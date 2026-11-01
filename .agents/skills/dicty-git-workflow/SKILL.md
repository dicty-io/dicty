---
name: dicty-git-workflow
description: >-
  Workflows, branch protection policies, pre-push verification gates, and commit standards for the Dicty repository.
  Use this skill whenever creating a branch, committing code, running tests before pushing, or preparing a pull request.
---

# Dicty Git & Branching Workflow

This skill establishes the repository-wide standards for branching, code verification, committing, and pushing in Dicty. All AI agents and contributors must strictly adhere to these rules.

---

## 1. Protected Branch Policy

> [!IMPORTANT]
> **NEVER push directly to `main` under any circumstances.**
> Even if local git credentials or administrative roles have bypass permissions, direct pushes to `main` are strictly forbidden.

- **All changes must go through a dedicated topic branch and Pull Request.**
- Branch naming convention:
  - Date-based sprint/topic branches: `DD.MM` (e.g. `01.11`, `31.10`)
  - Feature branches: `feature/<feature-name>` (e.g. `feature/audio-enhancement`)
  - Bugfix branches: `fix/<issue-name>` (e.g. `fix/model-variant-matching`)
  - Chore/infrastructure: `chore/<description>` (e.g. `chore/ci-hardening`)

---

## 2. Pre-Push Verification Gates

Dicty is a multi-platform project comprising Python, macOS Swift, and Windows Tauri/React. Before pushing any commit to a remote branch, you **must** run the verification checks corresponding to the modified components:

### A. Python Backend & Engine (if touching Python files or configs)
```bash
.venv/bin/python -m unittest discover tests
```
- All tests must pass (100% pass rate; skipped tests are acceptable if environment-specific).

### B. macOS Swift Client (if touching `DictyClient/`)
```bash
cd DictyClient && swift build
```
- Must compile cleanly with 0 errors.

### C. Windows Tauri Frontend (if touching `DictyClientTauri/`)
```bash
cd DictyClientTauri && npm ci && npm run build
```
- Type-checking (`tsc`) and bundling (`vite build`) must succeed with 0 errors.

### D. GitHub Workflows (if touching `.github/workflows/` or `.github/*.yml`)
Verify that all YAML files parse correctly:
```bash
.venv/bin/python -c "import yaml, glob; [yaml.safe_load(open(f)) for f in glob.glob('.github/**/*.yml', recursive=True)]; print('YAML valid!')"
```

---

## 3. Performance & Latency Constraints

> [!TIP]
> Dicty is optimized for real-time dictation with a **sub-100ms** total pipeline latency target.

- **Zero Latency Regression**: Do not introduce unnecessary disk I/O, synchronous network calls on the audio processing path, or thread contention.
- **Atomic Operations**: File downloads or mutations on disk (e.g. model weights, transcription history) must use atomic temporary files (`.part` / `.tmp` + `os.replace`) to protect against corruption during unexpected shutdowns.

---

## 4. Step-by-Step Contribution Flow

### Step 1: Ensure `main` is Synchronized
Before starting work, update your local `main`:
```bash
git switch main
git pull origin main
```

### Step 2: Create a Working Branch
Never start edits on `main`. Create and switch to your feature branch:
```bash
git checkout -b <branch-name>
```

### Step 3: Implement & Self-Review
- Keep diffs focused and minimal.
- Maintain existing docstrings, comments, and architecture patterns.

### Step 4: Run Verification
Execute the relevant commands from **Section 2 (Pre-Push Verification Gates)**.

### Step 5: Commit Following Conventional Standards
Write concise, descriptive commit messages:
```bash
git add <files>
git commit -m "<type>(<scope>): <summary>"
```
Examples:
- `feat(engine): add streaming deepgram authentication retry bypass`
- `fix(model-manager): recognize fp16 and fp32 model variant suffixes`
- `chore(ci): pin tailwindcss to v3 in DictyClientTauri`

### Step 6: Push to the Remote Branch
Push exclusively to the branch on `origin`:
```bash
git push -u origin <branch-name>
```

### Step 7: Open a Pull Request
- Create a PR targeting `main`.
- Wait for automated CI checks to complete:
  - `Backend Tests` (macOS-15)
  - `Swift Client Release Build`
  - `Lint & Workflow Checks`
  - `Tauri Client Checks (Windows)`
- Review any feedback from reviewers (or CodeRabbit), address comments on the branch, and re-push.
