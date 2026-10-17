# Feature: dev-mission-control

Native macOS menu bar app that answers "where was I and what needs attention?" across all local projects in one click.

## Specs

S1: "un segundo widget con la misma base: un 'Mission Control' de desarrollo en la barra de menú que responda en un click: PRs abiertos esperando, CI rojo, ramas sin fusionar, worktrees viejos para limpiar, y la última sesión de Engram por proyecto" — a menu bar item opening a status panel listing tracked projects and their attention items.

S2: Data sources per project, read-only and official only: local `git` (current branch, dirty file count, unpushed commit count, worktree list), `gh` CLI (open PRs with CI check status), Engram HTTP API (`GET /observations?project=<name>&limit=1` for last activity; server `http://127.0.0.1:7437`). No scraping, no mutations of user repos.

S3: Attention classification (pure logic, threshold-driven): uncommitted local changes are informational and do not create an attention finding; verified conflicts and failing checks require attention; unpushed commits remain an evidence-based finding; PR age and clean-worktree age are informational and do not establish urgency. Only current source reads may establish findings; stale or unavailable data is surfaced as no information, not as a clean result or attention alert. Agent inactivity is sourced only from Engram, never inferred from Git or file timestamps. Explicitly paused projects receive neither Engram inactivity nor idle-clean-worktree notices. This supersedes the previous dirty-worktree warning and age-only PR warning rules. Existing thresholds remain configurable for any informational age display.

S4: Configuration persisted as JSON in Application Support (`~/Library/Application Support/DevMissionControl/config.json`): repo list (absolute path; GitHub slug and Engram project name optional, derived when absent), refresh interval (default 5 min), thresholds, and optional per-repository `isPaused` defaulting to false. The settings window can pause or resume a project; paused projects receive no inactivity findings. Existing configuration remains backward-compatible.

S5: Graceful degradation: without `gh` (missing or unauthenticated) do not fabricate an empty PR result; without the Engram server do not fabricate activity; a missing/invalid repo path is an unavailable Git source instead of a crash, not a clean result or an attention alert. Each source reports its identity, last read time, availability, and freshness. If a refresh fails after a successful read, retain the last valid result marked stale and separately show the current source failure. Findings use only current reads, while independent current sources remain classifiable. Git remains queryable if GitHub or Engram fails.

S6: Manual refresh (button) plus automatic refresh every configured interval; scanning runs off the main thread; the panel never blocks. A refresh cannot overlap another refresh. External calls have bounded timeouts, and periodic scanning does not invoke a model.

S7: Native macOS design matching ai-subs-menubar: vibrancy/transparency materials, rounded cards, SF Symbols, borderless panel under the status item (Control Center look). Repository cards keep a compact summary; per L25 the inline expansion is superseded by a separate repository detail window. The primary checkout branch is distinct from linked-worktree branches; staged, unstaged, and untracked changes are separated; header counts distinguish affected projects from visible notices and identify source freshness.

S8: Personal, unsigned app; must build with Command Line Tools only (no full Xcode). The app performs read-only repository queries and read-only HTTP GETs to Engram; stores no credentials (gh keyring and git are external). Actions may open a selected worktree, show its diff, and open only a PR whose branch association is verified. No commit, push, merge, or worktree deletion is automated. Spawned processes use executable paths and separate arguments; repository paths are never concatenated into shell commands.

S9: The user requested these exact status rules: “En curso: cambios locales recientes; no son una alerta por sí solos.” The user then revised the wording and policy: “También cambiaría en el prompt ‘cambios locales recientes’ por ‘cambios locales pendientes’ para eliminar la ambigüedad. sin umbral”. Therefore any currently pending staged, unstaged, or untracked Git changes are informational, with no age cutoff or alert by themselves; this describes repository state, not agent activity. Attention requires explicit evidence such as an unmerged conflict or failing CI. A project explicitly marked paused has no inactivity alert.

S10: The requested compact card includes the repository name, primary checkout branch, number of worktrees, primary reason, expandable per-worktree branch/path, separate staged/unstaged/untracked counts, distinct affected-project and notice counts, and last-read time plus source. The primary checkout branch must not be confused with linked-worktree branches.

S11: The requested actions open the selected worktree in an editor configurable in Mission Control, a terminal, or a folder; display its diff; and open a PR only when the worktree branch-to-PR association is verified. For PR association, require one current PR whose `headRefName` and `headRefOid` exactly match the worktree branch and HEAD commit, and open only its returned HTTPS `url`; branch-name-only matches are insufficient. No commit, push, merge, or worktree deletion is automatic. Actions must target the selected worktree even when its path contains spaces.

S12: The requested robustness rules separate connectors, normalized data, attention rules, and UI; prevent overlapping scans and keep the UI responsive during scanning (wording corrected by the user in L26); bound external operations; preserve last valid data as stale after a refresh error; keep local Git available when another integration fails; avoid model calls in periodic scans; and pass process arguments separately without putting paths into shell command strings. A GitHub error is not an empty PR list.

S13: Acceptance cases quoted from the user: “Un worktree con cambios recientes no aparece como urgente”; “Un conflicto sí requiere atención”; “Un fallo de GitHub no equivale a ‘sin PR’”; “Sin información: integración ausente, error o datos desactualizados.”; “Cada acción abre el worktree correcto, incluso con espacios en la ruta”; “Los contadores coinciden con los avisos visibles”; “Los datos antiguos están identificados.” The first case follows the user's amended no-cutoff wording in S9.

