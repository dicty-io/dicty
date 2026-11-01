# Dicty Agent Guidelines

These guidelines apply to all AI coding agents working within the Dicty repository.

## 1. Branch Protection & Git Operations
- **NEVER push directly to `main`**. Even if admin credentials or local Git allows bypass, all modifications must be made on a topic branch (e.g., `01.11`, `feature/<name>`, `fix/<name>`, `chore/<name>`) and submitted via Pull Request.
- Before pushing to any branch, always run the appropriate pre-push verification gates.
- For detailed workflows, refer to [.agents/skills/dicty-git-workflow/SKILL.md](file:///.agents/skills/dicty-git-workflow/SKILL.md).

## 2. Pre-Push Verification Commands
- **Python Backend**: `.venv/bin/python -m unittest discover tests` (100% passing required).
- **macOS Swift Client**: `swift build` in `DictyClient/` (0 errors required).
- **Windows Tauri Frontend**: `npm ci && npm run build` in `DictyClientTauri/` (0 errors required).
- **Workflows**: Validate any YAML edited under `.github/`.

## 3. Performance & Latency Standard
- Dicty is built for sub-100ms end-to-end dictation latency.
- Do not add blocking disk I/O or synchronous HTTP calls into the audio capture, streaming, or text-paste pipeline.
- Disk persistence must use atomic replacement (`.part` / `.tmp` + `os.replace`) to safeguard against corruption.

## 4. Code Quality & Formatting
- Preserve all existing comments and docstrings.
- Follow Conventional Commits format (`feat:`, `fix:`, `chore:`, etc.).
- Keep pull requests focused on a single responsibility.
