<p align="center">
  <img src="assets/dicty-icon.png" alt="Dicty Logo" width="110" height="110" />
</p>

<h1 align="center">Dicty</h1>

<p align="center">
  <b>Fast, private AI voice dictation and autonomous engineering documentation for macOS.</b>
</p>

<p align="center">
  <a href="https://github.com/vkazmin/dicty/releases/latest"><img src="https://img.shields.io/github/v/release/vkazmin/dicty?color=5D6658&label=Latest%20Release" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey" alt="Platform: macOS 13.0+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Optimized-success" alt="Apple Silicon Optimized">
  <a href="https://dicty.io"><img src="https://img.shields.io/badge/website-dicty.io-4A5568" alt="Website"></a>
  <img src="https://img.shields.io/badge/privacy-100%25%20On--Device%20Available-brightgreen" alt="100% On-Device Available">
  <img src="https://img.shields.io/badge/license-MIT-blue" alt="License: MIT">
</p>

---

## ⚡ Download & Install

### Option 1: Homebrew (Recommended)

```bash
brew tap dicty-io/dicty
brew install --cask dicty
xattr -cr /Applications/Dicty.app
```

### Option 2: Direct DMG Download

1. Download **[Dicty.dmg](https://github.com/vkazmin/dicty/releases/latest)** from the latest release.
2. Drag **Dicty** to your **Applications** folder.
3. Open Dicty from Applications.

> **Note**: If prompted by macOS Gatekeeper on initial launch, allow the application in **System Settings → Privacy & Security** or run:
> ```bash
> xattr -cr /Applications/Dicty.app
> ```

---

## 💡 What is Dicty?

**Dicty** is a native macOS speech-to-text companion designed for developers, creators, and professionals who think out loud. Built with high-performance Swift, AppKit, and an optimized local AI engine, Dicty delivers sub-400ms transcription with zero friction. 

Whether you are dictating code comments in Cursor, replying to Slack threads, recording a multi-person standup, or staging architectural thoughts alongside your Git commits, Dicty turns spoken words into clean, context-aware text instantly inserted at your cursor.

---

## 🌟 Key Features

### ⚡ Blazingly Fast & Sub-400ms Latency
- Native Apple Silicon Metal acceleration and optimized inference kernels.
- Instant, non-blocking text insertion into any active app (`Cmd + V` emulation via native `CGEvent`).
- Works seamlessly across Cursor, VS Code, Xcode, Obsidian, Slack, Linear, Chrome, Notes, and the Terminal.

### ⌨️ Double-Tap Modifier Shortcuts & Push-to-Talk
- Trigger dictation naturally using macOS-style double taps: **`2× Fn`**, **`2× ⌥ Option`**, **`2× ⌘ Command`**, or **`2× ⇧ Shift`**.
- Flexible trigger modes: **Toggle (Tap to Start / Tap to Stop)** or **Hold to Record (Push-to-Talk)**.
- Full support for arbitrary custom key combinations with built-in hardware debounce.

### 🏗️ Autonomous Architecture Documentation & Queue
- **The Developer Superpower**: Stop letting critical architecture decisions vanish into thin air.
- Dicty provides an **Architecture Staging Queue** that captures spontaneous voice reflections and links them with Git branches, commit diffs, and PR metadata.
- Autonomously synthesizes structured **Architecture Decision Records (ADRs)** and technical notes directly into **Obsidian**, **Confluence**, or local Markdown repositories.
- Integrated **Architecture Librarian** mode cross-references existing documentation before formatting new notes.

### 👥 Speaker Diarization (Multi-Speaker Dialogue)
- Transcribe meetings, design reviews, and customer interviews with automatic speaker separation (`Speaker 1`, `Speaker 2`).
- Automatically generates executive summaries, key decisions, and actionable task checklists.

### 🛡️ Incognito Mode & Clipboard Protector
- **Incognito Mode**: Toggle on for sensitive dictation. Dicty processes everything strictly in volatile RAM — zero audio recordings or transcripts are saved to local SQLite history or disk cache.
- **Clipboard Protector**: Dicty automatically preserves your existing clipboard content, executes the paste into your focused application, and immediately restores your original clipboard without corruption.

### 🎧 Intelligent Media Playback Ducking & Pausing
- Synchronously pauses or ducks media playback (Spotify, Apple Music, YouTube, and web media) the instant you trigger recording.
- Automatically and gracefully resumes playback once dictation finishes.

### 🎭 Custom Modes, Vocabulary & System Prompts
- Tailor speech post-processing to your exact workflow:
  - **General Dictation**: Fluid natural language with intelligent punctuation and formatting.
  - **Code & Technical**: Preserves camelCase, snake_case, syntax conventions, and markdown formatting.
  - **Architecture Librarian**: Technical documentation formatted with rationale, trade-offs, and references.
  - **Meeting Assistant**: Speaker breakdown, bulleted action items, and concise summaries.
  - **Prose & Book Writing**: Preserves literary tone, rhythm, and long-form structure.
- **Custom Vocabulary**: Define personal keywords, acronyms, team jargon, and product names for zero-typo transcription.

### 🔒 100% Privacy-First & Model Flexibility
- **Fully Offline**: Run entirely locally with on-device Whisper models, Ollama, or LM Studio without an internet connection.
- **Cloud Flexibility**: Connect your own API keys for OpenRouter, Anthropic Claude, OpenAI (GPT-4o), Google Gemini, or Groq whenever you desire ultra-large language model post-processing.

### 🔄 Transcript History & One-Click Re-Processing
- Searchable local history of all past transcriptions.
- **1-Click Re-processing**: Re-run any past audio recording through a different mode, custom prompt, or model without re-speaking.
- One-click copy, markdown export, and deletion.

---

## 💡 Architecture Documentation in Action

Dicty bridges the gap between fast spoken developer thoughts and committed codebase architecture:

> **🎙️ Dicty · Voice Capture** `[00:42]`  
> *"We're moving the API observer to an event-driven queue so retries don't block the main thread and backpressure can be handled cleanly…"*
>
> **📎 Attached Context**:  
> `PR #142: Refactor API observer` · `commit a3f9c1: queue adapter` · `LIN-284: Event-driven retries`

#### 📄 Synthesized Output (`architecture/api-observer.md`):

```markdown
# ADR-008: Event-Driven Queue for API Observer

## Status
Accepted

## Context & Rationale
Under burst traffic, synchronous retry loops on the API observer were causing thread starvation on the primary worker pool.

## Decision
Migrated the observer pipeline to an asynchronous event-driven queue adapter.

## Consequences
- Retries no longer block the main thread.
- Downstream backpressure is handled gracefully with exponential backoff.

## References
→ PR #142 · Commit a3f9c1 · Linear LIN-284
```

---

## 🚀 How It Works

```
  [ Press Hotkey / 2× Fn ]
             │
             ▼
   🎙️ Floating Native HUD  ────► CoreAudio capture (16kHz PCM)
             │
             ▼
   🧠 Whisper / Local Engine ──► Metal GPU / CoreML sub-400ms STT
             │
             ▼
   ✨ Mode Post-Processor    ──► Clean punctuation, formatting & jargon
             │
             ▼
   📋 Clipboard Protector    ──► Backup clipboard ➔ Paste (Cmd+V) ➔ Restore clipboard
```

1. **Press your Hotkey**: Double-tap `Fn` (or your custom shortcut) anywhere on macOS to invoke the floating HUD.
2. **Speak Naturally**: Talk at your normal conversational speed. Dicty handles spoken punctuation, pauses, and speech filtering.
3. **Instant Insertion**: Dicty polishes the text and pastes it right where your cursor is blinking.

---

## 🏗️ Technical Architecture

Dicty is engineered for zero battery drain, instant responsiveness, and rock-solid stability:

- **Frontend Client (`DictyClient`)**:
  - Written in **Swift 5.9** / **SwiftUI** & **AppKit**.
  - Borderless, floating HUD with glassmorphic design and real-time audio waveform animations.
  - Native `NSEvent` global monitor and `CGEvent` synthesis for zero-latency shortcut detection and text injection.
  - Media session control via AppleScript and native MediaRemote APIs.
- **Backend Core Engine (`dicty-backend`)**:
  - Embedded high-performance **Python / FastAPI** service bundled via PyInstaller.
  - Accelerated speech recognition leveraging local Whisper / Faster-Whisper with Apple Silicon Metal support.
  - SQLite local database for fast, private history caching with WAL mode.
  - Robust inter-process communication (IPC) over high-speed local loopback with health-check watchdog.

---

## 🛠️ Building From Source

### Prerequisites

- macOS 13.0 (Ventura) or later

### Clone & Run

```bash
# Clone repository
git clone https://github.com/vkazmin/dicty.git
cd dicty

# Build and run the Swift client
cd DictyClient
swift run
```

---

## 📬 Contact & Support

- **Website**: [dicty.io](https://dicty.io)
- **Email**: [hello@dicty.io](mailto:hello@dicty.io)

---

<p align="center">
  <sub>Made with ❤️ for macOS developers and thinkers.</sub>
</p>