S14: The next delivery is explicitly “Retomar proyecto”: “recuperar desde Engram el último objetivo, avances, pendientes y archivos relevantes, mostrando fuente y fecha; contrastarlo con Git actual y permitir copiar contexto para IA. Utiliza interfaces soportadas y no escribas directamente en la base de Engram.” This is recorded as the next feature, not part of this first delivery.

S15: Additional product guidance includes the exact distinction “2 proyectos · 5 avisos” and the rule “La antigüedad por sí sola no determina urgencia.” First-delivery implementation remains bounded to S9-S13; later P1/P2 features in the user feedback remain deferred.

S16: “La interfaz mezcla español e inglés — Unificarla en español, conservando términos técnicos habituales como worktree, staged y diff.” Amended by L31: “y el idioma deberia ser automatico de acuerdo al del sistema”. The interface language therefore follows the system automatically — Spanish for any `es*` preferred language, English otherwise — implemented as `AppLanguage.current` in DevControlCore (localized AttentionMath messages, test-asserted in both languages) and an `L10n` picker for all panel, settings, detail-window, and CLI strings. Worktree, staged, unstaged, untracked, diff, PR, and checks remain technical terms in both languages.

S17: “Mostrar primero los que tienen conflictos, después los que tienen cambios. Ocultar los limpios bajo ‘Ver los 137’.” y “Hacer clic en el aviso debe abrir y enfocar directamente prop-139.” Worktrees are ordered conflicts first, then worktrees with pending changes, then clean ones collapsed under “Ver los N worktrees limpios”. Clicking an attention notice opens the repository detail window focused on that notice's worktree (or the top of the detail when it has no worktree). Also from L25: “La tarjeta expandida ocupa prácticamente toda la ventana — Mantener el resumen compacto y abrir el detalle del repositorio en una ventana aparte.” and “Los otros cuatro proyectos deben poder consultarse… añade acceso visible a Todos, aunque estén limpios o pausados.” The panel therefore keeps compact card summaries, opens one repository detail window per project, and offers a visible Atención/Todos selector.

S18: “Usar ‘Pausar proyecto’ como etiqueta del control y mostrar ‘Activo/Pausado’ como estado independiente.” y “Mostrar ‘Configurar editor…’ cuando todavía no haya uno seleccionado.” The Settings row shows a “Pausar proyecto” switch plus an independent Activo/Pausado status label, and a worktree action menu without a configured editor offers “Configurar editor…” that opens Settings.

S19: “‘Engram current’ necesita una definición precisa. Una consulta reciente no garantiza que la memoria esté actualizada respecto al código. Mejor mostrar por separado ‘Conectado · consultado hace…’ y ‘Último resumen guardado…’ cuando exista ese dato.” y “El texto ‘last commit 3 days ago’ puede mantenerse como información, pero no representa la última modificación local ni actividad del agente.” The Engram source shows its connection state (freshness plus last successful read time) separately from the most recent saved session summary (an observation of type session_summary within a bounded recent page); a missing summary is never fabricated. Last-commit age remains informational and is never presented as local modification time or agent activity.

S20: “porque aparecen dos git y github, engram hay alguna forma de mostrar algun dato mas o abrir las memorias?… el orden de lo nuevo que garegaste se ve muy achocado, si hay pr sale el link para abrirlo en el navegador? las diff como se muestran si muestra lo rojo y lo verde, lo que se agrega y lo que se quite”. Freshness renders as one airy row per source (fixed source label, state plus read time, inline extras) instead of cramped side-by-side badges. Engram rows show the latest activity title and date plus the saved summary, and an “Abrir memorias” action opens the supported `engram tui` in Terminal (the installed local server has no web dashboard: `/dashboard/` returns 404, verified); the action runs osascript with separate arguments and a fixed command. Open PRs are listed in the repository detail window with an Open button that uses only the HTTPS URL returned by `gh` (no worktree-association requirement, because no worktree is involved). Diffs render additions green with a light green background, removals red with a light red background, hunk headers in the accent color, and metadata dimmed, via the tested `DiffParser`.

## Tasks

