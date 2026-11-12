# Feature: split-console-panel

Replace the compact-card menu bar panel and the separate repository detail window with the "Split console" design: a project list on the left and the selected project's detail on the right, in one popover.
Visual spec: `design/menubar-panel/03-split-console.html` (chosen artboard; `01-triage-inbox.html` and `02-resume-board.html` are alternatives).

## Specs

S1: Owner request, verbatim: "Implement the design artboard design/menubar-panel/03-split-console.html … Title: Split console. Tradeoff: Everything in one place, no separate detail window; a wide 760 px popover covers more of the screen. Implement it in the project's real stack. Use the artboard as the visual spec: map its parts to the project's existing components and styles, and do not copy the artboard HTML verbatim."

S2: Layout per the artboard: one 760 × 600 popover; a left sidebar (250 px) with the "Mission Control" title, a refresh button, a "Filter projects" field and the grouped project list; the selected project's detail on the right; a footer spanning both columns with the per-source state ("Git · 2 min ago", "GitHub · unavailable", "Engram · 2 min ago"), "Next scan in 3 min" and a Settings button. No separate detail window.

S3: Sidebar groups per the artboard ("Needs action", "To review", "Clean"), each row with a severity shape (not color alone), the project name, a short age ("40m", "3h", "4d") and a one-line reason ("Merge conflict · 2 files", "3 unpushed", "4 idle review worktrees"); paused projects show "Paused". The selected row is highlighted.

S4: Detail header per the artboard: project name, "main · ~/Documents/Projects/xula-sigma" (branch and home-abbreviated path), a primary "Open in VS Code" action (the configured editor), "Terminal" and a "•••" menu.

S5: "Where you left off" per the artboard: the latest Engram memory with its date ("Engram summary · 7 Nov 2:35 p.m."), an "Open memories" link to the per-project Engram panel, the last commit ("d34bec1 fix(territory): close the audit for assigned zones · 4 days ago") and a "Copy context to resume" action.

S6: "Worktrees" per the artboard: a table with "Worktree", "State" and "Last commit" columns, starting with the primary checkout ("main", "primary checkout", "Clean"); clean idle worktrees grouped into one block ("4 review worktrees, clean, idle 15–17 days", their folder and names) with "Copy cleanup command" and "Ignore this folder".

S7: "Pull requests" per the artboard: when GitHub was not read, say so instead of showing zero ("Not read. GitHub CLI is not signed in, so open PRs and CI are unknown — not zero.") with "Copy gh auth login".

## Tasks

T1 [S3,S5,S6] Core: project grouping, primary last commit read, short relative age, shell-safe cleanup command + tests — worker; commit `4f2ec05` (RED compile failures → GREEN 487/487).
T2 [S6] Core + config: per-repository ignored worktree folders (suppress idle notices, backward-compatible config) + tests — worker; commit `4f2ec05` (RED compile failures → GREEN 508/508). Slice boundary: `4f2ec05` closes the core slice (531 authored lines incl. tests); UI is the next slice.
T3 [S2-S7] UI: split console panel, remove the detail window — worker; commits `b51e5f1` (pure panel rules + 56 checks, RED compile failures → GREEN 564/564) and `e395709` (SwiftUI split console, detail window deleted; build + launch verified, panel not clicked by automation). Slice note: `e395709` is ~1.6k authored lines because the views only compile together.
T4 [S1,S2] README, design artboards, preview build and acceptance — inline; commit: the README/design commit that closes this feature; owner visual acceptance pending.

## Log

L1 (owner request, verbatim): "Implement the design artboard design/menubar-panel/03-split-console.html

Artboard: design/menubar-panel/03-split-console.html
Title: Split console
Tradeoff: Everything in one place, no separate detail window; a wide 760 px popover covers more of the screen

Implement it in the project's real stack. Use the artboard as the visual spec: map its parts to the project's existing components and styles, and do not copy the artboard HTML verbatim."

L2 (decisions against existing specs, `odd/tasks/dev-mission-control.md`):
- S3/S9 of that feature keep pending local changes informational ("no son una alerta por sí solos"). The artboard put "5 uncommitted" under "Needs action"; that sample conflicted with S9, so pending changes get their own "In progress" group instead. "Needs action" holds only warning/critical findings (conflicts, failing CI, unpushed commits).
- Projects whose Git read is unavailable and have no findings go to a "No data" group, never "Clean" (S5 of that feature: unavailable is no information).
- Engram stores no summary body (only `SessionSummaryInfo.title/date`), so "Where you left off" shows the latest memory title and date, not invented prose; the artboard's "38 memories" counter is not read by the panel and is omitted.
- The primary checkout's last commit is not read today; T1 adds one read-only `git log -1` per repository.
- GitHub is "unavailable" with no error when a repository has no GitHub remote; the PR section then says no remote was found, and "Copy gh auth login" appears only when the current error is an authentication error.
- The footer shows each source as an aggregate over projects ("GitHub · 3 of 9 read") so a few local-only repositories do not look like a global outage.

L3 (verification): `swift run DevControlLogicTests` 564/564, `swift build` clean, `scripts/build-app.sh` built and the app launched and stayed up. The panel itself was not opened by automation (the accessibility click does not trigger the status item's mouse-up action), so the visual comparison with the artboard is the owner's acceptance step.
