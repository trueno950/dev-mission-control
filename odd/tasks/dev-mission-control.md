# Feature: dev-mission-control

Native macOS menu bar app that answers "where was I and what needs attention?" across all local projects in one click.

## Specs

S1: "un segundo widget con la misma base: un 'Mission Control' de desarrollo en la barra de menú que responda en un click: PRs abiertos esperando, CI rojo, ramas sin fusionar, worktrees viejos para limpiar, y la última sesión de Engram por proyecto" — a menu bar item opening a status panel listing tracked projects and their attention items.

S2: Data sources per project, read-only and official only: local `git` (current branch, dirty file count, unpushed commit count, worktree list), `gh` CLI (open PRs with CI check status), Engram HTTP API (`GET /observations?project=<name>&limit=1` for last activity; server `http://127.0.0.1:7437`). No scraping, no mutations of user repos.

S3: Attention classification (pure logic, threshold-driven): uncommitted local changes are informational and do not create an attention finding; verified conflicts and failing checks require attention; unpushed commits remain an evidence-based finding; PR age and clean-worktree age are informational and do not establish urgency. Only current source reads may establish findings; stale or unavailable data is surfaced as no information, not as a clean result or attention alert. Agent inactivity is sourced only from Engram, never inferred from Git or file timestamps. Explicitly paused projects receive neither Engram inactivity nor idle-clean-worktree notices. This supersedes the previous dirty-worktree warning and age-only PR warning rules. Existing thresholds remain configurable for any informational age display.

S4: Configuration persisted as JSON in Application Support (`~/Library/Application Support/DevMissionControl/config.json`): repo list (absolute path; GitHub slug and Engram project name optional, derived when absent), refresh interval (default 5 min), thresholds, and optional per-repository `isPaused` defaulting to false. The settings window can pause or resume a project; paused projects receive no inactivity findings. Existing configuration remains backward-compatible.

S5: Graceful degradation: without `gh` (missing or unauthenticated) do not fabricate an empty PR result; without the Engram server do not fabricate activity; a missing/invalid repo path is an unavailable Git source instead of a crash, not a clean result or an attention alert. Each source reports its identity, last read time, availability, and freshness. If a refresh fails after a successful read, retain the last valid result marked stale and separately show the current source failure. Findings use only current reads, while independent current sources remain classifiable. Git remains queryable if GitHub or Engram fails.

S6: Manual refresh (button) plus automatic refresh every configured interval; scanning runs off the main thread; the panel never blocks. A refresh cannot overlap another refresh. External calls have bounded timeouts, and periodic scanning does not invoke a model.

S7: Native macOS design matching ai-subs-menubar: vibrancy/transparency materials, rounded cards, SF Symbols, borderless panel under the status item (Control Center look). Repository cards are compact and expandable; the primary checkout branch is distinct from linked-worktree branches; staged, unstaged, and untracked changes are separated; header counts distinguish affected projects from visible notices and identify source freshness.

S8: Personal, unsigned app; must build with Command Line Tools only (no full Xcode). The app performs read-only repository queries and read-only HTTP GETs to Engram; stores no credentials (gh keyring and git are external). Actions may open a selected worktree, show its diff, and open only a PR whose branch association is verified. No commit, push, merge, or worktree deletion is automated. Spawned processes use executable paths and separate arguments; repository paths are never concatenated into shell commands.

S9: The user requested these exact status rules: “En curso: cambios locales recientes; no son una alerta por sí solos.” The user then revised the wording and policy: “También cambiaría en el prompt ‘cambios locales recientes’ por ‘cambios locales pendientes’ para eliminar la ambigüedad. sin umbral”. Therefore any currently pending staged, unstaged, or untracked Git changes are informational, with no age cutoff or alert by themselves; this describes repository state, not agent activity. Attention requires explicit evidence such as an unmerged conflict or failing CI. A project explicitly marked paused has no inactivity alert.

