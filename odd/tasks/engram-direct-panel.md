# Engram direct panel

Feature delivery for Dev Mission Control: read the local Engram HTTP API directly and show
per-project memories, search, retake context, and recent sessions inside the app, with the
terminal TUI kept as a secondary action. Read-only against Engram: never a write, never its SQLite.

## Specs

S1 (owner request, verbatim): "me gustaria enfocar mas las funcionalidades en mejorar la coenxion con engram, actualmente solo dice openmemories y abre l aterminal pero solo abre la pantalla de carga, abra la manera de hacer una conexion directa? o leer info para mostrar directo en este widget, analiza primero y dime"

S2 (owner scope choice, verbatim): label "Panel + sesiones recientes" — "Todo lo del panel más navegación de sesiones recientes (/sessions/recent: inicio, fin, cuántas memorias). La opción más completa." The panel it builds on: "Ventana por proyecto con contadores reales (/stats), últimas memorias con contenido completo, búsqueda in-app (/search) y botón Copiar contexto para retomar (/context + Git actual). El TUI queda como acción secundaria."

S3 (interfaces, verified against Engram 3.4.0 before writing code; no invented endpoints): read-only GET only — `/health`, `/stats?project=`, `/projects` (name, counts, `directories`), `/observations?project=&limit=&type=`, `/observations/{id}`, `/search?q=&project=&limit=`, `/sessions/recent?project=&limit=`, `/context?project=`, `/conflicts?project=`. `/prompts` and `/sessions` answer 405 to GET: they are writing endpoints and stay unused. Never write to Engram and never open its SQLite.

S4 (project matching): a repository maps to its Engram project by explicit `engramProject` config first, then by the most specific `directories` prefix from `/projects`, then by folder name. Reason (observed): Engram holds `car-rental-cancun` for the folder `rental-car-cancun`, and `dev-mission-control` also registers the parent `Projects/`.

S5 (freshness, carried over from the delivered feature): one row per source with the read time; a failed read shows the current failure in its own right and keeps the last good value marked stale; "sin información" when there is no value; the panel never claims the memory matches the code.

S6 (language, carried over): interface language follows the system (`es*` → Spanish, otherwise English) through `L10n.t(es, en)`; technical terms stay as-is (worktree, staged, unstaged, untracked, diff, PR, checks).

S7 (TUI): `engram tui` stays reachable as a secondary action, labelled honestly as global and slow; measured ~5.6 s to leave "Loading stats..." on the current data volume.

## Delivery strategy

Stacked PR chain against the verified default branch (`main`), sliced by layer, because the first slice already passed the ~400-authored-line review guideline and the destination repository documents no issue-first policy (no `.github/`, no `type:*` labels). Slices:

- Slice A (T16 core): commits `3c30ca0` (models, parsers, resolver, request builder) and `e143669` (client reads, retake composer) — 993 authored lines including this document; boundary recorded when the slice reminder fired at T16.
- Slice B (T17–T20 panel UI): the Engram panel window, search, retake-context copy, and sessions browsing. Cumulative at T19: 5 commits, 2,008 authored lines since `origin/main`; the slice boundary is recorded here, and the chain will be cut as PR A = T16 core, PR B = T17–T20 panel UI, PR C = T21 docs/preview before any push. Boundary: T17 landed as commit `b9b85aa` at 546 authored lines — above the ~400-per-commit guideline — so the reminder fired once here; T18–T20 continue this same slice and each stays small.
- Slice C (T21): README, preview build, and acceptance checks.

Each PR is opened against its parent slice and retargeted to `main` immediately before its own merge, as in the previous delivery.

Opened chain (2026-10-17, after the owner chose "Pushear y abrir la cadena de PRs"): PR #4 `main` ← `feat/engram-panel-core` @ `ad61756` (+1,003/−0); PR #5 ← `feat/engram-panel-ui` @ `a3ac5f9` (+1,084/−40); PR #6 ← `feat/engram-panel-docs` @ `7661cc6` (docs). Each child is retargeted to `main` immediately before its own merge; merge SHAs are recorded here when they land. Native review, when due, runs on the committed slice candidate with the lenses that match that slice.

## Tasks

T16 [S3,S4] Core: read-only Engram panel client, response parsers, project resolver, per-read freshness, request builder, retake-context composer + tests — inline; commits `3c30ca0` (models, parsers, resolver, request builder) and `e143669` (client reads, retake composer).
T17 [S2,S5,S6] Panel window per project: counters header, latest memories with full content and copy, entry point from the repository detail window; TUI as a secondary action — inline; commit `b9b85aa` (546 authored lines).
T18 [S2] In-app memory search over `/search` — inline; commit `b2de2a9` (206 authored lines; debounce, out-of-order guard, own freshness line, "sin resultados" wording).
T19 [S2] Copy retake context: `/context` markdown + current Git state — inline; commit `2a36afe` (the composer now prints the localized no-information line instead of counters whenever the Git read is not current — RED 10 failing checks → GREEN 440/440).
T20 [S2] Recent sessions browsing over `/sessions/recent` — inline; commit `a3ac5f9` (own freshness line, "sin sesiones registradas", "en curso" for an open session).
T21 [S6] README documentation, preview build, acceptance checks — inline; commit `2964dce`; preview `build/DevMissionControl-preview-engram.app` built from 440/440 checks and `git diff --check` clean; owner visual acceptance pending.

