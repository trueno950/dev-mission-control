# Feature: dev-mission-control

Native macOS menu bar app that answers "where was I and what needs attention?" across all local projects in one click.

## Specs

S1: "un segundo widget con la misma base: un 'Mission Control' de desarrollo en la barra de menú que responda en un click: PRs abiertos esperando, CI rojo, ramas sin fusionar, worktrees viejos para limpiar, y la última sesión de Engram por proyecto" — a menu bar item opening a status panel listing tracked projects and their attention items.

S2: Data sources per project, read-only and official only: local `git` (current branch, dirty file count, unpushed commit count, worktree list), `gh` CLI (open PRs with CI check status), Engram HTTP API (`GET /observations?project=<name>&limit=1` for last activity; server `http://127.0.0.1:7437`). No scraping, no mutations of user repos.

S3: Attention classification (pure logic, threshold-driven): dirty working tree; unpushed commits; worktree dirty OR older than N days; open PR older than N days; PR with failing CI; project with no Engram activity for N days. Repos with no findings render as clean. Thresholds configurable (defaults: worktree 7d, PR 7d, inactivity 14d).

S4: Configuration persisted as JSON in Application Support (`~/Library/Application Support/DevMissionControl/config.json`): repo list (absolute path; GitHub slug and Engram project name optional, derived when absent), refresh interval (default 5 min), thresholds. Editable via a settings window with a folder picker.

S5: Graceful degradation: without `gh` (missing or unauthenticated) skip PR/CI findings for that repo; without the Engram server skip activity findings; missing/invalid repo path renders an explicit config-error row instead of crashing. A source being unavailable is surfaced as "unavailable", never fabricated.

S6: Manual refresh (button) plus automatic refresh every configured interval; scanning runs off the main thread; the panel never blocks.

S7: Native macOS design matching ai-subs-menubar: vibrancy/transparency materials, rounded cards, SF Symbols, borderless panel under the status item (Control Center look).

S8: Personal, unsigned app; must build with Command Line Tools only (no full Xcode). The app performs read-only operations on repos and read-only HTTP GETs to Engram; stores no credentials (gh keyring and git are external).

## Tasks

T1 [S1,S7,S8] Scaffold: Package.swift, build-app.sh + Info.plist bundle script, status item with borderless panel skeleton, empty default config. Verify: `swift build` passes and the app launches showing an empty panel.
T2 [S3,S4] Core models, JSON config store, attention classification and staleness math — tests first.
T3 [S2,S5] Git scanner: porcelain parsers for status/worktree list/branch/upstream count with injected-output tests; process runner wiring.
T4 [S2,S5] GitHub scanner: origin-URL slug parsing + `gh pr list --json` parsing (open PR age, failing CI) with injected-output tests; graceful absence.
T5 [S2,S5,S6] Engram scanner (HTTP GET, per-project last activity) with response-parsing tests; aggregate scan pipeline and background refresh loop in AppState.
T6 [S1,S7,S4] Full panel UI (per-project cards, attention rows, clean state, config-error rows), settings window with folder picker, README, final functional verification (build, launch, manual smoke on real repos).

## Log

L1: "segun los que sabes de mi, que widget podriamos desarrollar para mejorar mi productividad o algo que pueda ayudarme en mi dia a dia" — user asked for a productivity widget proposal grounded in memory.
L2: User selected "Mission Control dev (recomendado)" from the proposal options (widget de menubar con estado de todos los proyectos: PRs abiertos, CI, ramas sin fusionar, worktrees viejos y última sesión Engram).
L3: Environment verified: gh 2.102.0 authed (trueno950, scopes repo+workflow); Engram v3.4.0 live at 127.0.0.1:7437 (`/health`, `/observations?project=X&limit=1`, `/sessions/recent` verified); ai-subs-menubar build pattern (SPM + CLT-only + build-app.sh bundle) reused as template; rental-car-cancun holds dozens of `.atl/*` detached-HEAD worktrees (target use case). Stale local branch detection deliberately excluded from v1: squash merges make `--no-merged` unreliable (xula-sigma lesson, obs-54549ce7e5a15adc/6011 context).
L4 (T6, S1-S8): Panel UI bound to AppState — attention cards severity-sorted (critical → warning → info) with per-repo branch, clean rows for zero-finding repos, and per-source `PRs unavailable` / `Engram unavailable` markers per S5 (never fabricated). Settings window (`SettingsWindow.swift`): `NSOpenPanel` folder picker adds repos, `minus.circle` removes them, `Stepper` controls refresh interval and the three thresholds; mutations persist immediately via AppState's `didSet`. Added `--scan-once` headless CLI that runs the full git/gh/Engram pipeline, prints per-repo summary plus severity-tagged findings, and exits 1 when any item is found. Added `DMC_CONFIG_DIR` env override so the config store can be isolated (used by the GUI launch smoke test). Tolerant config decoding fix: synthesized Codable required the `enabled` key, so a config without it silently fell back to `.default` (the whole load failed and `AppState.init` swallowed the error); replaced with a custom `init(from:)` using `decodeIfPresent(Bool.self, forKey: .enabled) ?? true`, mirrored for the root `AppConfig` numerics. Real-repo `--scan-once` verification: balanceados-pos → 14 uncommitted files (branch `feat/reports-module-improvement`); rental-car-cancun → 8 uncommitted files + 4 dirty `.atl/*` worktrees; dev-mission-control itself scanned cleanly. Reused the existing ConfigStore, GitScanner/GhScanner/EngramScanner, and AttentionMath throughout; no new state shape was introduced.
