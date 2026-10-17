# Dev Mission Control

A native macOS menu bar app that answers **"where was I and what needs attention?"** across all your local projects in one click. Click the scope icon in the menu bar to open a borderless panel that lists every tracked repository, its attention items, and the clean projects at a glance.

## What it flags

For each tracked project, Dev Mission Control separates pending local work from actionable attention. The evidence and meaning of each finding are:

| State or finding | Evidence | Meaning |
| --- | --- | --- |
| In progress | Git reports staged, unstaged, or untracked files in the checkout or a linked worktree | Informational only; it is not evidence that an agent is running and is never urgent by itself |
| Source unavailable or stale | The latest source read failed, or only an earlier successful value is retained | No information, not an alert; only current independent evidence can create a finding |
| Merge conflict | Git reports one or more unmerged entries in the checkout or a linked worktree | critical |
| Failing CI | An open PR has a failing check | critical |
| Unpushed commits | Local commits are ahead of the configured upstream branch | warning |
| PR `#N` open too long | Open PR is older than the informational threshold | info; age alone is not urgency |
| Worktree `X` idle too long | A clean linked worktree's last commit is older than the worktree threshold and its project is not paused | info |
| Engram inactivity | Engram is available and its latest observation is older than the inactivity threshold; project is not paused | info |

A project is paused only when explicitly configured as paused. Pausing suppresses Engram inactivity and idle-clean-worktree notices; it does not hide conflicts, failing checks, or unpushed commits. File modification dates are not used to infer agent activity. Informational findings do not count as a project needing attention. Sources that cannot be consulted are surfaced as **"unavailable"** and never treated as empty or fabricated results.

## Data sources

All access is read-only. The app never mutates a repository and stores no credentials.

- **Local git** (`/usr/bin/git`): primary checkout branch, categorized `git status --porcelain=v1` counts (staged, unstaged, untracked, unmerged conflicts), unpushed commit count (`rev-list @{u}..HEAD`), and `git worktree list --porcelain` with each linked worktree's branch, path, change counts, and last-commit age.

The primary checkout branch is distinct from linked-worktree branches. Pending changes are a repository-state signal, not a claim about agent liveness. Actions remain read-only: the app never commits, pushes, merges, or removes worktrees.
- **`gh` CLI**: `gh pr list -R <owner/repo> --state open --json number,title,createdAt,statusCheckRollup` for open PR age and CI state. The slug is taken from the config when set, otherwise derived from the `origin` remote.
- **Engram HTTP API**: `GET http://127.0.0.1:7437/observations?project=<name>&limit=1` for the most recent agent activity of the project.

## Source states and freshness

Each source — local Git, the `gh` CLI, and the Engram HTTP API — is read independently. The app tracks whether each latest read succeeded, the time of its last successful read, and one of three freshness states:

| State | Meaning |
| --- | --- |
| Current | The latest read succeeded; the value is current |
| Stale | The latest read failed after an earlier success; the last valid value is retained in memory and the current failure is shown separately as unavailable |
| Unavailable | The latest read failed and no earlier value exists |

A failed refresh never erases the last good value: the retained value is marked stale and the current error is reported alongside it, so a `gh` failure is never an empty PR list and an Engram outage is never "no activity". Only current reads create findings; an unavailable or stale source is "no information", not an attention alert. Each source degrades independently, so local Git stays queryable when `gh` or Engram is down.

Scans are non-overlapping: a manual or scheduled refresh is skipped while one is already running, so the panel never blocks. Every external operation is bounded — `git` and `gh` subprocesses time out after 30 s by default, and Engram requests use a 3 s request / 5 s resource timeout. Periodic scanning never calls a model. Subprocesses are launched by executable path with a separate argument vector; repository paths are passed as discrete `-C` arguments and are never concatenated into a shell command string.

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

It prints a check-count summary when everything is green.

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
      "enabled": true,
      "isPaused": false
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
| `repos[].isPaused` | Optional; defaults to `false`; suppresses inactivity and idle-worktree notices |
| `refreshIntervalMinutes` | Auto-refresh interval (default 5) |
| `staleWorktreeDays` | Informational threshold for clean idle worktrees (default 7) |
| `stalePRDays` | Informational open-PR age threshold; age alone is not urgent (default 7) |
| `inactivityDays` | Engram inactivity threshold in days (default 14) |

Decoding is tolerant: omitted keys fall back to defaults, so configs written by older versions keep loading. Repositories are added and removed with the folder picker in **Settings**, and thresholds are edited there with steppers.

## Design decisions and limitations

- **No stale local-branch detection.** Squash merges make `git branch --no-merged` unreliable, so branches that look unmerged may already be merged upstream. This was deliberately left out of v1.
- **Worktree age is derived from its last commit date**, not from when the worktree was created or linked.
- **Unavailable sources never fabricate findings, and stale data is identified.** If `gh` is missing or unauthenticated, PR/CI findings are skipped for that repo and the source is unavailable; when a previous successful read exists, its PR list is retained and marked stale rather than emptied. If Engram is unreachable, activity findings are skipped and the source is unavailable; the last known activity is retained as stale. A missing or invalid repo path is an unavailable Git source, not a clean result or an attention alert; independent current sources remain classifiable.
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
