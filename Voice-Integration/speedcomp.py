import io, wave, sounddevice as sd, requests, json, time

# ============================
# 🔑 API KEYS & ENDPOINTS
# ============================
FISH_API_KEY = "5bb45d634f4e4982a0fd2502998d9882"
DEEPGRAM_API_KEY = "0808982bf713768f07310c148dca808d3a4f254e"

FISH_URL = "https://api.fish.audio/v1/asr"
DEEPGRAM_URL = "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true"

# ============================
# 🎙️ AUDIO SETTINGS
# ============================
CHUNK_SEC = 20
SR = 44100

def record_chunk():
    """Record a short chunk of audio from the microphone."""
    print(f"Recording {CHUNK_SEC} seconds of audio...")
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

# ============================
# 🐟 FISH AUDIO REQUEST
# ============================
def transcribe_fish(wav_bytes):
    files = {"audio": ("chunk.wav", io.BytesIO(wav_bytes), "audio/wav")}
    payload = {"language": "en", "ignore_timestamps": "false"}
    headers = {"Authorization": f"Bearer {FISH_API_KEY}"}

    start = time.time()
    r = requests.post(FISH_URL, data=payload, files=files, headers=headers)
    elapsed = time.time() - start

    try:
        res = r.json()
        text = res.get("text") or res.get("transcript") or str(res)
    except Exception:
        text = r.text

    return elapsed, text.strip()

# ============================
# 🧠 DEEPGRAM REQUEST
# ============================
def transcribe_deepgram(wav_bytes):
    headers = {
        "Authorization": f"Token {DEEPGRAM_API_KEY}",
        "Content-Type": "audio/wav"
    }

    start = time.time()
    r = requests.post(DEEPGRAM_URL, headers=headers, data=wav_bytes)
    elapsed = time.time() - start

    try:
        res = r.json()
        # Debug: print the entire structure if needed
        # print(json.dumps(res, indent=2))

        # Deepgram response format:
        # {
        #   "results": {
        #       "channels": [
        #           {
        #               "alternatives": [
        #                   {"transcript": "hello world", ...}
        #               ]
        #           }
        #       ]
        #   }
        # }
        transcript = ""
        if "results" in res:
            results = res["results"]
            if isinstance(results, dict) and "channels" in results:
                channels = results["channels"]
                if len(channels) > 0:
                    alternatives = channels[0].get("alternatives", [])
                    if len(alternatives) > 0:
                        transcript = alternatives[0].get("transcript", "")
            elif isinstance(results, list):  # fallback if Deepgram returns a list
                for r_ in results:
                    if "channels" in r_:
                        alt = r_["channels"][0].get("alternatives", [])
                        if len(alt) > 0:
                            transcript = alt[0].get("transcript", "")
                            break

        # fallback to any text field if not found
        if not transcript and "text" in res:
            transcript = res["text"]

        return elapsed, transcript.strip()
    except Exception as e:
        print("ASR request failed:", e)
        return elapsed, ""


# ============================
# 🚀 MAIN BENCHMARK
# ============================
if __name__ == "__main__":
    wav_bytes = record_chunk()

    print("\n=== Benchmarking Transcription APIs ===\n")

    fish_time, fish_text = transcribe_fish(wav_bytes)
    deep_time, deep_text = transcribe_deepgram(wav_bytes)

    print("🐟 Fish Audio:")
    print(f"  Time: {fish_time:.2f} s")
    print(f"  Transcript: {fish_text}\n")

    print("🧠 Deepgram:")
    print(f"  Time: {deep_time:.2f} s")
    print(f"  Transcript: {deep_text}\n")

    print("=== Summary ===")
    faster = "Fish Audio" if fish_time < deep_time else "Deepgram"
    print(f"{faster} was faster by {abs(fish_time - deep_time):.2f} seconds.")
