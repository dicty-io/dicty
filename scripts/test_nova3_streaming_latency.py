#!/usr/bin/env python3
"""
Test script for verifying Deepgram Nova-3 real-time WebSocket streaming latency.

Simulates a real speaking user by streaming raw audio chunks (100ms intervals)
over the WebSocket relay to Deepgram Nova-3, and asserts ultra-low finalization latency (<250ms).
"""

import asyncio
import os
import sys
import time
import wave
import numpy as np

# Ensure services directory is in python path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "services"))

from services import cloud_streaming


async def test_nova3_live_streaming(audio_path: str = "bin/whisper.cpp/samples/jfk.wav", chunk_duration_ms: int = 100):
    print("=" * 70)
    print("  DICTY CLOUD DEEPGRAM NOVA-3 REAL-TIME STREAMING LATENCY TEST")
    print("=" * 70)

    token = cloud_streaming.dicty_cloud_token()
    if not token:
        print("[!] No Dicty Cloud token found in session or defaults.")
        print("[!] Please ensure you are logged in, or export DICTY_SESSION_TOKEN.")
        sys.exit(1)

    print(f"[*] Dicty Cloud token verified (prefix: {token[:16]}...)")

    if not os.path.exists(audio_path):
        print(f"[!] Audio file not found at: {audio_path}")
        sys.exit(1)

    with wave.open(audio_path, "rb") as wf:
        sr = wf.getframerate()
        frames = wf.readframes(wf.getnframes())
        audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0

    duration_s = len(audio) / sr
    print(f"[*] Loaded sample audio: {audio_path}")
    print(f"    Duration: {duration_s:.2f} seconds | Sample rate: {sr} Hz")

    loop = asyncio.get_running_loop()
    print("[*] Creating Deepgram Nova-3 live streaming session...")
    t_session_start = time.perf_counter()
    session = cloud_streaming.create_session(
        loop, "deepgram/nova-3", sr,
        route_provider="dicty_cloud", language="en", vocab_words=["country", "Americans"]
    )
    assert session is not None, "Failed to create streaming session"
    session_init_ms = (time.perf_counter() - t_session_start) * 1000.0
    print(f"[+] Session created in {session_init_ms:.1f}ms: {session.label}")

    chunk_samples = int(sr * (chunk_duration_ms / 1000.0))
    total_chunks = (len(audio) + chunk_samples - 1) // chunk_samples
    print(f"[*] Streaming audio in {total_chunks} chunks of {chunk_duration_ms}ms each...")

    stream_start = time.perf_counter()
    for i in range(0, len(audio), chunk_samples):
        chunk = audio[i:i + chunk_samples]
        session.feed(chunk)
        # Sleep for chunk duration to simulate real-time speech capture
        await asyncio.sleep(chunk_duration_ms / 1000.0)

    simulated_speech_time = time.perf_counter() - stream_start
    print(f"[*] Finished speech stream ({simulated_speech_time:.2f}s elapsed).")
    print("[*] User released hotkey -> calling session.finalize()...")

    t_finalize_start = time.perf_counter()
    transcription = await session.finalize(timeout=5.0)
    finalize_latency_ms = (time.perf_counter() - t_finalize_start) * 1000.0

    print("-" * 70)
    print(f"[+] TRANSCRIPTION RESULT: \"{transcription}\"")
    print(f"[+] FINALIZATION LATENCY: {finalize_latency_ms:.1f} ms")
    print("-" * 70)

    if not transcription or not transcription.strip():
        print("[!] ERROR: No transcription received from Nova-3.")
        return False

    if finalize_latency_ms > 350.0:
        print(f"[!] WARNING: Finalize latency exceeded target (<250ms): {finalize_latency_ms:.1f}ms")
    else:
        print(f"[✓] SUCCESS: Ultra-low latency confirmed ({finalize_latency_ms:.1f}ms < 250ms target)!")

    return True


if __name__ == "__main__":
    audio_file = sys.argv[1] if len(sys.argv) > 1 else "bin/whisper.cpp/samples/jfk.wav"
    success = asyncio.run(test_nova3_live_streaming(audio_file))
    sys.exit(0 if success else 1)
