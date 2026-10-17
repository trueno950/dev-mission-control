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
- Slice B (T17–T20 panel UI): the Engram panel window, search, retake-context copy, and sessions browsing.
- Slice C (T21): README, preview build, and acceptance checks.

Each PR is opened against its parent slice and retargeted to `main` immediately before its own merge, as in the previous delivery. Native review, when due, runs on the committed slice candidate with the lenses that match that slice.

## Tasks

T16 [S3,S4] Core: read-only Engram panel client, response parsers, project resolver, per-read freshness, request builder, retake-context composer + tests — inline; commits `3c30ca0` (models, parsers, resolver, request builder) and `ea97a09` (client reads, retake composer).
T17 [S2,S5,S6] Panel window per project: counters header, latest memories with full content and copy, entry point from the repository detail window; TUI as a secondary action — inline. Commit: pending.
T18 [S2] In-app memory search over `/search` — inline. Commit: pending.
T19 [S2] Copy retake context: `/context` markdown + current Git state — inline. Commit: pending.
T20 [S2] Recent sessions browsing over `/sessions/recent` — inline. Commit: pending.
T21 [S6] README documentation, preview build, acceptance checks — inline. Commit: pending.

## Log

L1 (owner request, verbatim): "me gustaria enfocar mas las funcionalidades en mejorar la coenxion con engram, actualmente solo dice openmemories y abre l aterminal pero solo abre la pantalla de carga, abra la manera de hacer una conexion directa? o leer info para mostrar directo en este widget, analiza primero y dime"

L2 (read-only analysis, then owner scope choice): probed the live Engram 3.4.0 server at `127.0.0.1:7437` — `/stats` is project-scoped (without `project` it reports the server's own detected project) and no global-total endpoint exists; `/observations` and `/search` return the full `content`; `/context` returns the "Memory from Previous Sessions" markdown; `/prompts` and `/sessions` answer 405 to GET. `engram tui` works but takes ~5.6 s to leave its "Loading stats..." box (3,111 sessions / 6,056 observations) and shows global numbers even when launched from the project directory, so it cannot answer per-project questions. `/projects` exposes per-project `directories`, which is the reliable way to match a local repository when the Engram project name differs from the folder name. Owner then chose the widest scope: "Panel + sesiones recientes".
