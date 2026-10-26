# Contributing to Dicty

Thank you for your interest in contributing to Dicty! Dicty is an open-source, local-first voice dictation application built for speed, privacy, and minimalist design.

---

## 1. Architecture Overview

Dicty operates as three coordinated local processes:

1. **Dicty.app** (`DictyClient/Sources/DictyClient`):
   - Native macOS SwiftUI and AppKit application.
   - Handles global hotkeys, CoreAudio recording, keystroke injection (paste), and floating overlays (`RecordingOverlay`).
2. **Dicty Engine** (`dicty_engine.py`, `localhost:8075`):
   - Fast cross-platform FastAPI backend (Python).
   - Manages speech pipeline orchestration, local normalization, snippets, format styles, and SQLite history.
3. **whisper-server** (`whisper.cpp` Metal server, random localhost port):
   - Child process of the Python engine.
   - Keeps the active speech-to-text model loaded in RAM/GPU for sub-300ms inference.

---

## 2. Development Setup

### macOS Prerequisites
- macOS 14.0+
- Xcode 15+ (or Command Line Tools)
- Python 3.11+
- CMake & Ninja (for building `whisper.cpp`)

### Quick Start
```bash
# 1. Clone repository
git clone https://github.com/dicty-io/dicty.git
cd dicty

# 2. Setup Python environment
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Compile local whisper.cpp server
./scripts/compile_whisper.sh

# 4. Run the backend engine
python dicty_engine.py

# 5. In another terminal, run the macOS client
cd DictyClient
swift run
```

---

## 3. Engineering Guidelines & Constraints

### Latency Budget (Speed is the Product)
- Local STT runs in ~250 ms. Every LLM stage adds 0.4–3.0 s.
- **Never** add an LLM step for something that deterministic regex or rules can accomplish.
- Vocabulary replacements and Snippets must always execute with ~0 ms overhead before/after LLMs.

### SwiftUI Performance
- `EngineClient` is observed by many views. Never trigger `@Published` changes from polling if values have not changed.
- Never compute derived data (sorts, medians, filters) inside view bodies or `ForEach` loops.
- Use `LazyVStack` for scrolling lists.

### Visual Design System
- **Accent Color**: The accent color is user-configurable (`Color.appAccent`). Never hardcode fixed brand colors.
- **Restraint**: Keep the UI neutral and clean. Avoid decorative radial gradients, glows, or unneeded containers.
- **Shadows**: Apply shadows to background shapes (`RoundedRectangle(...).fill(...).shadow(...)`), never to outer containers (`VStack`, `HStack`, `Button`), which blurs internal text.

---

## 4. Running Tests

Before submitting a Pull Request, verify that all test suites pass:

```bash
# Run backend Python test suite
.venv/bin/python3 -m unittest discover tests -p "test_*.py"

# Run Swift client test suite
cd DictyClient
swift test
```

---

## 5. Security & Privacy Policy

- Dicty enforces strict privacy: telemetry is **disabled by default**, and no transcripts, audio, user emails, or active window names are ever collected or transmitted.
- See [`docs/telemetry.md`](docs/telemetry.md) and [`SECURITY.md`](SECURITY.md) for full security and privacy specifications.
