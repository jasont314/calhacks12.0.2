import io, wave, sounddevice as sd, requests, json, time
from websocket import create_connection

# 🔑 API key variables
DEEPGRAM_API_KEY = "0808982bf713768f07310c148dca808d3a4f254e"
DEEPGRAM_URL = "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true"
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
    """Send audio chunk to Deepgram for transcription."""
    headers = {
        "Authorization": f"Token {DEEPGRAM_API_KEY}",
        "Content-Type": "audio/wav"
    }

    try:
        response = requests.post(DEEPGRAM_URL, headers=headers, data=wav_bytes)
        response.raise_for_status()
        res_json = response.json()
        print("ASR response:", json.dumps(res_json, indent=2))

        # Deepgram's text path: results → channels → alternatives → transcript
        results = res_json.get("results", {})
        if results and "channels" in results:
            channels = results["channels"]
            if channels and "alternatives" in channels[0]:
                transcript = channels[0]["alternatives"][0].get("transcript", "")
                return transcript.strip()
        return str(res_json)
    except Exception as e:
        print("ASR request failed:", e)
        return ""

if __name__ == "__main__":
    ws = create_connection(GODOT_WS_URL)
    print("Connected to Godot WebSocket.")
    while True:
        wav_bytes = record_chunk()
        print("Recorded chunk, sending to Deepgram...")
        text = send_to_asr(wav_bytes)
        print("Transcript:", text)
        ws.send(text)
