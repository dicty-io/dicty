

<h1 align="center">Dicty</h1>

<p align="center">
  <b>Fast, private AI voice dictation and autonomous engineering documentation for macOS.</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013.0%2B-lightgrey" alt="Platform: macOS 13.0+">
  <img src="https://img.shields.io/badge/Apple%20Silicon-Optimized-success" alt="Apple Silicon Optimized">
</p>

---

## Highlights

- **Fast & Responsive**: Real-time on-device voice transcription with instant text injection into your active apps.
- **Speaker Diarization (Alpha)**: Multi-speaker dialogue reconstruction for meetings, interviews, and videos with summaries and action items.
- **Architecture Queue**: Ingests voice thoughts, Git commits, and PR metadata to generate structured technical documentation directly in Obsidian, Confluence, or local files.
- **Configurable Profiles**: Dedicated modes for general dictation, long-form writing/prose, meetings, specific application audio capture, and architecture documentation.
- **Local & Cloud Model Support**: Run 100% offline using local models (Whisper, Ollama, LM Studio) or connect cloud providers like OpenRouter and Anthropic.
- **Media Controls**: Automatically pauses or ducks media playback while you speak and resumes when done.

---

## Installation

### Homebrew

```bash
brew tap vkazmin/dicty
brew install --cask dicty
