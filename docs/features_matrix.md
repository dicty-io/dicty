# Dicty Platform Feature Parity & Matrix

> **Document Version:** 1.0.0  
> **Last Updated:** October 8, 2026  
> **Status:** Active / Source of Truth for Cross-Platform Parity  
> **Platforms Covered:** macOS Client (SwiftUI / AppKit native) & Windows Client (Tauri v2 + Rust + React/TypeScript)

---

## 1. Executive Summary

Dicty uses a unified **Python FastAPI backend engine** running locally on `localhost:8000` (handling CoreAudio/WASAPI recording, Whisper transcription, LLM post-processing, Diarization, and TTS). However, Dicty maintains two distinct client implementations tailored to their host operating systems:
1. **macOS Client (`DictyClient`):** Built natively with **SwiftUI & AppKit**, using macOS-specific system frameworks (`CoreAudio`, private `MediaRemote.framework`, `NSPanel`, `MenuBarExtra`, `AXUIElement`).
2. **Windows Client (`DictyClientTauri`):** Built with **Tauri v2 (Rust) + React 19 / TypeScript**, using Windows-specific APIs (`windows-rs`, `windows-sys`, WASAPI, Windows Media Transport Controls / GSMTC, `windows::Win32::UI::WindowsAndMessaging`).

Due to separate development tracks, several UI features, controls, and accessibility options exist on one platform but are missing or incomplete on the other. This document provides a granular comparison of all features, their implementation status, and exact architectural differences.

---

## 2. Core Feature Parity Matrix

### Legend
- 🟢 **Full Parity:** Implemented and functional on both platforms.
- 🟡 **Partial / Discrepancy:** Implemented on both, but with UI or functional gaps/differences between macOS and Windows.
- 🟠 **Windows Only:** Implemented in Windows Tauri UI, missing in macOS SwiftUI UI.
- 🔵 **macOS Only:** Implemented in macOS SwiftUI UI, missing in Windows Tauri UI.
- ⚪ **Planned / Engine Only:** Implemented in Python backend, but UI not exposed on either client.

---

### Comparison Table

