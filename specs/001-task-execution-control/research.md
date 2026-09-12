# Phase 0 Research: Agent Task Execution Control

## Task source binding

**Decision**: Bind each Project Runtime to exactly one `tasks.md`. Resolve an explicit path first,
then the active feature in `.specify/feature.json`, then a sole matching `specs/*/tasks.md`.

**Rationale**: Spec Kit feature documents commonly restart IDs at `T001`; merging documents creates
ordinary collisions and ambiguous Phase order.

**Alternatives considered**: Merge all Task files; require a path every time; use a feature-plus-ID
key. Multi-feature identity is deferred beyond MVP.

## Normalized source adapter

**Decision**: A Task Source returns one atomic batch with source identity/digest, ordered Phases,
normalized Tasks, and diagnostics. The Markdown adapter recognizes checkbox Task rows with
`T[0-9]+`, optional `[P]`, optional story label, a non-empty description, and the nearest Phase
heading. A single exact description suffix such as `(depends on T001, T002)` is the only MVP
dependency declaration. The adapter emits a deterministic `dependencies.json` beside the accepted
normalized batch under the source digest. Checkbox state is metadata only.

**Rationale**: The reducer must not know Markdown syntax or infer unsafe readiness from prose,
numeric order, Phase order, file overlap, or a parallel marker.

**Alternatives considered**: Change Spec Kit Task-row labels; expose a Markdown AST; infer Phase
barriers; parse broad prose or a narrative `Dependencies` section; support multiple equivalent
spellings; partially accept malformed input.

## Dependency extraction artifact

**Decision**: Define `contracts/dependency-extraction.md`. Parse only a case-sensitive terminal
clause `(depends on T001, T002)` in a recognized Task description. Task number, Phase order,
`[P]`, file overlap, headings, dependency graphs, and narrative sections create no edges. Emit
canonical JSON containing contract version, raw-source SHA-256, source locator, ordered edges,
line/column evidence, and deterministic diagnostics. The JSON is never edited, is ignored when its
source digest differs, and is safe to delete and regenerate.

**Rationale**: The standard Spec Kit checklist row remains unchanged. Dependency evidence stays
traceable to the canonical `tasks.md`, while the machine-readable representation is reusable by
the reducer without becoming a second source of truth.

**Alternatives considered**: Extend the Spec Kit row-label format with `[depends:...]`; write a
machine block back into `tasks.md`; accept a human-edited sidecar; infer narrative dependency
sections; omit dependency monitoring. These respectively fork upstream format, violate read-only
ingestion, duplicate authority, create ambiguous edges, or weaken readiness monitoring.

## Runtime semantics

**Decision**: Derive `pending` and `ready` from explicit dependencies. Only `completed` and
`skipped` satisfy dependencies. All other lifecycle states are Event-derived. Terminal Tasks
remain terminal; successful sync recalculates nonterminal availability.

**Rationale**: Availability is deterministic under replay without noisy synthetic Events.

**Alternatives considered**: Persist ready Events; infer Phase dependencies; reopen terminal Tasks
implicitly. Reopen/reset requires a future explicit Event.

## Human intervention

**Decision**: A `human.*_requested` Event creates a pending intervention but never changes
lifecycle. Correlated Agent Events confirm execution effects. `intervention.responded` records
acknowledged, rejected, unsupported, or completed responses where needed.

**Rationale**: The UI truthfully distinguishes “requested” from “actually paused/stopped”.

**Alternatives considered**: Change status immediately; use Agent-specific acknowledgements; omit
inspect/comment from history.

## Missing definitions

**Decision**: Retain Events and the last-known definition for a removed ID, mark the orthogonal
`definition_state` as `missing`, and exclude it from scheduling. Allow inspection/comments but
reject new execution transitions. Reattach Runtime if the same ID returns.

**Rationale**: Audit history survives without inventing a ninth lifecycle status.

**Alternatives considered**: Delete Runtime; add `orphaned` status; execute against stale definitions.

## Event store and commit point

**Decision**: Use one compact UTF-8 JSON object per line in `.ztasks/events.jsonl`. Under an
exclusive project lock, replay and validate, persist and sync any referenced content-addressed
Definition batch, allocate contiguous `seq`, append one bounded line, and sync the Event file.
Successful Event sync is the commit point. Snapshot publication follows. An unreferenced batch
artifact after interruption has no semantic effect.

**Rationale**: Event-first ordering recovers after a crash between authority and cache. Locking
coordinates sequence allocation and avoids platform-specific append assumptions.

**Alternatives considered**: `O_APPEND` alone; one file per Event; SQLite; mutable state only.

## Snapshot and replay recovery

**Decision**: Write `state.json` through same-directory atomic replacement with schema,
`last_event_seq`, and log-prefix identity. Strict replay requires valid UTF-8, supported version,
contiguous sequence, unique identities, and valid transitions. Only an unterminated final fragment
may be automatically truncated while locked; interior corruption stops replay.

**Rationale**: The cache can disappear safely, while skipping committed history would fabricate
state.

**Alternatives considered**: In-place writes; trust mtime; skip malformed records; trust snapshot
when history is corrupt.

