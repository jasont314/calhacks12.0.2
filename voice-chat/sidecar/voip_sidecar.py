# voip_sidecar.py
# Minimal headless Mumble client with local UDP control for PTT/join/shutdown.
# Requires: pip install pymumble sounddevice numpy ; brew install opus

import argparse, socket, json, threading, queue, sys, time
import numpy as np
import sounddevice as sd
from pymumble import Mumble, constants

# ---- config ----
SR = 48000          # sample rate
CHUNK = 960         # ~20ms at 48k
CHANNELS = 1

# ---- globals ----
mumble = None
connected_evt = threading.Event()
ptt_enabled = threading.Event()      # set() = mic on; clear() = mic off
shutdown_evt = threading.Event()

play_q = queue.Queue(maxsize=50)     # incoming PCM for playback

# ---- control server ----
def control_loop(sock):
    while not shutdown_evt.is_set():
        try:
            data, _ = sock.recvfrom(4096)
            msg = json.loads(data.decode("utf-8").strip())
            cmd = msg.get("cmd")
            if cmd == "ptt":
                if bool(msg.get("state")):
                    ptt_enabled.set()
                else:
                    ptt_enabled.clear()
            elif cmd == "join":
                ch = msg.get("channel") or "Demo"
                try_join_channel(ch)
            elif cmd == "leave":
                try_join_channel("")  # root
            elif cmd == "shutdown":
                shutdown_evt.set()
                break
        except Exception as e:
            print("CTRL error:", e, file=sys.stderr)

# ---- mumble helpers ----
def try_join_channel(name: str):
    if not mumble or not mumble.is_ready():
        return
    target = None
    chans = mumble.channels
    # exact match first
    for cid, ch in chans.items():
        if ch['name'] == name:
            target = cid
            break
    # root if not found or name empty
    if target is None:
        target = 0
    mumble.users.myself.move_in(target)

def on_sound_received(user, soundchunk):
    """
    pymumble provides decoded PCM (int16) in soundchunk.pcm (mono or stereo).
    For safety, convert to mono int16 numpy and enqueue for playback.
    """
    try:
        pcm = soundchunk.pcm  # bytes or numpy array depending on version
        if isinstance(pcm, bytes):
            arr = np.frombuffer(pcm, dtype=np.int16)
        else:
            arr = np.asarray(pcm, dtype=np.int16)
        # if stereo, downmix to mono
        if arr.ndim == 1:
            mono = arr
        else:
            mono = arr.mean(axis=1).astype(np.int16)
        if not play_q.full():
            play_q.put_nowait(mono)
    except Exception as e:
        print("recv error:", e, file=sys.stderr)

def mumble_thread(server, port, username, password, channel):
    global mumble
    mumble = Mumble(server, user=username, port=port, password=password, debug=False, reconnect=True)
    # register callbacks
    mumble.callbacks.set_callback(constants.PYMUMBLE_CLBK_SOUNDRECEIVED, on_sound_received)
    mumble.start()
    mumble.is_ready()  # blocks until connected
    connected_evt.set()
    print("[sidecar] connected to murmur", flush=True)
    if channel:
        try_join_channel(channel)

    # keep thread alive until shutdown
    while not shutdown_evt.is_set():
        time.sleep(0.1)

    try:
        mumble.stop()
    except Exception:
        pass

# ---- audio I/O ----
def mic_loop():
    """
    When PTT is ON, read mic frames and feed to mumble.
    Expect int16 mono at SR.
    """
    def on_frames(indata, frames, time_info, status):
        if shutdown_evt.is_set():
            raise sd.CallbackStop()
        if not ptt_enabled.is_set() or not mumble or not mumble.is_ready():
            return
        # indata: float32 [-1,1] by default; convert to int16 PCM
        mono = indata[:, 0] if indata.ndim > 1 else indata
        pcm_i16 = (np.clip(mono, -1.0, 1.0) * 32767.0).astype(np.int16)
        try:
            mumble.sound_output.add_sound(pcm_i16.tobytes())
        except Exception as e:
            # Some pymumble builds accept numpy array directly:
            try:
                mumble.sound_output.add_sound(pcm_i16)
            except Exception:
                print("send error:", e, file=sys.stderr)

    with sd.InputStream(samplerate=SR, channels=CHANNELS, blocksize=CHUNK, dtype='float32', callback=on_frames):
        while not shutdown_evt.is_set():
            time.sleep(0.05)

def speaker_loop():
    """
    Continuously play whatever arrives from other users.
    """
    with sd.OutputStream(samplerate=SR, channels=1, blocksize=CHUNK, dtype='int16'):
        while not shutdown_evt.is_set():
            try:
                buf = play_q.get(timeout=0.1)
                sd.play(buf, samplerate=SR, blocking=True)
            except queue.Empty:
                pass
            except Exception as e:
                print("play error:", e, file=sys.stderr)

# ---- main ----
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", required=True)
    ap.add_argument("--port", type=int, default=64738)
    ap.add_argument("--username", required=True)
    ap.add_argument("--password", default=None)
    ap.add_argument("--channel", default="Demo")
    ap.add_argument("--ctrl-port", type=int, default=7878, help="UDP control port (0=auto)")
    args = ap.parse_args()

    # Control UDP
    ctrl_sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    ctrl_sock.bind(("127.0.0.1", args.ctrl_port))
    print(f"[sidecar] control_port={ctrl_sock.getsockname()[1]}", flush=True)

    # Threads
    threads = [
        threading.Thread(target=control_loop, args=(ctrl_sock,), daemon=True),
        threading.Thread(target=mumble_thread, args=(args.server, args.port, args.username, args.password, args.channel), daemon=True),
        threading.Thread(target=mic_loop, daemon=True),
        threading.Thread(target=speaker_loop, daemon=True),
    ]
    for t in threads: t.start()

    # Wait until shutdown
    try:
        while not shutdown_evt.is_set():
            time.sleep(0.2)
    except KeyboardInterrupt:
        pass
    shutdown_evt.set()
    time.sleep(0.3)

if __name__ == "__main__":
    main()