| Category | Feature Name | Description | macOS (SwiftUI) | Windows (Tauri / React) | Parity Status & Technical Discrepancy Notes |
| :--- | :--- | :--- | :---: | :---: | :--- |
| **Audio Feedback** | **Sound Recording Feedback Toggle** | Play pleasant audible chimes on start and stop of dictation recording. | 🟢 Yes | 🟢 Yes | Both play start/stop cues. macOS uses `NSSound` (`Appearance.swift`), Windows uses Rust `rodio` (`sound.rs`). |
| **Audio Feedback** | **Sound Feedback Volume Slider** | Dedicated volume slider (0% - 100%) to control feedback chime loudness independently from system volume. | 🔴 **Missing** | 🟢 **Yes** | 🟠 **Windows Only.** Windows has a 0–100% volume slider in [PreferencesView.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/PreferencesView.tsx), scaling raw PCM samples in [sound.rs](file:///c:/projects/Personal/dicty/DictyClientTauri/src-tauri/src/sound.rs). macOS plays at fixed default system volume without slider. |
| **Audio Feedback** | **Custom Feedback Sound Files** | Select custom `.wav` / `.mp3` audio files or choose from bundled presets. | 🟢 Yes | 🟢 Yes | Full parity. macOS bundles `Funk.aiff`, `Pop.aiff`, etc. Windows bundles custom `.wav` chime files with browse/test dialogs. |
| **Audio Feedback** | **Sound Preview Button** | Test/audition the selected feedback sound directly in Settings before recording. | 🟢 Yes | 🟢 Yes | Both have preview buttons beside the sound picker. |
| **Audio & Media** | **Auto-Pause Media During Dictation** | Automatically pause playing music/podcasts when dictation begins, and resume when recording ends. | 🟢 **Yes (Exposed)** | 🟡 **Engine only** | 🔵 **macOS Feature Advantage.** macOS links to `MediaRemote.framework` with UI selection ("Pause & Resume", "Always Pause", "Off") in [MainViews.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/MainViews.swift). Windows backend in [media.rs](file:///c:/projects/Personal/dicty/DictyClientTauri/src-tauri/src/media.rs) supports GSMTC (`VK_MEDIA_PLAY_PAUSE`), but the setting toggle is not yet exposed in Windows Tauri UI. |
| **Audio Recording** | **Live Recording Overlay (HUD)** | Non-activating floating transparent overlay showing live microphone volume meter and real-time transcription streaming. | 🟢 Yes (`NSPanel`) | 🟢 Yes (Transparent Webview) | 🟡 macOS uses a native AppKit floating panel (`RecordingOverlay.swift`) with live UDP volume packets (port 55555). Windows uses a frameless transparent Tauri window ([RecordingOverlayHUD.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/RecordingOverlayHUD.tsx)) with draggable handle, pin/minimize, and WebSocket partial stream. |
| **Voice / Speech** | **Text-to-Voice (TTS) Settings View** | Dedicated screen for Text-to-Speech configuration: voice selector, speech speed, pitch, sentence pause, voice audition text box. | 🟢 **Yes** | 🔴 **Missing** | 🔵 **macOS Only.** Dedicated `TextToVoiceSettingsView.swift` supporting Kokoro ONNX and Silero models with interactive audition player. Windows Tauri UI lacks this tab in `Navigation.tsx`. |
| **Voice / Speech** | **Floating Audio Player HUD** | Floating miniature audio player for listening to transcribed summaries or TTS output with scrubber and playback controls. | 🟢 **Yes** | 🔴 **Missing** | 🔵 **macOS Only.** [FloatingAudioHUD.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/FloatingAudioHUD.swift) provides an always-on-top AppKit pill with waveform, play/pause, rewind, speed selector (0.75x–2.0x), and progress bar. |
| **Voice / Speech** | **Global Text-to-Voice Hotkey** | Press hotkey over highlighted text in any application to read aloud via neural voice synthesis. | 🟢 **Yes** | 🔴 **Missing** | 🔵 **macOS Only.** macOS registers global shortcut for TTS read-aloud via Accessibility selection reading. |
| **Meeting Records** | **Meeting Audio File Playback** | Built-in waveform/audio scrubber to replay recorded meeting audio directly in history. | 🟢 Yes | 🟢 Yes | Full parity. Plays local recorded WAV files with timeline scrubbing and playback speed controls. |
| **Meeting Records** | **Speaker Diarization Timeline** | Visual breakdown of speaker turns (e.g. Speaker 0, Speaker 1) with color-coded badges and timestamps. | 🟢 Yes | 🟢 Yes | Full parity across both clients. |
| **Meeting Records** | **Generate / Regenerate Summary** | Button on meeting card to trigger LLM summary generation with structured bullets, decisions, and action items. | 🟢 Yes | 🟢 Yes | Full parity. Re-summarize action with loading spinners and error handling implemented on both platforms. |
| **Meeting Records** | **Meeting Context Notes & Editor** | Add and persist custom meeting notes/prompts to provide the LLM context for smarter summarization. | 🟢 Yes | 🟢 Yes | Full parity. macOS uses inline text editor; Windows Tauri uses expanding textarea with auto-save to `/v1/history/{id}/notes`. |
| **Transcription** | **Audio File Transcription (Upload)** | Drag & drop or browse `.mp3`, `.wav`, `.m4a`, `.mp4` files for offline engine transcription. | 🟢 Yes | 🟢 Yes | Full parity ([TranscribeFileView.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/TranscribeFileView.tsx) vs `TranscribeFileView.swift`). |
| **History & Management** | **Search & Filter History** | Filter past dictations and meetings by keyword, date range, mode (Dictate vs Meeting), and starred status. | 🟢 Yes | 🟢 Yes | Full parity. Search bar with instant client-side and backend search filtering. |
| **History & Management** | **Export Options** | Export transcripts and summaries to Markdown (`.md`), Plain Text (`.txt`), SRT Subtitles, or JSON. | 🟢 Yes | 🟢 Yes | Full parity with native OS Save Panels. |
| **History & Management** | **Delete / Clear History** | Single item deletion with confirmation and bulk clear. | 🟢 Yes | 🟢 Yes | Full parity. |
| **Modes & Profiles** | **Custom Dictation Modes** | Create, edit, and delete modes (e.g., "Casual", "Email", "Code", "Meeting", "Custom Prompt") with custom system instructions and temperatures. | 🟢 Yes | 🟢 Yes | Full parity. Syncs with backend `/modes` endpoints. |
| **Modes & Profiles** | **Quick Mode Switcher HUD** | Dedicated hotkey opens a fast switcher HUD overlay to toggle between modes without opening full preferences. | 🟢 Yes (`ModeSwitcherHUD.swift`) | 🟢 Yes (`ModeSwitcherHUDView.tsx`) | Full parity. Both platforms open a centered non-activating HUD overlay with keyboard navigation. |
| **Knowledge Base** | **Knowledge Base Items Management** | Manage custom terms, personal vocabulary, acronyms, and phonetic hints for higher transcription accuracy. | 🟢 Yes | 🟢 Yes | Full parity. Add, edit, delete, and import custom dictionary terms. |
| **Knowledge Base** | **Mermaid Diagram Lightbox** | Clickable Mermaid diagrams in knowledge updates with zoom, pan, and SVG export. | 🟢 **Yes** | 🟡 **Basic Code Only** | 🔵 **macOS Feature Advantage.** macOS uses a custom `WKWebView` interactive lightbox modal with pinch-to-zoom and pan. Windows Tauri renders static Markdown/code blocks without interactive pan/zoom modal. |
| **Shortcuts & Input** | **Global Push-to-Talk / Toggle Hotkey** | Global shortcut to start/stop dictation or push-to-talk from any active application. | 🟢 Yes | 🟢 Yes | macOS uses `CGEventTap` / `Carbon` hotkeys; Windows uses `RegisterHotKey` / low-level Windows keyboard hooks in Rust (`hotkey.rs`). |
| **Shortcuts & Input** | **Direct Typing vs Clipboard Paste** | Option to type text character-by-character into target app or copy to clipboard and paste (`Ctrl+V` / `Cmd+V`). | 🟢 Yes | 🟢 Yes | macOS uses `AXUIElement` / `CGEventKeyboard`; Windows uses Win32 `SendInput` keyboard events with fallback to clipboard. |
| **Help & Onboarding** | **In-App Contextual Help Modal (`(?)`) & Onboarding Replay** | Dedicated contextual help button on every screen explaining features, hotkeys, and troubleshooting tips, plus onboarding replay. | 🟢 **Yes** | 🟢 **Yes** | 🟢 **Full Parity.** Both platforms feature searchable, 10-topic guides accessible via header `(?)` icons (`FeatureHelpView.swift` vs `FeatureHelpModal.tsx`), with onboarding replay in Preferences and tray/menu bar. |
| **Appearance & Theme** | **Theme Switcher (Dark / Light / System)** | Modern glassmorphic theme selector matching system accent colors and dark mode preference. | 🟢 Yes | 🟢 Yes | Both feature sleek dark/light mode interfaces following Dicty UI guidelines. |
| **Appearance & Theme** | **Dock / Taskbar Visibility Toggle** | Choose whether the app icon appears in macOS Dock / Windows Taskbar or only resides in the Tray menu. | 🟢 Yes | 🟢 Yes | macOS uses `NSApp.setActivationPolicy(.accessory / .regular)`; Windows toggles taskbar window styling. |
| **Appearance & Theme** | **Custom Dock Icon Themes** | Switch Dock icon appearance between Light, Dark, or Custom stylized icons. | 🟢 **Yes** | 🔴 **N/A (OS specific)** | macOS supports dynamic `NSWorkspace` / `NSApp.applicationIconImage` swapping. Not applicable to Windows taskbar pinning. |
| **System Tray / MenuBar** | **System Tray Menu** | Fast status tray menu with Quick Record, Pause, Open Window, Status indicator, and Quit. | 🟢 Yes (`MenuBarExtra`) | 🟢 Yes (Tauri System Tray) | macOS uses native SwiftUI `MenuBarExtra`; Windows uses Tauri Rust `tray.rs` with native Windows context menu. |
| **Updates & Engine** | **Engine Status & Health Monitor** | Indicator showing whether local Python engine is starting, ready, running, or encountered an error. | 🟢 Yes | 🟢 Yes | Full parity. Polls `/health` endpoint and displays status chips. |
| **Updates & Engine** | **App & Model Updates View** | Check for newer Whisper models, HuggingFace model weights, and application binaries. | 🟢 Yes | 🟢 Yes | Full parity ([UpdatesView.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/UpdatesView.tsx) vs `UpdatesView.swift`). |

---

## 3. Detailed Analysis of Key Platform Disparities

### 1. Sound Feedback Volume Control
* **Windows (Implemented):**
  - Location: [PreferencesView.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/PreferencesView.tsx) & [sound.rs](file:///c:/projects/Personal/dicty/DictyClientTauri/src-tauri/src/sound.rs).
  - Feature: Users have a dedicated slider from `0%` to `100%` (`recording_sound_volume`).
  - Implementation: Rust `rodio` sink decodes the WAV stream and multiplies PCM amplitude samples by the volume scalar before sending to the audio output device.
* **macOS (Gap):**
  - Location: [Appearance.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/Appearance.swift) & [AudioFeedbackManager.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/AudioFeedbackManager.swift).
  - Discrepancy: `NSSound(named:)?.play()` is triggered without a dedicated volume attribute exposed in UI. As a result, chimes play at whatever system volume is currently set.
  - **Action Required for Parity:** Add `recordingSoundVolume: Double` to AppStorage in `Appearance.swift` and apply `sound.volume = Float(volume)` in `AudioFeedbackManager.swift`.

---

### 2. Text-to-Voice (TTS) Integration & Floating Audio HUD
* **macOS (Implemented):**
  - Location: `TextToVoiceSettingsView.swift` & `FloatingAudioHUD.swift`.
  - Feature: Full tab for selecting local neural voices (Kokoro ONNX, Silero), tweaking speed/pitch/pause lengths, auditioning speech samples, and activating a global hotkey that reads selected text aloud in any app. Includes an interactive floating audio player pill.
* **Windows (Gap):**
  - Location: Backend engine has all endpoints ready (`/tts/generate`, `/tts/voices`), but [Navigation.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/components/Navigation.tsx) does not include a `TextToVoiceView`, nor does Tauri have an equivalent `FloatingAudioHUDView`.
  - **Action Required for Parity:** Port `TextToVoiceSettingsView` into React/TS in `DictyClientTauri/src/views/TextToVoiceView.tsx` and register a secondary Tauri window for the floating audio scrubber HUD.

---

### 3. Media Playback Auto-Pause (Music / Podcasts)
* **macOS (Implemented):**
  - Location: [MediaPlaybackManager.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/MediaPlaybackManager.swift) and [MainViews.swift](file:///c:/projects/Personal/dicty/DictyClient/Sources/DictyClient/MainViews.swift).
  - Feature: Integrates directly with macOS `MediaRemote.framework` (`MRMediaRemoteSendCommand`) to smoothly pause Spotify, Apple Music, or YouTube when recording starts, and resume when finished. Option is exposed in Settings.
* **Windows (Partial):**
  - Location: [media.rs](file:///c:/projects/Personal/dicty/DictyClientTauri/src-tauri/src/media.rs).
  - Discrepancy: Rust code supports Windows GSMTC (`GlobalSystemMediaTransportControlsSessionManager`) and `VK_MEDIA_PLAY_PAUSE` keystroke emulation. However, the user preference toggle is **not exposed** in [PreferencesView.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/views/PreferencesView.tsx).
  - **Action Required for Parity:** Add an "Auto-pause media during recording" toggle in `PreferencesView.tsx` that links to the Tauri `pause_media` / `resume_media` command invocations.

---

### 4. Contextual In-App Help Modal & Onboarding Replay
* **Windows (Implemented):**
  - Location: [FeatureHelpModal.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/components/FeatureHelpModal.tsx) & [OnboardingModal.tsx](file:///c:/projects/Personal/dicty/DictyClientTauri/src/components/OnboardingModal.tsx).
  - Feature: Clicking the `(?)` button in the app header opens an interactive guide explaining every feature for the current tab, including keyboard shortcuts, setup prerequisites, and common issues. Onboarding can be replayed from Preferences anytime.
* **macOS (🟢 Full Parity Achieved):**
  - Location: `FeatureHelpView.swift`, `Appearance.swift` (`SettingsPageHeader`), and `MainViews.swift` (`OnboardingHelpPreferencesView`).
  - Feature: Native SwiftUI frosted glass modal with search filtering, 10 detailed feature guides, SF Symbols, Pro Tip callout cards, and contextual `FeatureHelpButton` next to page headers across all tabs. Includes Onboarding setup wizard replay from Preferences and the MenuBarExtra tray menu.

---

### 5. Mermaid Diagram Interactive Lightbox
* **macOS (Implemented):**
  - Location: `KnowledgeBaseView.swift`.
  - Feature: Interactive diagram viewer using `WKWebView` with pinch-to-zoom, pan gesture, and SVG export.
* **Windows (Partial):**
  - Location: `RichMarkdownDocumentView.tsx`.
  - Discrepancy: Renders diagrams as static SVG/code blocks; lacks zoom/pan canvas modal.
  - **Action Required for Parity:** Integrate an SVG pan/zoom library (e.g. `react-svg-pan-zoom` or `panzoom`) in the Windows Markdown renderer modal.

---

## 4. Architectural Summary

| Dimension | macOS (`DictyClient`) | Windows (`DictyClientTauri`) |
| :--- | :--- | :--- |
| **UI Framework** | SwiftUI + AppKit | React 19 + TypeScript + Tailwind CSS |
| **Desktop Shell** | Native Swift Executable (`.app`) | Tauri v2 (Rust Core + Webview2) |
| **Audio Capture** | CoreAudio Engine (`AVAudioEngine` / Python `sounddevice`) | WASAPI (`sounddevice` / `rodio` playback) |
| **Global Keystrokes** | `CGEventTap` / Carbon Hotkeys / Accessibility API | Windows Low-Level Keyboard Hooks (`WH_KEYBOARD_LL`) & `RegisterHotKey` |
| **Text Insertion** | `AXUIElement` / `CGEvent` synthesis | Win32 `SendInput` & Clipboard injection fallback |
| **Floating Overlays** | Native `NSPanel` (`.nonactivatingPanel`, floating level) | Transparent frameless Tauri webview (`alwaysOnTop: true`) |
| **Local Engine** | Embedded PyInstaller Python executable (`backend_packaged`) | Embedded PyInstaller Python executable (`backend_packaged`) |

---

## 5. Recommended Parity Roadmap

1. **Short Term (High User Value):**
   - **macOS:** Add the sound feedback volume slider (0% to 100%) to `Appearance.swift` and `AudioFeedbackManager.swift`.
   - **Windows:** Expose the Media Playback Auto-Pause toggle in `PreferencesView.tsx` and wire it to `media.rs`.
2. **Medium Term:**
   - **Windows:** Port `TextToVoiceView.tsx` into Windows Tauri, allowing Windows users to utilize the backend Kokoro and Silero TTS engine.
   - **Windows:** Create a lightweight floating mini-HUD in Tauri for audio playback and scrubbing.
3. **Long Term:**
   - **macOS:** ~~Add the universal `FeatureHelpModal` sheet for quick feature discovery.~~ (✅ **Completed: FeatureHelpView & Onboarding Replay**)
   - **Windows:** Add interactive Pan/Zoom lightbox for Mermaid diagrams.