T1 [S1,S7,S8] Scaffold: Package.swift, build-app.sh + Info.plist bundle script, status item with borderless panel skeleton, empty default config. Verify: `swift build` passes and the app launches showing an empty panel.
T2 [S3,S4] Core models, JSON config store, attention classification and staleness math — tests first.
T3 [S2,S5] Git scanner: porcelain parsers for status/worktree list/branch/upstream count with injected-output tests; process runner wiring.
T4 [S2,S5] GitHub scanner: origin-URL slug parsing + `gh pr list --json` parsing (open PR age, failing CI) with injected-output tests; graceful absence.
T5 [S2,S5,S6] Engram scanner (HTTP GET, per-project last activity) with response-parsing tests; aggregate scan pipeline and background refresh loop in AppState.
T6 [S1,S7,S4] Full panel UI (per-project cards, attention rows, clean state, config-error rows), settings window with folder picker, README, final functional verification (build, launch, manual smoke on real repos).
T7 [S9,S13] Normalize Git status per checkout/worktree (staged, unstaged, untracked, conflicts) with parser tests — worker, done; commit: 8024cbe.
T8 [S9,S13] Implement evidence-based attention classification and backward-compatible paused-project config; test pause suppression and non-urgent pending changes; document evidence rules — inline, done; commit: 90285b7.
T9 [S3,S5,S6,S12,S13] Add source timestamps/freshness, bounded non-overlapping scans, and last-good stale retention without losing Git when remote sources fail; classify stale/unavailable reads as no information; document the source states — worker plus parent review, done; source slice: `d0ae1ea`; classification slice: `d5f366e`; subprocess-timeout slice: `35dea99`; verified 267/267 logic checks and `swift build`.
T10 [S11,S12,S13] Implement a user-configurable editor target, argument-safe worktree actions, and verified worktree-to-PR mapping; test paths containing spaces and keep all operations read-only — inline, done; commits: `84c25ce` (behavior) and `e9cd51a` (ODD evidence); differential proof recorded in L39.
T11 [S10,S12,S13] Implement compact expandable repository cards, accurate project/notice counts, per-source freshness, pause controls, README updates, and end-to-end acceptance checks — inline, implemented; visual review received (L25); summary-count core committed in `a542b28` and card/pause UI in `4133b9e`; acceptance inspection pending.
T12 [S16,S17] Spanish interface; worktree ordering (conflicts → changes → clean) with collapsed cleans; attention notices that open the repository detail window focused on their worktree; compact card summaries; visible Atención/Todos access — implemented; core `a542b28`, UI `4133b9e`; visual acceptance pending.
T13 [S18] “Pausar proyecto” switch with independent Activo/Pausado status and the “Configurar editor…” action CTA — implemented; commit `4133b9e`; visual acceptance pending.
T14 [S19,S5] Engram connection state shown separately from the latest saved session summary (bounded observations page filtering type session_summary) with stale retention — implemented, 302/302 checks; commit `a542b28`.
T15 [S12,S13,S15] Spec wording fix, README updates, acceptance checks, and work-unit commits — README `235d449`; this ODD evidence commit completes the docs; owner UI inspection remains the open acceptance gate.

## Log

L1: "segun los que sabes de mi, que widget podriamos desarrollar para mejorar mi productividad o algo que pueda ayudarme en mi dia a dia" — user asked for a productivity widget proposal grounded in memory.
L2: User selected "Mission Control dev (recomendado)" from the proposal options (widget de menubar con estado de todos los proyectos: PRs abiertos, CI, ramas sin fusionar, worktrees viejos y última sesión Engram).
L3: Environment verified: gh 2.102.0 authed (trueno950, scopes repo+workflow); Engram v3.4.0 live at 127.0.0.1:7437 (`/health`, `/observations?project=X&limit=1`, `/sessions/recent` verified); ai-subs-menubar build pattern (SPM + CLT-only + build-app.sh bundle) reused as template; rental-car-cancun holds dozens of `.atl/*` detached-HEAD worktrees (target use case). Stale local branch detection deliberately excluded from v1: squash merges make `--no-merged` unreliable (xula-sigma lesson, obs-54549ce7e5a15adc/6011 context).
L4 (T6, S1-S8): Panel UI bound to AppState — attention cards severity-sorted (critical → warning → info) with per-repo branch, clean rows for zero-finding repos, and per-source `PRs unavailable` / `Engram unavailable` markers per S5 (never fabricated). Settings window (`SettingsWindow.swift`): `NSOpenPanel` folder picker adds repos, `minus.circle` removes them, `Stepper` controls refresh interval and the three thresholds; mutations persist immediately via AppState's `didSet`. Added `--scan-once` headless CLI that runs the full git/gh/Engram pipeline, prints per-repo summary plus severity-tagged findings, and exits 1 when any item is found. Added `DMC_CONFIG_DIR` env override so the config store can be isolated (used by the GUI launch smoke test). Tolerant config decoding fix: synthesized Codable required the `enabled` key, so a config without it silently fell back to `.default` (the whole load failed and `AppState.init` swallowed the error); replaced with a custom `init(from:)` using `decodeIfPresent(Bool.self, forKey: .enabled) ?? true`, mirrored for the root `AppConfig` numerics. Real-repo `--scan-once` verification: balanceados-pos → 14 uncommitted files (branch `feat/reports-module-improvement`); rental-car-cancun → 8 uncommitted files + 4 dirty `.atl/*` worktrees; dev-mission-control itself scanned cleanly. Reused the existing ConfigStore, GitScanner/GhScanner/EngramScanner, and AttentionMath throughout; no new state shape was introduced.

L5 (T7-T11 request): “Quiero evolucionar mi aplicación existente “Dev Mission Control”, un widget de escritorio para supervisar mis proyectos de desarrollo. Utilizo Engram, Gentle AI y Gentle Shell.

Objetivo: identificar qué requiere mi atención y retomar proyectos rápidamente con contexto verificable.

Primero inspecciona el repositorio, sus instrucciones, arquitectura, pruebas y versiones instaladas. Conserva el stack existente. Comprueba las interfaces reales de las herramientas antes de diseñar integraciones; no inventes comandos, endpoints, rutas ni formatos.

Implementa una primera entrega limitada a:

1. Clasificación de estados:
   - En curso: cambios locales recientes; no son una alerta por sí solos.
   - Necesita atención: motivos verificables, como conflictos o checks fallidos.
   - Sin información: integración ausente, error o datos desactualizados.
   - Proyectos pausados: sin avisos de inactividad.
   Define explícitamente qué evidencia usa cada regla. No deduzcas actividad del agente a partir de cambios de archivos.

