# Dev Mission Control

A native macOS menu bar app that answers **"where was I and what needs attention?"** across all your local projects in one click. Click the scope icon in the menu bar to open a borderless panel that lists every tracked repository, its attention items, and the clean projects at a glance.

## What it flags

For each tracked project, Dev Mission Control classifies these attention items (threshold-driven, critical first):

| Item | Trigger | Severity |
| --- | --- | --- |
| Config error | Repo path missing or not a git repository | critical |
| Failing CI | An open PR has a failing check | critical |
| Dirty working tree | Uncommitted files in the main worktree | warning |
| Unpushed commits | Local commits not pushed to the upstream branch | warning |
| Dirty worktree `X` | A linked worktree has uncommitted changes | warning |
| PR `#N` open too long | Open PR older than the PR threshold | warning |
| Worktree `X` idle too long | Linked worktree whose last commit is older than the worktree threshold | info |
| No agent activity | Last Engram observation older than the inactivity threshold | info |

Repositories with no findings render as clean rows. Sources that cannot be consulted are surfaced as **"unavailable"** on the card and never fabricate a finding.

## Data sources

All access is read-only. The app never mutates a repository and stores no credentials.

- **Local git** (`/usr/bin/git`): current branch, `git status --porcelain`, unpushed commit count (`rev-list @{u}..HEAD`), and `git worktree list --porcelain` with per-worktree dirty state and last-commit age.
- **`gh` CLI**: `gh pr list -R <owner/repo> --state open --json number,title,createdAt,statusCheckRollup` for open PR age and CI state. The slug is taken from the config when set, otherwise derived from the `origin` remote.
- **Engram HTTP API**: `GET http://127.0.0.1:7437/observations?project=<name>&limit=1` for the most recent agent activity of the project.

## Requirements

- macOS 13 or later
- Command Line Tools only (`xcode-select --install`); no full Xcode required
- `gh`, authenticated, for PR/CI findings (optional)
- Engram running at `127.0.0.1:7437` for activity findings (optional)

## Build

```sh
scripts/build-app.sh          # debug
scripts/build-app.sh release  # release
```

The script builds the Swift package and assembles `build/DevMissionControl.app` (ad-hoc signed). The final line is `Built build/DevMissionControl.app`.

## Run

```sh
open build/DevMissionControl.app
```

The scope icon appears in the menu bar. Left-click toggles the panel, right-click opens a context menu with Settings and Quit.

## Tests

The logic tests are an executable Swift target with a custom check harness:

```sh
swift run DevControlLogicTests
```

It prints `127/127 checks passed` when everything is green.

## Headless mode

`--scan-once` runs the full scan pipeline against the configured repositories, prints a summary per repo, and exits. It is used to verify the pipeline against real repositories without the UI:

```sh
build/DevMissionControl.app/Contents/MacOS/DevMissionControl --scan-once
```

The exit code is `1` when any attention item is found and `0` when everything is clean. Missing sources are printed as `unavailable (...)`.

## Configuration

Configuration is JSON stored at:

```
~/Library/Application Support/DevMissionControl/config.json
```

The file is created on first save (from the Settings window). Set the `DMC_CONFIG_DIR` environment variable to point the config store at another directory (used for smoke tests and isolated runs).

```json
{
  "repos": [
    {
      "id": "my-project",
      "path": "/Users/me/Projects/my-project",
      "githubSlug": "owner/my-project",
      "engramProject": "my-project",
      "enabled": true
    }
  ],
  "refreshIntervalMinutes": 5,
  "staleWorktreeDays": 7,
  "stalePRDays": 7,
  "inactivityDays": 14
}
```

| Field | Meaning |
| --- | --- |
| `repos[].id` | Display name / identifier |
| `repos[].path` | Absolute path to the repository working tree |
| `repos[].githubSlug` | Optional `owner/name`; derived from `origin` when absent |
| `repos[].engramProject` | Optional Engram project name; defaults to the folder name |
| `repos[].enabled` | Optional; defaults to `true` when omitted |
| `refreshIntervalMinutes` | Auto-refresh interval (default 5) |
| `staleWorktreeDays` | Worktree idle threshold in days (default 7) |
| `stalePRDays` | Open PR age threshold in days (default 7) |
| `inactivityDays` | Engram inactivity threshold in days (default 14) |

Decoding is tolerant: omitted keys fall back to defaults, so configs written by older versions keep loading. Repositories are added and removed with the folder picker in **Settings**, and thresholds are edited there with steppers.

## Design decisions and limitations

- **No stale local-branch detection.** Squash merges make `git branch --no-merged` unreliable, so branches that look unmerged may already be merged upstream. This was deliberately left out of v1.
- **Worktree age is derived from its last commit date**, not from when the worktree was created or linked.
- **Unavailable sources never fabricate findings.** If `gh` is missing or unauthenticated, PR/CI items are skipped for that repo and the card shows `PRs unavailable`. If Engram is unreachable, activity items are skipped and the card shows `Engram unavailable`. A missing or invalid repo path produces an explicit critical config-error row instead of crashing.
- **Read-only by contract.** The app runs `git` queries, `gh pr list`, and an Engram `GET` only; it stores no credentials (git and the `gh` keyring stay external).

## Project layout

```
Sources/DevControlCore/        Models, config store, attention math, scanners (git, gh, Engram)
Sources/DevMissionControl/     Menu bar app: AppState, panel, settings window, --scan-once
Sources/DevControlLogicTests/  Executable logic tests (custom check harness)
scripts/build-app.sh           CLT-only build + .app bundle assembly
Packaging/Info.plist           Bundle metadata
odd/tasks/dev-mission-control.md  ODD feature spec and log
```
