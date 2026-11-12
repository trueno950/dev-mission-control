# Dev Mission Control

A native macOS menu bar app that answers **"where was I and what needs attention?"** across all your local projects in one click. Click the scope icon in the menu bar to open a borderless split console: a grouped, filterable project list on the left and the selected project's detail on the right, with per-source freshness in one panel and no separate detail window. The interface language follows the system automatically (Spanish for `es*` systems, English otherwise); worktree, staged, unstaged, untracked, diff, and PR stay as technical terms.

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

A project is paused only when explicitly configured as paused. Pausing suppresses Engram inactivity and idle-clean-worktree notices; it does not hide conflicts, failing checks, or unpushed commits. File modification dates are not used to infer agent activity, and a worktree's last-commit age stays informational: it is neither the local modification time nor agent activity. Informational findings are not urgent, but remain visible notices: the panel sorts them into **Para revisar**, apart from **Necesitan acción**, which only holds warnings and critical findings. Source states are reported separately and never create a finding. Findings follow the system language (for example, "Worktree prop-139 tiene 2 conflictos de merge" / "Worktree prop-139 has 2 merge conflicts", "PR #14 con checks fallidos" / "PR #14 failing CI").

## Data sources

All access is read-only. The app never mutates a repository and stores no credentials.

- **Local git** (`/usr/bin/git`): primary checkout branch, categorized `git status --porcelain=v1` counts (staged, unstaged, untracked, unmerged conflicts), unpushed commit count (`rev-list @{u}..HEAD`), and `git worktree list --porcelain` with each linked worktree's branch, HEAD object ID, path, change counts, and last-commit age.

The primary checkout branch is distinct from linked-worktree branches. Pending changes are a repository-state signal, not a claim about agent liveness. Actions remain read-only: the app never commits, pushes, merges, or removes worktrees.
- **`gh` CLI**: `gh pr list -R <owner/repo> --state open --json number,title,createdAt,statusCheckRollup,headRefName,headRefOid,url` for open PR age, CI state, and verified worktree association. The slug is taken from the config when set, otherwise derived from the `origin` remote.
- **Engram HTTP API** (`http://127.0.0.1:7437`): `GET /observations?project=<name>&limit=100` for the most recent agent activity and the saved session summary inside that page, plus the read-only panel reads `GET /stats`, `GET /projects`, `GET /observations` (full content), `GET /search`, `GET /sessions/recent`, and `GET /context`. Engram's writing endpoints (`POST /prompts`, `POST /sessions`) are never used and the app never opens Engram's SQLite store.

## Source states and freshness

Each source — local Git, the `gh` CLI, and the Engram HTTP API — is read independently. The app tracks whether each latest read succeeded, the time of its last successful read, and one of three freshness states:

| State | Meaning |
| --- | --- |
| Current | The latest read succeeded; the value is current |
| Stale | The latest read failed after an earlier success; the last valid value is retained in memory and the current failure is shown separately as unavailable |
| Unavailable | The latest read failed and no earlier value exists |

A failed refresh never erases the last good value: the retained value is marked stale and the current error is reported alongside it, so a `gh` failure is never an empty PR list and an Engram outage is never "no activity". Only current reads create findings; an unavailable or stale source is "no information", not an attention alert. Each project's detail ends with one source line (Git, GitHub, Engram) using the wording `actual` / `antiguo` / `no disponible`, with the read time and any current error in its tooltip. The panel footer rolls the three sources up across projects: "Git · hace 2 min" when every read is current, otherwise a count such as "GitHub · 3 de 9 leídos", so a few local-only repositories never look like a global outage. The detail's **•••** menu opens the in-app memories window described below and, as a secondary action, `engram tui` in Terminal (the local Engram server has no web dashboard), labelled **TUI global de Engram** because it is global and takes a few seconds to leave its loading box. Each source degrades independently, so local Git stays queryable when `gh` or Engram is down.

Engram's connection state is shown separately from its saved memory: a current read does **not** claim the memory reflects the current code. Engram stores session summaries as a title and date only, so **Dónde te quedaste** shows the latest memory's title and date (marked `antiguo` when the read is stale), says `Sin memorias de Engram` or `Engram sin conexión` instead of inventing one, and adds the primary checkout's last commit (short hash, subject, age) read with `git log -1`.