S10: The requested compact card includes the repository name, primary checkout branch, number of worktrees, primary reason, expandable per-worktree branch/path, separate staged/unstaged/untracked counts, distinct affected-project and notice counts, and last-read time plus source. The primary checkout branch must not be confused with linked-worktree branches.

S11: The requested actions open the selected worktree in an editor, terminal, or folder; display its diff; and open a PR only when the worktree branch-to-PR association is verified. No commit, push, merge, or worktree deletion is automatic. Actions must target the selected worktree even when its path contains spaces.

S12: The requested robustness rules separate connectors, normalized data, attention rules, and UI; prevent overlapping scans and UI blocking; bound external operations; preserve last valid data as stale after a refresh error; keep local Git available when another integration fails; avoid model calls in periodic scans; and pass process arguments separately without putting paths into shell command strings. A GitHub error is not an empty PR list.

S13: Acceptance cases quoted from the user: “Un worktree con cambios recientes no aparece como urgente”; “Un conflicto sí requiere atención”; “Un fallo de GitHub no equivale a ‘sin PR’”; “Sin información: integración ausente, error o datos desactualizados.”; “Cada acción abre el worktree correcto, incluso con espacios en la ruta”; “Los contadores coinciden con los avisos visibles”; “Los datos antiguos están identificados.” The first case follows the user's amended no-cutoff wording in S9.

S14: The next delivery is explicitly “Retomar proyecto”: “recuperar desde Engram el último objetivo, avances, pendientes y archivos relevantes, mostrando fuente y fecha; contrastarlo con Git actual y permitir copiar contexto para IA. Utiliza interfaces soportadas y no escribas directamente en la base de Engram.” This is recorded as the next feature, not part of this first delivery.

S15: Additional product guidance includes the exact distinction “2 proyectos · 5 avisos” and the rule “La antigüedad por sí sola no determina urgencia.” First-delivery implementation remains bounded to S9-S13; later P1/P2 features in the user feedback remain deferred.

## Tasks

T1 [S1,S7,S8] Scaffold: Package.swift, build-app.sh + Info.plist bundle script, status item with borderless panel skeleton, empty default config. Verify: `swift build` passes and the app launches showing an empty panel.
T2 [S3,S4] Core models, JSON config store, attention classification and staleness math — tests first.
T3 [S2,S5] Git scanner: porcelain parsers for status/worktree list/branch/upstream count with injected-output tests; process runner wiring.
T4 [S2,S5] GitHub scanner: origin-URL slug parsing + `gh pr list --json` parsing (open PR age, failing CI) with injected-output tests; graceful absence.
T5 [S2,S5,S6] Engram scanner (HTTP GET, per-project last activity) with response-parsing tests; aggregate scan pipeline and background refresh loop in AppState.
T6 [S1,S7,S4] Full panel UI (per-project cards, attention rows, clean state, config-error rows), settings window with folder picker, README, final functional verification (build, launch, manual smoke on real repos).
T7 [S9,S13] Normalize Git status per checkout/worktree (staged, unstaged, untracked, conflicts) with parser tests — worker, done; commit: 8024cbe.
T8 [S9,S13] Implement evidence-based attention classification and backward-compatible paused-project config; test pause suppression and non-urgent pending changes; document evidence rules — inline, done; commit: 90285b7.
T9 [S3,S5,S6,S12,S13] Add source timestamps/freshness, bounded non-overlapping scans, and last-good stale retention without losing Git when remote sources fail; classify stale/unavailable reads as no information; document the source states — worker plus parent review, in progress; split into source freshness, attention classification, and subprocess-timeout commit slices; source slice: `d0ae1ea`; classification and timeout slices pending.
T10 [S11,S12,S13] Implement argument-safe worktree actions and verified worktree-to-PR mapping; test paths containing spaces and keep all operations read-only — inline; commit: pending.
T11 [S10,S12,S13] Implement compact expandable repository cards, accurate project/notice counts, per-source freshness, pause controls, README updates, and end-to-end acceptance checks — inline; commit: pending.

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
