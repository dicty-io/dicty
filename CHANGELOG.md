# Changelog

All notable changes to Dicty are documented in this file.
This project adheres to [Semantic Versioning](https://semver.org/). Releases and automated release notes are published to [GitHub Releases](https://github.com/dicty-io/dicty/releases).

---

## [v1.1.2](https://github.com/dicty-io/dicty/releases/tag/v1.1.2) - 2026-10-27

### Added
- Automated test coverage collection and Codecov upload in CI pipeline.
- Dependabot configuration for GitHub Actions, Python, Swift, and npm ecosystems.
- Release Drafter for automated release notes generation and categorization.
- CodeRabbit configuration for automated pull request code review.

### Fixed & Improved
- Invoked `swift test` and `swift build` with `arch -arm64` on Apple Silicon runner hosts.
- Allowed maintainer-approved contributor PR test verification for outside forks.
- Cleaned and focused Core Capabilities and architectural documentation.
- Streamlined release pipeline and updated repository endpoints to `dicty-io/dicty`.

---

## [v1.1.1](https://github.com/dicty-io/dicty/releases/tag/v1.1.1) - 2026-10-26

### Fixed
- Handled Rosetta runner x86_64 architecture mismatch during CMake compilation.
- Disabled `GGML_NATIVE` on macOS runner builds for broader compatibility across Apple Silicon architectures.

---

## [v1.1.0](https://github.com/dicty-io/dicty/releases/tag/v1.1.0) - 2026-10-26

### Initial Release
- Initial open-source release of Dicty desktop voice dictation engine.
- Swift / SwiftUI menu bar app with floating dictation overlay and dark/light mode accents.
- Fast local `whisper.cpp` speech recognition engine running resident in RAM on Metal GPU.
- Offline-first voice dictation pipeline with dynamic style rules and custom snippet expansion.
- Dual-track microphone and system loopback meeting recording.
- Multi-provider LLM post-processing and correction options.
