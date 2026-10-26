#!/usr/bin/env python3
"""
Dicty Telemetry & Metrics Analyzer
Reads ~/.dicty/telemetry.jsonl and displays a real-time analytics matrix in the terminal.
"""
import os
import json
from collections import Counter
from datetime import datetime

TELEMETRY_FILE = os.path.expanduser("~/.dicty/telemetry.jsonl")

def analyze():
    if not os.path.exists(TELEMETRY_FILE):
        print("\n[!] No telemetry events recorded yet. Start dictating to generate data!")
        print(f"    Expected path: {TELEMETRY_FILE}\n")
        return

    events = []
    with open(TELEMETRY_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    events.append(json.loads(line))
                except Exception:
                    pass

    if not events:
        print("\n[!] Telemetry log is empty.\n")
        return

    print("\n" + "═" * 70)
    print(f"📊  DICTY TELEMETRY & METRICS MATRIX  (Total Events: {len(events)})")
    print("═" * 70)

    # 1. Event Distribution Breakdown
    event_counts = Counter([e.get("event", "unknown") for e in events])
    print("\n📌 EVENT COUNTS:")
    for evt, count in event_counts.most_common():
        pct = (count / len(events)) * 100
        bar = "█" * int(pct / 5)
        print(f"  • {evt:<26} : {count:>4} ({pct:>5.1f}%) {bar}")

    # 2. Dictation Performance & Usage Matrix
    dictations = [e for e in events if e.get("event") == "transcription_completed"]
    if dictations:
        total_words = sum(e.get("properties", {}).get("text_word_count", 0) for e in dictations)
        latencies = [e.get("properties", {}).get("total_latency_ms", 0) for e in dictations if e.get("properties", {}).get("total_latency_ms")]
        avg_latency = sum(latencies) / len(latencies) if latencies else 0.0
        wpms = [e.get("properties", {}).get("speaking_wpm", 0) for e in dictations if e.get("properties", {}).get("speaking_wpm")]
        avg_wpm = sum(wpms) / len(wpms) if wpms else 0.0

        print("\n🎙️  DICTATION METRICS:")
        print(f"  • Total Completed Dictations : {len(dictations)}")
        print(f"  • Total Words Spoken         : {total_words}")
        print(f"  • Average Total Latency      : {avg_latency:.1f} ms")
        print(f"  • Average Speaking WPM       : {avg_wpm:.1f} WPM")

    # 3. Mode & Style Adoption Breakdown
    modes = Counter([e.get("properties", {}).get("mode") for e in dictations if e.get("properties", {}).get("mode")])
    if modes:
        print("\n⚙️  ACTIVE MODES USED:")
        for m, count in modes.most_common():
            print(f"  • {m:<26} : {count:>4} use(s)")

    styles = Counter([e.get("properties", {}).get("dictation_format_style") for e in dictations if e.get("properties", {}).get("dictation_format_style")])
    if styles:
        print("\n✍️  PROSE & FORMATTING STYLES:")
        for s, count in styles.most_common():
            print(f"  • {s:<26} : {count:>4} use(s)")

    # 4. Whisper Models Matrix
    model_switches = Counter([e.get("properties", {}).get("model_id") for e in events if e.get("event") == "model_switched"])
    model_downloads = Counter([e.get("properties", {}).get("model_id") for e in events if e.get("event") == "model_download_completed"])
    if model_switches or model_downloads:
        print("\n🧠 WHISPER MODELS:")
        for m, count in model_switches.most_common():
            print(f"  • Loaded: {m:<20} : {count:>4} switch(es)")
        for m, count in model_downloads.most_common():
            print(f"  • Downloaded: {m:<16} : {count:>4} download(s)")

    # 5. Target Application Injections Matrix
    injections = [e for e in events if e.get("event") == "text_injected"]
    if injections:
        apps = Counter([e.get("properties", {}).get("target_app_name", "Unknown") for e in injections])
        print("\n🎯 TOP TARGET APPS (Where users dictate):")
        for app_name, count in apps.most_common(5):
            print(f"  • {app_name:<26} : {count:>4} paste(s)")

    # 6. Device Context & Demographics
    first_event = events[0]
    ctx = first_event.get("context", {})
    print("\n💻 HOST METADATA:")
    print(f"  • OS & Platform              : {ctx.get('os.name')} {ctx.get('os.version')} ({ctx.get('host.arch')})")
    print(f"  • App Version                : {ctx.get('app.version')}")
    print(f"  • Anonymous Distinct ID      : {first_event.get('distinct_id')}")

    print("\n" + "═" * 70 + "\n")

if __name__ == "__main__":
    analyze()