2. Tarjetas compactas por repositorio:
   - Nombre, rama principal consultada, cantidad de worktrees y motivo principal.
   - Detalle desplegable con la rama y ruta propias de cada worktree.
   - Separar archivos staged, unstaged y untracked.
   - Contadores que distingan proyectos afectados y avisos.
   - Fecha de última lectura y fuente del dato.

3. Acciones:
   - Abrir editor, terminal y carpeta en el worktree seleccionado.
   - Consultar diff y abrir PR cuando exista una asociación verificada.
   - No ejecutar commit, push, merge ni borrar worktrees automáticamente.

4. Robustez:
   - Separar conectores, modelo de datos, reglas de atención e interfaz.
   - Evitar escaneos superpuestos y bloquear la interfaz.
   - Aplicar límites de tiempo y conservar el último resultado válido marcado como antiguo.
   - Un fallo en una integración no debe impedir consultar Git local.
   - No utilizar llamadas a modelos durante el escaneo periódico.
   - Ejecutar procesos con argumentos separados, sin concatenar rutas en comandos de shell.

Verifica al menos estos escenarios:
- Un worktree con cambios recientes no aparece como urgente.
- Un conflicto sí requiere atención.
- Un fallo de GitHub no equivale a “sin PR”.
- Cada acción abre el worktree correcto, incluso con espacios en la ruta.
- Los contadores coinciden con los avisos visibles.
- Los datos antiguos están identificados.

Antes de editar, presenta un diagnóstico breve basado en archivos reales y el alcance de esta entrega. Después implementa y verifica siguiendo las instrucciones del proyecto.

Deja como siguiente entrega “Retomar proyecto”: recuperar desde Engram el último objetivo, avances, pendientes y archivos relevantes, mostrando fuente y fecha; contrastarlo con Git actual y permitir copiar contexto para IA. Utiliza interfaces soportadas y no escribas directamente en la base de Engram.

Al terminar, explica qué cambió, cómo se verificó y qué limitaciones reales quedan.”

L6 (additional product feedback): “Lo que veo en tu widget
La agrupación por repositorio funciona bien y los ajustes son sencillos. Pero hay cuatro oportunidades claras:
- Todo cambio sin commit parece una alerta. Durante el desarrollo eso es normal; conviene distinguir actividad en curso de trabajo abandonado.
- “2 need attention” es ambiguo: aparecen dos repositorios, pero cinco motivos. Mejor: “2 proyectos · 5 avisos”.
- Falta contexto para actuar. final-134 no explica qué trabajo contiene, si terminó o cuál sería el siguiente paso.
- La ventana tiene bastante espacio vacío. Una vista compacta y tarjetas expandibles permitirían consultar más sin convertirlo en un dashboard enorme.
Además, “sin actividad del agente durante 14 días” debería depender del proyecto: puede ser normal en uno pausado.
Cómo aprovechar tu ecosistema
Herramienta    Qué aprovecharía en el widget
Engram    Último resumen, decisiones, bloqueos y siguiente paso por proyecto. Tiene interfaces CLI, HTTP y MCP; usaría una interfaz soportada, evitando modificar directamente su SQLite.
Gentle AI    Diagnóstico de configuración y evidencia del flujo de trabajo disponible en la instalación.
Gentle Shell    Estado de sesiones y trabajo, cuando exista una interfaz compatible para consultarlo; acceso rápido para continuar en la herramienta.
Git / GitHub    Estado real de worktrees, cambios, commits pendientes de subir, PR y checks.
Engram documenta recuperación de contexto por proyecto y resúmenes de sesión. Gentle AI configura agentes y su flujo de trabajo. Gentle Shell ya ofrece vistas de cambios, agentes y tareas: tu oportunidad es reunir varios proyectos en una vista global, con enlaces al detalle de cada herramienta. Las capacidades deben comprobarse contra tus versiones locales. GitHub
Estas son las mejoras que priorizaría
Prioridad    Mejora    Comportamiento concreto
P0    Alertas con significado    Separar “En curso”, “Necesita atención” y “Sin información”. Cambios recientes sin commit son informativos; conflictos o un check fallido requieren atención.
P0    Acciones desde cada tarjeta    Abrir editor, terminal en el worktree correcto, carpeta, diff y PR.
P0    Estado confiable    Mostrar fuente y última lectura. Si GitHub falla, indicar “No disponible”; conservar el último dato marcado como antiguo.
P1    “Retomar proyecto”    Mostrar objetivo, último avance, pendiente y archivos relevantes desde Engram; permitir copiar el contexto.
P1    Detalle de worktrees    Rama, ruta, cambios staged/unstaged/untracked, upstream y PR asociado cuando se pueda verificar.
P1    Seguimiento de PR    Distinguir borrador, revisión pendiente, cambios solicitados y checks fallidos. La antigüedad por sí sola no determina urgencia.
P1    Notificaciones útiles    Avisar cuando cambia el estado, sin repetir la misma notificación en cada escaneo. Permitir posponer.
P2    Salud del entorno    Detectar herramientas disponibles y presentar diagnósticos bajo demanda, con explicación y acción sugerida.
P2    Cierre de jornada    Resumen revisable de trabajo hecho y pendientes; guardarlo en Engram mediante una acción explícita.
La función que más valor te daría: “Retomar proyecto”
Al abrir xula-sigma, me gustaría encontrar:
- Rama y worktree seleccionados.
- Último objetivo registrado.
- Qué se completó y qué quedó pendiente.
- Bloqueos conocidos.
- Fecha y origen del resumen.
- Botones Abrir terminal, Abrir editor y Copiar contexto para IA.
Es importante separar lo que dice la memoria de lo que Git muestra ahora. Si Engram dice “verificación completada” pero existen cambios posteriores, el widget debe señalarlo. Tampoco debería deducir que un agente está trabajando únicamente porque haya archivos modificados.
Cambios de interfaz que haría primero
1. Pestañas Atención · En curso · Todos.
2. Tarjetas compactas con una razón principal y detalles desplegables.
3. Cabecera con “Actualizado hace 30 s” y estado de conexiones.
4. Selector de proyecto activo, pausado o archivado.
5. Configuración por repositorio para ignorar avisos que no aplican.
6. Búsqueda y navegación por teclado.
Para rental-car-cancun, mostraría “4 worktrees con cambios” y desplegaría cada uno con sus acciones. La rama main de la tarjeta principal no debería confundirse con las ramas de esos worktrees.
Cómo desarrollarlo sin volverlo frágil
Separaría los conectores —Git, GitHub, Engram y Gentle— del motor de alertas y de la interfaz. Cada conector devolvería datos normalizados con fecha, origen y estado de disponibilidad.
El escaneo habitual debería funcionar sin llamadas a un modelo. Reservaría la IA para acciones como “Preparar contexto” o “Resumir jornada”. Así el widget puede seguir siendo rápido y útil aunque no haya una sesión de IA disponible.
También evitaría depender del texto decorado de la terminal: primero buscar salidas estructuradas o interfaces documentadas; si una integración no existe en tu versión, mostrarla como no disponible.
Voy a dejarte el encargo en un bloque de texto listo para copiar, usando la función de borradores.”

