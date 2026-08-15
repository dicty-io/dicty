<h1 align="center">Dicty</h1>

<p align="center">
  <b>Fast, private AI voice dictation and autonomous engineering documentation for macOS.</b>
</p>

<p align="center">
  <a href="https://github.com/vkazmin/dicty/releases/latest"><img src="https://img.shields.io/github/v/release/vkazmin/dicty?color=5D6658&label=Latest%20Release" alt="Latest Release"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey" alt="Platform: macOS 13.0+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Optimized-success" alt="Apple Silicon Optimized">
</p>

---

## ⚡ Download & Install

### Option 1: Homebrew (Recommended)

```bash
brew tap vkazmin/dicty
brew install --cask dicty
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

## 🌟 Key Features

- **⚡ Fast & On-Device**: High-accuracy local speech-to-text with instantaneous text insertion into any active app (`Cmd + V`).
- **👥 Speaker Diarization (Alpha)**: Multi-speaker dialogue reconstruction for meetings, interviews, and videos with executive summaries and action checklists.
- **🏗️ Architecture Documentation Queue**: Staging buffer for voice thoughts, Git commits, and PR metadata to autonomously synthesize structured technical documentation into **Obsidian**, **Confluence**, or local markdown files.
- **🎭 Configurable Profiles & Modes**: Dedicated workflows for *General Dictation*, *Prose & Book Writing*, *Meeting Assistant*, *Focused App Audio Capture*, and *Architecture Librarian*.
- **🔒 Privacy First**: Run 100% offline using local models (Whisper, Ollama, LM Studio) or connect cloud models (OpenRouter, Anthropic, OpenAI).
- **🎧 Media Playback Ducking**: Automatically pauses or ducks media playback (Spotify, Apple Music, YouTube) while you speak and resumes when finished.

---

## 🚀 How It Works

1. **Press your Hotkey**: Tap your custom shortcut (or `Fn` key) anywhere on macOS to open the floating recording HUD.
2. **Speak Naturally**: Talk at your normal conversational pace. Dicty handles spoken punctuation and audio cleanup in real time.
3. **Instant Insertion**: Dicty automatically formats and pastes the polished text into your active editor, IDE, chat, or browser.


---

## 📬 Contact & Support

- **Website**: [dicty.io](https://dicty.io)
- **Email**: [hello@dicty.io](mailto:hello@dicty.io)
- **Issues**: [GitHub Issues](https://github.com/dicty-io/dicty/issues)
