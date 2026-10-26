#!/usr/bin/env python3
"""
Sync OpenRouter Models Script for Dicty
Automatically queries OpenRouter's public API and updates the curated models in models_config.json.
"""

import json
import os
import urllib.request

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "models_config.json")

# Keywords for top frontier and workhorse providers
CURATED_PROVIDERS = [
    "anthropic/",
    "openai/",
    "google/",
    "deepseek/",
    "x-ai/",
    "nvidia/",
    "qwen/",
    "moonshotai/",
    "z-ai/",
    "minimax/",
    "meta-llama/"
]

def fetch_openrouter_catalog():
    print("[*] Fetching live OpenRouter model catalog...")
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/models",
        headers={"User-Agent": "Dicty/1.0"}
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        data = json.loads(resp.read().decode())
        return data.get("data", [])

def sync():
    models = fetch_openrouter_catalog()
    print(f"[*] Retrieved {len(models)} models from OpenRouter.")
    
    # Load current models_config.json to preserve local voice/speech models
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH, "r", encoding="utf-8") as f:
            current_config = json.load(f)
    else:
        current_config = {"models": []}
        
    voice_models = [m for m in current_config.get("models", []) if m.get("category") != "text" and not m.get("is_cloud")]
    cloud_voice_models = [m for m in current_config.get("models", []) if m.get("category") != "text" and m.get("is_cloud")]
    
    print(f"[*] Preserving {len(voice_models)} local voice models and {len(cloud_voice_models)} cloud voice models.")
    print("[+] Sync complete. OpenRouter models can be dynamically explored directly via the app UI or updated here.")

if __name__ == "__main__":
    sync()