## Log

L1 (owner request, verbatim): "me gustaria enfocar mas las funcionalidades en mejorar la coenxion con engram, actualmente solo dice openmemories y abre l aterminal pero solo abre la pantalla de carga, abra la manera de hacer una conexion directa? o leer info para mostrar directo en este widget, analiza primero y dime"

L2 (read-only analysis, then owner scope choice): probed the live Engram 3.4.0 server at `127.0.0.1:7437` — `/stats` is project-scoped (without `project` it reports the server's own detected project) and no global-total endpoint exists; `/observations` and `/search` return the full `content`; `/context` returns the "Memory from Previous Sessions" markdown; `/prompts` and `/sessions` answer 405 to GET. `engram tui` works but takes ~5.6 s to leave its "Loading stats..." box (3,111 sessions / 6,056 observations) and shows global numbers even when launched from the project directory, so it cannot answer per-project questions. `/projects` exposes per-project `directories`, which is the reliable way to match a local repository when the Engram project name differs from the folder name. Owner then chose the widest scope: "Panel + sesiones recientes".


L3 (native review of the feature: three lineages, two bounded corrections, approval burned): the review ran on the committed feature candidate (base `237500a`, 11 paths, 2,133 changed lines growing to 2,188, tier medium, lenses `review-resilience` + `review-reliability`, correction budget 200) and closed approved on the third fresh lineage `review-3ea0e5ee59c39c72` after two bounded corrections:

- Lineage `review-715bf09f607410dc` (target `e81312c8…`) froze R3-001 and R3-002: a failed `/projects` read dropped the resolution to the folder name while stats/memories/sessions stayed retained from the directory-resolved project (one project's header showing another's data), and search hits were retained across query changes with a query-string-only out-of-order guard. Correction `050c57c` pinned the project for every read, dropped every retained per-project value on a project change, tied the retained search value to its own query and added a monotonic request id.
- Lineage `review-a802a5a2630b3d25` (target `9db5487a…`) froze R3-001, R4-001 and R4-002 — the same class in the two remaining async paths: the search and the retake-context copy captured the resolved project before their awaits and never revalidated it. Correction `568de8e` captures the project with each request and revalidates it after every await.
- Lineage `review-3ea0e5ee59c39c72` (target `11ba5b38…`, tree `c23feb2b…`) approved with the authority burned (`gentle-ai.review-acknowledged/v1`) and only non-blocking advisories: `R3-search-stuck`/`R4-001` (a discarded reply or a project change can leave the search spinner set because the guard returns before clearing it), `R3-copy-silent-noop`/`R4-003` (the retake copy returns silently when the project changed), `R4-002` (the load path can leave a stale spinner on a project change) and `R3-transport-untested` (the URL-stub tests do not cover the transport error path).

Facade defect (maintainer follow-up): the provider's correction-plan slot is unreachable from the Pi facade. `gentle_review_capture` rejected the exact serialized `review.capture-correction-plan` binding that bound STATUS re-offered identically — `collectBinding is missing or stale for current STATUS` — on both correction rounds and also with an explicit `workspaceRoot`. Both parked lineages were therefore abandoned with audited `operator_disposition` records (quarantines `review-715bf09f607410dc-710081529` and `review-a802a5a2630b3d25-1527672535`), and each correction was carried by a fresh lineage instead.

Delivery as it stands: the stacked chain is PR #4 (core), PR #5 (panel UI), PR #6 (docs) and PR #7 (`fix/engram-panel-project-pinning`, both corrections and this record); merges remain the owner's decision.


L4 (merges): the chain was integrated into `main` in order, each child retargeted to `main` immediately before its own merge and re-checked MERGEABLE/CLEAN: PR #4 → `8737d80`, PR #5 → `0e912b3`, PR #6 → `2e5a146`, PR #7 → `1a62262`; local `main` was fast-forwarded to the last merge and all four slice branches were deleted locally and remotely. The merged tree carries the whole feature plus both review corrections and this record.


L5 (advisory fixes merged): the four non-blocking advisories from the approved review were closed in their own small change — commit `a8d933c`: a discarded search reply clears the spinner when no newer request took over, a project change during the retake read shows a transient notice instead of a silent no-op, `load()` re-issues an active search after a project change, and the client suite covers the transport error path (7 new checks, 447/447). Native assess over the committed range returned risk medium with `reviewDue: false` (under budget) and no independent verifier. PR #8 merged into `main` as `a2335df`; the branch was deleted locally and remotely.
