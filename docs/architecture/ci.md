# CI Pipeline

Dicty ships to macOS and Windows only, so every workload runs on GitHub-hosted
`macos-15` / `windows-latest` runners (plus a couple of seconds-long bookkeeping jobs on
`ubuntu-latest`). Standard hosted runners are free for public repositories, so this
pipeline optimises for signal quality and PR feedback time rather than runner-minutes.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `tests-and-build.yml` | `pull_request`, `push` to `main`, nightly `schedule`, manual | Backend tests, Swift build, lint, Windows/Tauri checks, nightly suites |
| `release.yml` | manual (`workflow_dispatch`) | Version bump, release notes, DMG / Windows installer, publish, Homebrew cask |
| `release-drafter.yml` | `push` to `main`, `pull_request_target` | Draft release notes and version resolution |

Static analysis is provided by GitHub’s CodeQL **default setup** (Python, weekly, configured
in the repository settings) rather than an in-repo workflow — a custom `codeql.yml` would
conflict with default setup and fail to upload SARIF.

## `tests-and-build.yml` jobs

| Job | Runs on | When | What it does |
| --- | --- | --- | --- |
| `changes` | `ubuntu-latest` | every run | Diffs the PR against its base to decide whether the Windows job is relevant |
| `python-tests` | `macos-15` | every PR and push | `check_engine_endpoint.sh` guard, backend unit tests with a 50% coverage floor, Codecov upload |
| `swift-build` | `macos-15` | every PR and push | `swift build -c release` with a cached `.build`, then `validate_app_bundle.sh` |
| `lint` | `macos-15` | every PR and push | Ruff (`E9,F63,F7,F82`) and actionlint over `.github/workflows` |
| `tauri-checks` | `windows-latest` | PRs touching Tauri/Windows files, plus push/nightly | `npm ci`, `npm run build` (tsc + vite), `cargo check --all-targets` |
| `dependency-review` | `ubuntu-latest` | PRs | Fails a PR that introduces a high-severity vulnerable dependency |
| `swift-tests` | `macos-15` | nightly cron and manual dispatch | `make test-swift` |
| `packaging-smoke` | `macos-15` | nightly cron and manual dispatch | Compiles whisper.cpp and builds `dicty_engine.spec` with PyInstaller, asserts the bundle contents |
| `tests-quality-gate` | `ubuntu-latest` | always | Fails the run unless the required jobs succeeded; always reports a status |

### Why the Swift build is on pull requests but the Swift tests are not

A pull request must not be able to merge uncompilable Swift. `swift-build` therefore runs
on every PR; the `.build` cache keeps incremental builds to a couple of minutes.

`swift test` has a history of runner flakiness, and a flaky required check blocks
contributors for reasons unrelated to their change. It runs nightly instead, where a
failure is a signal to investigate rather than a merge blocker. To run it against a PR,
use `workflow_dispatch` on the branch.

### Why the lint gate is narrow

`lint` deliberately runs only Ruff's syntax/undefined-name rules. A codebase-wide style or
import-order gate added today would fail on hundreds of pre-existing findings and block
every PR for unrelated reasons. Widen the rule selection as the codebase is cleaned up.

### Required checks

Branch protection on `main` should require exactly one status check:
**`Tests Quality Gate`**. The gate knows which jobs are optional, so adding or removing
jobs never leaves a PR stuck on a pending check.

## Release pipeline

`release.yml` is manual and runs in this order:

1. **`release`** — detects which platforms were affected since the last published release
   by diffing the changed paths (shared backend paths trigger both platforms), creates the
   release **as a draft**, and computes the next version.
2. **`build_mac`** — imports the Developer ID certificate, builds and signs the DMG,
   notarizes and staples it, verifies the signature and Gatekeeper assessment, and
   uploads the DMG plus checksum.
3. **`build_windows`** — packages the backend with PyInstaller and the Tauri installer,
   then uploads the `.exe` plus checksum.
4. **`publish`** — only runs when every requested installer succeeded and the expected
   assets are attached, flips the draft to a published release, and only then bumps the
   Homebrew cask (so the tap never points at a draft DMG).

Because the release stays a draft until the end, a failed build never produces a public
release with missing assets. Re-running the workflow reuses the same draft.

The `build_mac` / `build_windows` inputs accept `auto` (default), `always`, or `never`, so
a Windows-only change does not rebuild or re-publish a macOS installer.

## Reproducing CI locally

```bash
make setup          # venv, dependencies, whisper binaries, Swift client
make test           # backend suite + Swift tests + bundle validation
make test-backend   # backend suite only
make test-swift     # Swift tests only
```

`scripts/check_engine_endpoint.sh` enforces that engine host/port/token handling stays in
its central client module (`EngineEndpoint.swift`, `engine_http.rs`,
`services/engineClient.ts`). It runs in CI and in `make setup`.

## Conventions

- Every job declares `timeout-minutes`. A hung job on a hosted runner otherwise holds its
  slot for up to six hours.
- Jobs that touch secrets must not run on `pull_request` from forks; GitHub does not pass
  secrets to those runs.
- Third-party actions are pinned to full commit SHAs with the human-readable version in a
  trailing comment. Bump both together (Dependabot handles this for `github-actions`).
- `ACTIONLINT_VERSION` in `tests-and-build.yml` is bumped manually alongside the pinned
  actionlint release.
- The 50% coverage floor in `python-tests` is a ratchet: raise it when coverage improves,
  never lower it to make a red build green.
- Workflow changes must pass `actionlint`; `lint` enforces it in CI.
