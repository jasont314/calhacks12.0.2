"""
Record audio from the user's microphone and save it as a .wav file.
Usage:
    python record_audio.py --filename user_input.wav --duration 5
"""

import argparse
import sounddevice as sd
import wavio

def record_audio(filename="user_input.wav", duration=5, samplerate=44100):
    """
    Records audio from the user's microphone and saves it to a .wav file.

    Args:
        filename (str): The name of the output .wav file.
        duration (int): Recording duration in seconds.
        samplerate (int): Sampling rate in Hz (default 44100 for CD quality).
    """
    print(f"🎙️ Recording for {duration} seconds... Speak now!")
    audio_data = sd.rec(int(duration * samplerate), samplerate=samplerate, channels=1, dtype='int16')
    sd.wait()  # Wait until recording is finished
    wavio.write(filename, audio_data, samplerate, sampwidth=2)
    print(f"✅ Recording saved as {filename}")

def main():
    parser = argparse.ArgumentParser(description="Record audio from microphone and save to .wav file.")
    parser.add_argument("--filename", type=str, default="user_input.wav", help="Output filename (default: user_input.wav)")
    parser.add_argument("--duration", type=int, default=5, help="Recording duration in seconds (default: 5)")
    args = parser.parse_args()

    record_audio(filename=args.filename, duration=args.duration)

if __name__ == "__main__":
    main()
