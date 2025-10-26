# test_claude.py (Python test script)
import os
import requests
import json

API_KEY = os.getenv("CLAUDE_API_KEY")
API_URL = "https://api.anthropic.com/v1/messages"

def test_claude():
    headers = {
        "Content-Type": "application/json",
        "x-api-key": API_KEY,
        "anthropic-version": "2023-06-01"
    }
    
    body = {
        "model": "claude-sonnet-4-20250514",
        "max_tokens": 150,
        "system": "You are a helpful assistant.",
        "messages": [
            {
                "role": "user",
                "content": "Say hello in 10 words or less."
            }
        ]
    }
    
    response = requests.post(API_URL, headers=headers, json=body)
    
    print(f"Status: {response.status_code}")
    print(f"Response: {json.dumps(response.json(), indent=2)}")
    
    if response.status_code == 200:
        reply = response.json()["content"][0]["text"]
        print(f"\nClaude says: {reply}")
        return True
    return False

if __name__ == "__main__":
    if not API_KEY:
        print("ERROR: CLAUDE_API_KEY not set!")
    else:
        print("Testing Claude API...")
        test_claude()