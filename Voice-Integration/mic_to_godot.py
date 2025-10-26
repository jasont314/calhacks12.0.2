import io, wave, sounddevice as sd, requests, json, time
from websocket import create_connection

API_KEY = "5bb45d634f4e4982a0fd2502998d9882"
ASR_URL = "https://api.fish.audio/v1/asr"
GODOT_WS_URL = "ws://127.0.0.1:8765"  # Godot WebSocketServer

CHUNK_SEC = 5
SR = 44100

def record_chunk():
    audio = sd.rec(int(CHUNK_SEC * SR), samplerate=SR, channels=1, dtype='int16')
    sd.wait()
    buf = io.BytesIO()
    with wave.open(buf, 'wb') as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(SR)
        wf.writeframes(audio.tobytes())
    buf.seek(0)
    return buf.read()

def send_to_asr(wav_bytes):
    url = "https://api.fish.audio/v1/asr"

    # Write the chunk temporarily to memory so requests can send it as a file
    files = {
        "audio": ("chunk.wav", io.BytesIO(wav_bytes), "audio/wav")
    }
    payload = {
        "language": "en",
        "ignore_timestamps": "false"
    }
    headers = {
        "Authorization": "Bearer " + API_KEY
    }

    try:
        response = requests.post(url, data=payload, files=files, headers=headers)
        response.raise_for_status()  # Raise exception for HTTP errors
        res_json = response.json()
        print("ASR response:", res_json)

        # Return best available text field
        if "text" in res_json:
            return res_json["text"]
        elif "transcript" in res_json:
            return res_json["transcript"]
        else:
            return str(res_json)
    except Exception as e:
        print("ASR request failed:", e)
        return ""

if __name__ == "__main__":
    ws = create_connection(GODOT_WS_URL)
    print("Connected to Godot WebSocket.")
    while True:
        wav_bytes = record_chunk()
        print("Recorded chunk, sending to Fish Audio...")
        text = send_to_asr(wav_bytes)
        print("Transcript:", text)
        ws.send(text)