## Idempotency and concurrency

**Decision**: Persist a client-generated `request_id` on every mutation. An identical retry returns
the original result; different semantics fail as `idempotency_conflict`. Serialize writers with
a stable `.ztasks/lock`; initially use exclusive locking for consistent reads too.

**Rationale**: A request may commit and lose its response. Persistent identity prevents duplicate
Events after restart.

**Alternatives considered**: Content/time deduplication; memory-only caches; PID files; only an
in-process mutex.

## Frontend and process lifecycle

**Decision**: Use Go standard process/JSON packages and Bubble Tea v2. Start one
`ztasks-core serve --project-root <absolute-path>` for a TUI session; CLI commands use the same
handler for one request. stdout is protocol-only, stderr diagnostic-only, and Go never predicts
domain transitions.

**Rationale**: A long-lived child avoids refresh startup cost, direct argv avoids shell injection,
and a unidirectional UI maps naturally to request/result flow.

**Alternatives considered**: Hand-written terminal control; process per refresh; daemon/socket; FFI;
an additional CLI framework before justified.

## Protocol and compatibility

**Decision**: Each physical line is one UTF-8 JSON object with a 1 MiB limit. Requests carry
`version`, `request_id`, and `op`; responses echo identity. Perform a compatibility handshake
at TUI startup and retry ambiguous mutations with the same request ID.

**Rationale**: Bounded JSON Lines is transparent and language-neutral; correlation and idempotency
resolve response-loss ambiguity.

**Alternatives considered**: Length prefixes; unbounded scanners; protobuf/gRPC; exit-code inference.

## Operation to Event mapping

**Decision**: Every successful mutation operation maps to exactly one committed Event type as
specified in `contracts/event-mapping.md`; query and validation operations append none. The Core
owns this mapping. `project.init` emits `project.initialized`, `source.sync` emits
`source.synced`, Task acknowledgement operations emit their corresponding `task.*` facts, human
commands emit `human.*_requested` (or `human.comment`), and Adapter response reporting emits
`intervention.responded`. `event.emit` is transport sugar restricted to the same allowlisted
operation/Event pairs, not a generic Event injection escape hatch.

**Rationale**: Exact causality makes audit logs predictable and prevents Go or an Adapter from
selecting a convenient Event that bypasses transition validation. One mutation/one Event also
simplifies idempotent retry and response-loss recovery.

**Alternatives considered**: Let callers submit arbitrary Event types; derive Event names from
operation strings; emit multiple Events per command; make initialization or sync silent.

## Redaction and safe observability

**Decision**: Apply three controls before sequence allocation or persistence, detailed in
`contracts/redaction.md`: (1) accept only typed, event-specific payload fields and reject unknown
or explicitly forbidden fields; (2) reject private-reasoning, transcript, raw stdout/stderr,
credential-container, and authorization-header fields; (3) sanitize permitted free text for
unsafe controls and recognized credential forms, replacing detected secrets with typed
`[REDACTED:<class>]` markers and recording only field/class redaction metadata. Original secret
bytes matched by these rules never enter Events, snapshots, protocol errors, diagnostics, or logs.
Raw normalized input limits are checked before sanitization and Event limits afterward. Adapters
and callers submit short, secret-free observable action/result summaries rather than hidden
reasoning or raw process output; arbitrary free text is not claimed to be perfectly classifiable.

**Rationale**: Schema allowlisting structurally prevents prohibited data classes, while
pre-persistence sanitization handles recognized secrets inside legitimate text. Redaction after
append is incompatible with append-only history. Explicit caller responsibility keeps the
remaining semantic limit honest and testable.

**Alternatives considered**: Store then scrub; rely solely on callers; encrypt unrestricted raw
transcripts; heuristic-only redaction; reject all free text. These respectively violate durable
exclusion, weaken the trust boundary, expand key-management scope, remain structurally unsafe, or
remove essential human context.

## Testing and packaging

**Decision**: Combine pure Core tests, shared golden fixtures, Go fake-client tests, fake process
failure tests, race/TUI tests, and real two-binary E2E tests. Ship platform archives containing
`bin/ztasks` and `libexec/ztasks/ztasks-core`, with matching product/protocol versions.

**Rationale**: Each layer localizes failures while real binaries prove protocol and discovery.
Bundled archives require no user toolchain and preserve the process boundary.

**Alternatives considered**: Only E2E; only mocks; terminal snapshots alone; both binaries in PATH;
runtime extraction; FFI; `go install` as complete installation.

## References

- Zig 0.16 release notes: https://ziglang.org/download/0.16.0/release-notes.html
- Go `os/exec`: https://pkg.go.dev/os/exec
- Go `encoding/json`: https://pkg.go.dev/encoding/json
- Bubble Tea: https://github.com/charmbracelet/bubbletea
- Linux `fsync(2)`: https://man7.org/linux/man-pages/man2/fsync.2.html
- Linux `open(2)`: https://man7.org/linux/man-pages/man2/open.2.html
- Linux `flock(2)`: https://man7.org/linux/man-pages/man2/flock.2.html