L7 (decision): “También cambiaría en el prompt ‘cambios locales recientes’ por ‘cambios locales pendientes’ para eliminar la ambigüedad. sin umbral”.

L8 (implementation interpretation): A paused project suppresses both Engram inactivity and informational idle-clean-worktree notices; the latter is based only on last commit age and never implies agent activity.

L9 (slice boundary): T7 is committed as `8024cbe` and T8 as `90285b7`; T9 starts a separate review slice on the feature branch.

L10 (route): T9 uses the worker route for its bounded connector/AppState reliability changes; the parent owns verification, documentation/memory projection, and commit.

L11 (spec clarification from the original request): “Sin información: integración ausente, error o datos desactualizados.” Only current source data may create findings; stale and unavailable values remain distinguishable from clean results, while other current sources continue independently.

L12 (T9 slice boundary): Source freshness and last-good retention committed as `d0ae1ea` (`feat(data): retain source freshness across scan failures`), 371 diff lines. Remaining T9 commits are limited to attention classification and process deadlines.

L13 (T9 slice boundary): Current-only finding classification committed as `d5f366e` (`fix(attention): ignore stale source evidence`), 161 diff lines. The remaining T9 slice is subprocess deadline enforcement and its tests.

L14 (T9 slice boundary): Subprocess deadline enforcement and its regression tests were committed as `35dea99` (`fix(process): enforce deadlines on process exit`), 237 diff lines; this slice is confined to `ProcessRunner`, the process test suite, and its test entry point.

L15 (T9 completion): Verified `swift run DevControlLogicTests` (267/267), `swift build`, and `git diff --check`. Current source reads alone create findings; stale values remain available with their original read time and current failure; subprocess deadlines follow process exit rather than pipe EOF.

L16 (T10 editor decision): User selected “Configurable en Mission Control” for the Editor action.

L17 (T10 interface evidence and decision): The installed `gh pr list --help` lists JSON fields `headRefName`, `headRefOid`, and `url`; `/usr/bin/open` usage supports `-a` (application), `-b` (bundle identifier), and file arguments. PR links will require one exact branch-and-HEAD match and a returned HTTPS URL; all selected paths remain separate process arguments.

L18 (T10 verification blocker): The base-versus-candidate `--scan-once` comparison for a config containing `editorApplicationPath` exceeded its 30-second command timeout while building the scratch baseline. Per timeout policy it was not retried or moved to background; the owner must decide whether to accept this missing comparison or authorize a different bounded proof.

L19 (T10 verification results): The focused logic suite passed 291/291 checks, `swift build` passed after replacing the unavailable SwiftUI `@State` macro with `@StateObject`, and `git diff --check` passed. The T10 implementation diff was reviewed; its required differential proof remains unresolved.

L20 (T10 delivery instruction): User requested “haz coomit y push”. Commit and push are explicitly authorized while the differential proof remains unresolved; this does not change T10's verification status. The T10 behavior commit `84c25ce` was created.