## Split console panel

The panel is a 760 × 600 split console that stays on the status item's screen.

**Sidebar.** A **Filtrar proyectos** field and the tracked projects grouped in triage order. Each row shows a severity shape (not color alone), the project name, a short age since the last commit or memory ("40m", "3h", "4d", "3w"), and a one-line reason.

| Group | Contents |
| --- | --- |
| Necesitan acción | Any warning or critical finding: merge conflicts, failing CI, unpushed commits |
| En curso | Pending local changes only; informational, never an alert |
| Para revisar | Informational findings only (idle clean worktrees, old PRs, Engram inactivity) |
| Sin datos | No findings and a Git read that is unavailable or stale; never presented as clean |
| Limpios | Nothing to report; paused projects show **Pausado** here unless a warning applies |

**Detail.** The selected project's header shows its primary branch and home-abbreviated path, with **Abrir en <Editor>** (or **Configurar editor…**), **Terminal**, and a **•••** menu (Engram memories, Engram TUI, Finder, copy path). Below it:

- **Dónde te quedaste**: the latest Engram memory, an **Abrir memorias** link, the last commit, and **Copiar contexto para retomar**, which composes the same retake context as the memories window without opening it.
- **Worktrees**: a table with the primary checkout first, then worktrees with conflicts or pending changes, each with a state pill ("2 conflictos", "3 cambios", "Limpio") and its last-commit age; zero counters are not shown. Clean linked worktrees collapse into one block ("4 worktrees limpios, inactivos 15–17 días") with **Copiar comando de limpieza** and, when they share one repository folder, **Ignorar esta carpeta** / **Dejar de ignorar**. A Git-unavailable read is never shown as an empty table.
- **Pull requests**: open PRs with age and CI state. When GitHub was not read, the section says **No leído.** and explains why: no GitHub remote, or the current `gh` error, with **Copiar gh auth login** only for authentication errors.

Pause or resume a project from its **Ajustes → Repositorios** row.

## Engram memories panel

Every repository has a read-only **Memorias de Engram** window — opened from the detail's **Abrir memorias** link or its **•••** menu — that reads the local Engram HTTP API directly instead of opening a terminal:

| Section | Read | What it shows |
| --- | --- | --- |
| Header | `GET /projects`, `GET /stats?project=` | The resolved Engram project and where the match came from, plus the sessions, observations, and prompts counters |
| Memories | `GET /observations?project=&limit=20` | The latest memories with type, title, and date, each expandable in place to its full content and copyable |
| Search | `GET /search?q=&project=` | Full-text search over that project's memories, debounced 350 ms, with out-of-order responses discarded |
| Sesiones recientes | `GET /sessions/recent?project=&limit=10` | Start, end (`en curso` when the session has not ended), and observation count per session |
| Retake context | `GET /context?project=` | A **Copiar contexto para retomar** action that composes the Engram context markdown with the current Git state (branch, pending counts, unpushed commits, worktrees) for pasting into an agent session |

Every section is its own source with its own freshness line and read time, so an unavailable read shows "sin información" and the current error instead of an empty list, and a failed refresh keeps the last good value marked stale. The panel never writes to Engram, never opens its SQLite store, and never calls a model. A repository matches its Engram project by the configured project name first, then by the most specific registered `directories` prefix from `GET /projects`, then by folder name — the Engram project name does not always match the folder (for example `car-rental-cancun` holds the memories of the folder `rental-car-cancun`).

## Worktree actions

Each worktree row in the detail has an Actions menu to open its folder in the Editor selected in Settings (or "Configurar editor…" when none is configured, which opens Settings), open it in macOS Terminal or Finder, copy its path, or display `git diff HEAD`. The diff sheet colorizes lines: additions green, removals red, hunk headers in the accent color, and file metadata dimmed. The diff includes staged and unstaged tracked changes; untracked files are not included.

The detail's pull-request section lists the project's open pull requests with their title, age, and CI state, plus an **Abrir** button that opens the PR in the browser using only the HTTPS URL returned by `gh`. A pull-request action appears only when exactly one current PR has both the same branch name and HEAD object ID as the worktree and `gh` returned an HTTPS URL. Branch-only or stale-data matches are not opened. These actions do not commit, push, merge, or remove worktrees.

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

