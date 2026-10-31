# CI Pipeline

Dicty ships to macOS and Windows only, so all CI workloads run on GitHub-hosted
`macos-15` (and `windows-latest` for release packaging). Standard hosted runners are
free for public repositories, so the goal of this pipeline is fast, meaningful signal
rather than runner-minutes.

## Workflows

| Workflow | Trigger | Purpose |
| --- | --- | --- |
| `tests-and-build.yml` | `pull_request`, `push` to `main`, nightly `schedule`, manual | Backend tests, Swift release build, nightly Swift tests |
| `release.yml` | manual (`workflow_dispatch`) | Version bump, release notes, DMG / Windows installer, Homebrew cask |
| `release-drafter.yml` | `push` to `main`, `pull_request_target` | Draft release notes and version resolution |

## `tests-and-build.yml` jobs

| Job | Runs on | When | What it does |
| --- | --- | --- | --- |
| `python-tests` | `macos-15` | every PR and push | `check_engine_endpoint.sh` guard, 300+ backend unit tests with coverage, Codecov upload |
| `swift-build` | `macos-15` | every PR and push | `swift build -c release` with a cached `.build`, then `validate_app_bundle.sh` (bundle sealing + codesign verification) |
| `swift-tests` | `macos-15` | nightly cron and manual dispatch | `make test-swift` |
| `tests-quality-gate` | `ubuntu-latest` | always | Fails the run unless the required jobs succeeded; always reports a status so required checks never hang |

### Why the Swift build is on pull requests but the Swift tests are not

A pull request must not be able to merge uncompilable Swift. `swift-build` therefore runs
on every PR; the `.build` cache keeps incremental builds to a couple of minutes.

`swift test` has a history of runner flakiness, and a flaky required check blocks
contributors for reasons unrelated to their change. It runs nightly instead, where a
failure is a signal to investigate rather than a merge blocker. To run it against a PR,
use `workflow_dispatch` on the branch.

### Required checks

Branch protection on `main` should require exactly one status check:
**`Tests Quality Gate`**. The gate tolerates jobs that are legitimately skipped and fails
on anything else, so adding or removing jobs never leaves a PR stuck on a pending check.

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
- Workflow changes should pass `actionlint` before merge.