L21 (T10 slice boundary and rollback): `84c25ce` (`feat(worktrees): add safe worktree actions`) is the T10 behavior slice: 12 files, 450 insertions, 32 deletions, with tests and user docs. Revert that commit to remove T10's configurable editor, worktree actions, and verified PR association while preserving T7-T9. Files: `README.md`; `Sources/DevControlCore/GhScanner.swift`, `GitScanner.swift`, `Models.swift`, `WorktreeActions.swift`; `Sources/DevControlLogicTests/GhScannerTests.swift`, `GitScannerTests.swift`, `WorktreeActionTests.swift`, `main.swift`; `Sources/DevMissionControl/MissionControlPanelView.swift`, `SettingsWindow.swift`; this ODD task log. Recorded functional checks are in L19; preview bundle launch succeeded. Differential proof remains missing. The branch totals 1,752 authored changed lines across seven commits since `origin/main`; use `auto-chain` if PR preparation is later requested (no PR was requested).

L22 (T10 delivery result): Commits `84c25ce` and `e9cd51a` were pushed to `origin/feat/mission-control-attention`; upstream tracking is set. T10 remains blocked because its differential proof is unresolved.

L23 (T11 implementation progress): Added tested affected-project/visible-notice counts, compact expandable cards, per-source freshness/read-time indicators, per-checkout change categories, a Settings pause toggle, and README guidance. Verified `swift run DevControlLogicTests` (293/293), `swift build`, and `git diff --check`; built and launched `build/DevMissionControl-preview-t11.app`. The panel's interactive appearance has not been visually inspected.

L24 (T11 verification blocker, resolved by L25): The preview process was running, but the session cannot inspect the menu-bar panel UI. L25 is the owner's visual inspection of that preview; it confirms the count, conflict alert, source status, worktree detail, editor config, and pause basics, and requests corrections (S16-S19).

L25 (user visual review and requested changes, verbatim):
“Sí avanzó respecto a la primera versión, pero ahora el principal problema es encontrar rápidamente lo importante entre tantos worktrees. Esto es lo que puedo evaluar visualmente; las capturas no permiten verificar la lógica interna.
Lo que quedó bien:
- Contador claro: “1 proyecto · 1 aviso”.
- Alerta concreta: dos conflictos en prop-139.
- Estado y hora de lectura por integración.
- Detalle de cambios y acciones por worktree.
- Configuración del editor y pausa por repositorio.
Lo primero que corregiría:
Observación    Ajuste recomendado
Hay 137 worktrees y la lista empieza con varios limpios    Mostrar primero los que tienen conflictos, después los que tienen cambios. Ocultar los limpios bajo “Ver los 137”.
El aviso menciona prop-139, pero debajo aparecen final-127, final-128…    Hacer clic en el aviso debe abrir y enfocar directamente prop-139.
La tarjeta expandida ocupa prácticamente toda la ventana    Mantener el resumen compacto y abrir el detalle del repositorio en una ventana aparte.
Ajustes muestra “Paused” con interruptores apagados    Usar “Pausar proyecto” como etiqueta del control y mostrar “Activo/Pausado” como estado independiente.
La interfaz mezcla español e inglés    Unificarla en español, conservando términos técnicos habituales como worktree, staged y diff.
“Open in Editor” está deshabilitado sin explicación en ese menú    Mostrar “Configurar editor…” cuando todavía no haya uno seleccionado.
También revisaría dos comportamientos importantes:
- Los otros cuatro proyectos deben poder consultarse. La captura solo muestra “Necesita atención”; añade acceso visible a Todos, aunque estén limpios o pausados.
- “Engram current” necesita una definición precisa. Una consulta reciente no garantiza que la memoria esté actualizada respecto al código. Mejor mostrar por separado “Conectado · consultado hace…” y “Último resumen guardado…” cuando exista ese dato.
El texto “last commit 3 days ago” puede mantenerse como información, pero no representa la última modificación local ni actividad del agente.
Mi siguiente entrega sería pequeña: ordenar y filtrar worktrees, convertir cada aviso en acceso directo al problema y corregir la pausa. Con 137 worktrees, esos cambios te darán más utilidad inmediata que añadir nuevas integraciones.
Además, en el prompt anterior quedó una frase ambigua: “Evitar escaneos superpuestos y bloquear la interfaz”. Debe decir “Evitar escaneos superpuestos y mantener la interfaz responsive durante el escaneo”.”

L26 (T12-T15 scope decision): Asked which scope to implement next, the user selected “Incluir todas las correcciones”: the small priority slice (worktree ordering/filtering, alert-to-focus navigation, pause control) plus full Spanish UI, Engram connection vs saved-summary separation, the “Configurar editor…” CTA, and the S12 responsive-scanning wording. Specs S16-S19 and tasks T12-T15 record this delivery. Installed Engram 3.4.0 evidence: `GET /sessions/recent?project=dev-mission-control&limit=5` returned records with only `id`, `observation_count`, `project`, `started_at` (no `summary` locally), while `GET /observations?project=…&limit=100` entries expose `type` and include `session_summary` entries (latest `2026-10-17 04:37:49`); the saved-summary timestamp is therefore read from the observations endpoint with a bounded page, filtering `type == "session_summary"`.

