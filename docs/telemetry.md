# Dicty Telemetry Policy & Privacy Architecture

Dicty is an open-source, local-first voice dictation application designed with privacy as a foundational principle.

---

## 1. Core Principles

1. **Strictly Opt-In by Default**: Telemetry is completely disabled unless you explicitly turn on **"Share anonymous usage statistics"** in *Settings $\rightarrow$ Diagnostics*.
2. **Zero PII (Personally Identifiable Information)**: Dicty never collects, stores, or transmits:
   - Voice audio recordings
   - Spoken transcripts or corrected text
   - Account email addresses or user identities
   - Active application names or bundle IDs (`target_app_name`, `target_app_bundle_id`)
   - Clipboard contents
3. **Anonymized Installation ID**: If telemetry is enabled, events are linked only to a random UUIDv4 (`distinct_id`) generated locally on your machine.
4. **Transparent & Auditable**: The entire telemetry dispatch code is open source and available for review in:
   - Client dispatcher: [`DictyClient/Sources/DictyClient/TelemetryClient.swift`](file:///Users/vasiliikazmin/projects/dicty/DictyClient/Sources/DictyClient/TelemetryClient.swift)
   - Engine telemetry hub: [`services/telemetry_service.py`](file:///Users/vasiliikazmin/projects/dicty/services/telemetry_service.py)

---

## 2. What Is Collected (Only When Opted In)

When opted in, Dicty collects aggregate operational and performance metrics to help diagnose bugs and optimize speech model latency:

| Event Name | Purpose | Example Properties |
| :--- | :--- | :--- |
| `app_launched` | Application health and startup success | `accessibility_granted: true`, `microphone_granted: true` |
| `text_injected` | Keystroke injection health | `is_trusted_accessibility: true` |
| `recording_started` / `recording_canceled` | Session usage count | `mode: "dictation"` |
| `transcription_completed` | Model latency & performance | `model_id: "tiny.en"`, `duration_s: 2.4`, `engine_ms: 180` |
| `model_download_started` / `completed` | Model manager download reliability | `model_id: "base.en"`, `success: true` |
| `mode_switched` | Active mode distribution | `active_mode: "dictation"` |

---

## 3. What Is Strictly Excluded / Redacted

Every event payload passes through an automated redaction filter before reaching any sink:

```python
_REDACTED_PROPS = {
    "user_id", "email", "target_app_name", "target_app_bundle_id",
    "text", "transcript", "audio", "title", "traits", "profile_name"
}
```

Any property matching this blacklist or prefixed with `user_` is immediately stripped and discarded.

---

## 4. How to Control Telemetry

### Via Dicty UI
1. Open Dicty settings (`⌘,`).
2. Navigate to **Diagnostics** or **Settings**.
3. Toggle **"Share anonymous usage statistics"** off.
   - When turned off, Dicty immediately disables the client dispatcher, stops engine event processing, and wipes any local `telemetry.jsonl` cache.

### Via Environment Variables
You can permanently disable telemetry at the environment level for all subprocesses and engine runs:

```bash
export DICTY_TELEMETRY=0
# or
export DICTY_TELEMETRY=false
```

When `DICTY_TELEMETRY=0` is set, all telemetry code paths become complete no-ops, regardless of any saved local preferences.

---

## 5. Local Diagnostics & Logs Export

Dicty provides a **Diagnostics Export** button in Settings that packages system logs and local performance stats into a `.zip` file on your Desktop. This file is generated entirely on-device and remains under your full control—it is never sent anywhere automatically.
