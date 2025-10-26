import argparse
import os
import sys
import tempfile

import soundfile as sf  # to read/write audio files
import requests  # fallback if you want direct HTTP calls
from fish_audio_sdk import Session, TTSRequest  # install via pip install fish-audio-sdk

def transcribe_audio(api_key: str, audio_path: str, language: str = None) -> str:
    """
    Send the user’s audio file to Fish Audio’s ASR (speech-to-text) endpoint,
    return the transcribed text.
    """
    session = Session(api_key)
    # SDK may not yet have a dedicated ASR wrapper, so we’ll call via requests directly
    url = "https://api.fish.audio/v1/asr"
    headers = {
        "Authorization": f"Bearer {api_key}",
    }

    files = {
        "audio": open(audio_path, "rb"),
    }
    data = {
        "ignore_timestamps": "true",
    }
    if language:
        data["language"] = language

    print(f"Uploading audio for transcription: {audio_path}")
    resp = requests.post(url, headers=headers, files=files, data=data)
    resp.raise_for_status()
    result = resp.json()
    text = result.get("text", "")
    print(f"Transcribed text: {text}")
    return text

def generate_voice(api_key: str, text: str, voice_model: str = None, output_path: str = "output.mp3") -> None:
    """
    Use Fish Audio’s TTS (text-to-speech) endpoint to generate speech from text.
    You may select a voice_model or voice reference if supported.
    """
    session = Session(api_key)
    tts_req = TTSRequest(
        text=text,
        # If you have a specific voice model/reference_id, set it:
        reference_id=voice_model,
        # customize other params if you like:
        format="mp3",
        sample_rate=44100,
        mp3_bitrate=128,
        # prosody etc:
        prosody={"speed": 1.0, "volume": 0},
    )

    print(f"Generating speech for text: {text}")
    with open(output_path, "wb") as f:
        for chunk in session.tts(tts_req):
            f.write(chunk)

    print(f"Generated speech saved to: {output_path}")

def main():
    parser = argparse.ArgumentParser(description="Transcribe and generate voice using Fish Audio API.")
    parser.add_argument("--api_key", required=True, help="Your Fish Audio API key")
    parser.add_argument("--input_audio", required=True, help="Path to the user’s input audio file")
    parser.add_argument("--voice_model", required=False, help="Reference voice model/ID to use for the TTS (if any)")
    parser.add_argument("--output_audio", default="output.mp3", help="Path to save generated voice audio")
    parser.add_argument("--language", required=False, help="Language code of the input audio (e.g., 'en', 'ja') for ASR")

    args = parser.parse_args()

    api_key = args.api_key
    input_audio = args.input_audio
    voice_model = args.voice_model
    output_audio = args.output_audio
    language = args.language

    # Step 1: Transcribe user audio
    transcribed = transcribe_audio(api_key, input_audio, language=language)

    # Step 2: Generate voice from transcribed text
    generate_voice(api_key, transcribed, voice_model=voice_model, output_path=output_audio)

if __name__ == "__main__":
    main()