L27 (T12-T15 implementation and verification): Worktree ordering shipped as `WorktreeOrdering` (conflicts → changes → clean, deterministic tiebreaks) with tests-first RED/GREEN; the Engram scanner now reads a bounded observations page (`limit=100`) and exposes `ActivityStatus.summary` (`SessionSummaryInfo`) with stale retention; the UI adds compact cards with notice shortcuts, the Atención/Todos selector, per-project detail windows with focus highlight, “Pausar proyecto” plus Activo/Pausado status, and the “Configurar editor…” CTA; all visible panel, settings, attention-message, and action-error text is Spanish with worktree/staged/untracked/diff/PR kept as technical terms. `@State` remains unavailable in this CLT environment (SwiftUIMacros.StateMacro), so panel/detail local state uses `@StateObject` holders. Verified `swift run DevControlLogicTests` (302/302), `swift build`, and `git diff --check`; README rewritten for the new behaviors; preview bundle rebuilt and relaunched for owner inspection.

L28 (correction delivery slices): `a542b28` (`feat(attention): spanish findings, triage ordering, engram summary`, 231 lines) is the core slice — AttentionMath Spanish messages with updated test expectations, `WorktreeOrdering` plus its tests, and the Engram summary signal with retention; reverting it restores English findings and removes triage ordering and saved-summary data without touching T7-T10. `4133b9e` (`feat(ui): spanish triage panel with focused detail windows`, 694 lines) is the UI slice — compact cards, Atención/Todos selector, repository detail windows with focus, pause control, editor CTA, Spanish settings, and the `--scan-once` label changes; reverting it restores the previous panel while keeping the core slice. `235d449` is the README slice. The branch totals about 2,740 authored changed lines across 11 commits since `origin/main`; per the recorded strategy use `auto-chain` when PR preparation is requested (still not requested). Push remains a user decision.

L29 (native review lifecycle): The full-branch candidate was terminal (`lens_context_budget_exceeded`, no authority created), so the review was reduced to the committed range `e9cd51a..HEAD`. Authority `review-28c8a7d1072923e8`: medium risk, lenses resilience/readability/reliability, 1,155 changed lines, correction budget 200. Three reviewers and the refuter ran; the review reached `correction_required` with four candidate-caused critical findings collapsing into two real defects: detail-window reuse dropped the notice focus (R2-001, R3-DETAIL-WINDOW-FOCUS, R4-detail-refocus) and `--scan-once` labels changed outside the requested Spanish scope (R3-SCAN-ONCE-OUTPUT). A 100-line correction plan was registered; the correction is committed as `7b75cbb` (`fix(review): forward detail focus on reuse and restore scan-once labels`, 71 diff lines) with 302/302 checks, `swift build`, and `git diff --check` passing. The required targeted-validator capture was rejected three times (`capture-route-registration-rejected`: object without `validationRequest`, exact serialized string, and full object with multi-line proofs); no verdict was produced and nothing was burned. The lineage stays in `correction_required` pending a human decision: retry the validator capture through the native CLI, inspect the authority, or disable review for this clone.

L30 (native review approved): A fresh authority `review-d4ac46f7b610642e` (medium risk, same three lenses, 1,172 changed lines over the same reduced range including the correction) reviewed the corrected candidate. Three reviewers and the refuter closed with state `approved`; `acknowledge-approved` burned the authority (consumed revision `34c73402`). All listed findings are advisory and non-blocking (one CRITICAL was explicitly refuted): unused `WorktreeOrdering.cleanWorktrees`, no re-scroll when the same notice is re-clicked, Engram summary epoch fallback on unparseable dates, and the `limit=100` activity window. They are recorded as separate later work, never a reason to re-run review on this candidate. Delivery follows ordinary repository policy; push and PR remain the user's decisions. The old lineage `review-28c8a7d1072923e8` is superseded in practice but its stale authority still needs an owner disposition.

L31 (second visual feedback, verbatim): “detalles que miro solo dice git actual, engram conectado, pero no da mas informacion relevante, elegir editor me abre el finder no la opcion apra seleccionar las app que tengo,” y “y el idioma deberia ser automatico de acuerdo al del sistema”. Corrections implemented: every source badge now shows the read time inline, GitHub shows its open-PR count, and Engram shows its latest activity date plus saved summary (previously tooltip-only or lost with the old clean rows); the editor picker opens anchored at `/Applications` accepting only application bundles; and the interface language follows the system via `AppLanguage` (S16 amended). Verified 307/307 logic checks (Spanish pinned, English messages asserted), `swift build`, and `git diff --check`; preview rebuilt and relaunched for re-inspection.

L32 (language-feedback slices): `1ed6989` (`feat(attention): localize findings to the system language`, 132 lines) is the core slice — `AppLanguage` plus localized AttentionMath messages with bilingual test coverage. `481f48c` (`feat(ui): system-language interface with informative source badges`, 192 lines) is the UI slice — `L10n` strings across panel, detail window, settings, context menu, and `--scan-once`, inline badge data (read time, open-PR count, Engram activity and summary), and the `/Applications` editor picker. `5ca99a1` is the docs slice (README language section and L30-L31). The branch totals about 3,034 authored changed lines across 17 commits since `origin/main`; the recorded `auto-chain` strategy applies when PR preparation is requested. Push remains a user decision.

L33 (native review of the language delta): Authority `review-03ac215e69e1c9c4` (medium, same three lenses, 484 changed lines over the delta `c2a3793..HEAD`, so already-approved work was not re-reviewed). The first group run failed on a pi-host-relay transport failure (no model run, nothing mutated); fresh STATUS reoffered the slots and single-slot captures succeeded for all three reviewers. The refuter closed `correction_required` with three criticals describing one real defect introduced by this slice: the `--scan-once` labels passed `L10n.t` arguments inverted (English first), swapping es/en output. A 8-line correction plan was registered and committed as `f0a05a7`; the targeted validator approved the corrected candidate, `acknowledge-approved` burned the authority (consumed revision `8dd6f163`), and remaining findings are advisory only (badge/settings string suggestions and the locale-dependent CLI output warning). Delivery follows ordinary repository policy; push and PR remain the user's decisions.