The exit code is `1` when any attention item is found and `0` when everything is clean. Output labels follow the system language (`branch:`/`rama:`, `unavailable`/`no disponible`, `clean`/`sin hallazgos`).

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
      "isPaused": false,
      "ignoredWorktreeFolders": [".pi/review-units"]
    }
  ],
  "refreshIntervalMinutes": 5,
  "staleWorktreeDays": 7,
  "stalePRDays": 7,
  "inactivityDays": 14,
  "editorApplicationPath": "/Applications/Code Editor.app"
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
| `repos[].ignoredWorktreeFolders` | Optional; defaults to `[]`; repository-relative folders whose clean idle worktrees produce no notice (conflicts still do). Set from the panel's **Ignorar esta carpeta** |
| `refreshIntervalMinutes` | Auto-refresh interval (default 5) |
| `staleWorktreeDays` | Informational threshold for clean idle worktrees (default 7) |
| `stalePRDays` | Informational open-PR age threshold; age alone is not urgent (default 7) |
| `inactivityDays` | Engram inactivity threshold in days (default 14) |
| `editorApplicationPath` | Optional application bundle path selected in Settings; omitted or `null` disables the Editor action |

Decoding is tolerant: omitted keys fall back to defaults, so configs written by older versions keep loading. Repositories are added and removed in **Ajustes**; each row has an independent Activo/Pausado status label and a "Pausar proyecto" switch; thresholds are edited with steppers, and the Editor application is selected with the application picker, which opens anchored at `/Applications` and accepts only application bundles.

## Design decisions and limitations

- **No stale local-branch detection.** Squash merges make `git branch --no-merged` unreliable, so branches that look unmerged may already be merged upstream. This was deliberately left out of v1.
- **Worktree age is derived from its last commit date**, not from when the worktree was created or linked.
- **Unavailable sources never fabricate findings, and stale data is identified.** If `gh` is missing or unauthenticated, PR/CI findings are skipped for that repo and the source is unavailable; when a previous successful read exists, its PR list is retained and marked stale rather than emptied. If Engram is unreachable, activity findings are skipped and the source is unavailable; the last known activity is retained as stale. A missing or invalid repo path is an unavailable Git source, not a clean result or an attention alert; independent current sources remain classifiable.
- **Read-only by contract.** The app runs `git` queries, `gh pr list`, and Engram `GET` reads only; it stores no credentials (git and the `gh` keyring stay external). **Copiar comando de limpieza** only copies shell-quoted `git worktree remove` lines to the clipboard; the app never runs them.
- **The Engram panel matches by registered directory, and an ancestor registration can win.** The panel picks the most specific registered directory prefix, so a repository whose parent directory is registered to another project inherits that project when it has no registration of its own (Engram registers `~/Documents/Projects` for `dev-mission-control`). The configured `engramProject` always wins, and the panel states which origin it used.
- **The Engram TUI stays available but is global and slow.** `engram tui` needs about five seconds to leave its "Loading stats..." box and always shows global numbers, so it is a secondary action for administration rather than the per-project answer the panel gives.

## Project layout

```
Sources/DevControlCore/        Models, config store, attention math, scanners (git, gh, Engram)
  EngramPanel.swift            Panel models, response parsers, project resolver, request builder
  EngramPanelClient.swift      Read-only Engram HTTP reads and the retake-context composer
Sources/DevMissionControl/     Menu bar app: AppState, split console panel, settings window, --scan-once
  ConsoleSidebar.swift         Grouped, filterable project list
  ConsoleDetailView.swift      Selected project's header, where you left off, pull requests, sources
  WorktreesSection.swift       Worktree table, clean-worktree block, per-worktree actions and diff
  EngramPanelView.swift        Per-project Engram memories window (counters, memories, search, sessions, copy)
Sources/DevControlLogicTests/  Executable logic tests (custom check harness)
scripts/build-app.sh           CLT-only build + .app bundle assembly
Packaging/Info.plist           Bundle metadata
odd/tasks/dev-mission-control.md   ODD feature spec and log (attention delivery)
odd/tasks/engram-direct-panel.md   ODD feature spec and log (Engram direct panel)
odd/tasks/split-console-panel.md   ODD feature spec and log (split console panel)
design/menubar-panel/          Panel design directions (03-split-console is the implemented one)
```