L34 (docs-delta review closure): The only unreviewed mutation after L33 was `fe71458` (two added ODD log lines). The native review `review-72a3c639394c948f` started as low risk, non-executable-only, with no lenses (a lens selection requires medium/high risk, so the first attempt with lenses was rejected and the corrected request omitted them); the lifecycle closed `approved` immediately with no reviewers and no acknowledgement step. Committed together with L35 in this slice.

L35 (third visual feedback, verbatim): “porque aparecen dos git y github, engram hay alguna forma de mostrar algun dato mas o abrir las memorias?, y otra cosa que no me gusto el orden de lo nuevo que garegaste se ve muy achocado, si hay pr sale el link para abrirlo en el navegador? las diff como se muestran si muestra lo rojo y lo verde, lo que se agrega y lo que se quite,”. Corrections implemented (S20): freshness rows are now one airy row per source with the read time and inline data (GitHub open-PR count; Engram activity date, title, and saved summary); an “Abrir memorias” action opens `engram tui` in Terminal via osascript with separate arguments and an error alert (the installed local server has no web dashboard — `/dashboard/` and `/dashboard/projects` return 404, verified against the running Engram 3.4.0); the repository detail window lists open PRs with an Open button using only the HTTPS URL returned by `gh`; diffs render with a tests-first `DiffParser` (additions green, removals red, hunk headers accent, metadata dimmed). Verified 319/319 logic checks, `swift build`, and `git diff --check`; preview rebuilt and relaunched for re-inspection.

L36 (round-3 review escalated): Native review `review-d68bd4740987dd61` (medium, three lenses, 348 lines over `fe71458..HEAD`) ran its three reviewers successfully, but the refuter closed the lifecycle in state `escalated` (`unknown_causality`; `native_stop_required`): finding R3-001 is severe with undetermined causality — the refuter's probe was unavailable on pi — and R4-001 was corroborated with proof at `DiffParser.swift:42`, `DiffParser.swift:50-51`, and `MissionControlPanelView.swift:757` (the meta/±-prefix classification and the diff sheet's offset-identified `ForEach` inside a `LazyVStack`). Nothing was burned and no correction was demanded; the authority stops for maintainer action. Self-inspection notes for the decision: offset-based identity in a lazy stack is the plausible concern, addressable with stable per-line identities if the maintainer wants a follow-up fix.

L37 (maintainer decision and fix): Asked to choose among accepting the risk, applying the fix and re-reviewing, inspecting the authority, or disabling review, the user selected option 2. The fix is committed as `3656473` (`fix(diff): give diff lines stable identities for lazy rendering`): `DiffLine` is `Identifiable` with a sequential identity assigned at parse time, and the diff sheet renders `ForEach` over the lines directly instead of enumerating offsets inside the `LazyVStack`; tests pin sequential and reproducible identities. Verified 321/321 logic checks, `swift build`, and `git diff --check`. A fresh native review over `fe71458..HEAD` follows to close the delta.

L38 (re-review approved after bounded correction): The fresh authority `review-6119a3ec826eae56` (medium, three lenses, 365 lines) ran its reviewers, and the refuter closed `correction_required` with four criticals: `+++`/`---` prefixes were classified before the sign checks so hunk lines whose content starts with extra signs were dimmed (R3-001, R4-001); the identity fix was still positional (R3-002); and the PR list was hidden when `gh` failed, discarding retained data (R3-003). A 60-line correction plan was registered; the correction commit `5de9243` makes classification hunk-aware, assigns deterministic content identities (FNV-1a plus occurrence), and keeps retained stale PR data visible with a stale marker inside the in-scope view file (the first attempt touched `Models.swift` outside the frozen scope, so the native side offered a `scope_changed` recovery; the correction was amended to stay in scope instead of taking the recovery route). The targeted validator approved the corrected candidate; `acknowledge-approved` burned the authority (consumed revision `89354e54`). Verified 324/324 logic checks, `swift build`, and `git diff --check`; preview rebuilt. Remaining findings are advisory (L38 list: DiffParser prefix warning, panel row/freshness styling suggestions, detail-view PR section note, and the osascript memories-action warning) and are recorded as later work, never a reason to re-run review on this candidate.

L39 (T10 differential proof, user-authorized bounded check): With the user explicitly authorizing the pending verification, the base (35dea99, pre-T10) was built in a temporary worktree and both binaries ran `--scan-once` against the same deterministic fixture repository with an isolated config whose `editorApplicationPath` exercises the key T10 introduced (English locale forced via LANG/LC_ALL/AppleLanguages). Result: `DIFFERENTIAL: IDENTICAL OUTPUT`, exit codes 0 and 0; stdout matched byte-for-byte including the `engram: unavailable (Engram returned HTTP 404)` line, which both binaries report identically. Artifacts left at `/tmp/dmc-t10diff.oWlKuY` (base.out, cand.out, diff.txt, base-build.log); the temporary worktree was removed and pruned. T10's verification gap is closed.
