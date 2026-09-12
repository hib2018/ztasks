# Data Model: Agent Task Execution Control

## Authority boundaries

| Data | Authority | Derived from |
|------|-----------|--------------|
| Task Definition | Bound Spec Kit `tasks.md` | Source adapter |
| Accepted Definition artifact | `.ztasks/sources/<digest>/definition.json` | Validated normalized batch |
| Dependency extraction artifact | `.ztasks/sources/<digest>/dependencies.json` | Explicit source declarations |
| Runtime history | `.ztasks/events.jsonl` | Accepted commands |
| Current Runtime | Reducer projection | Definitions + Events |
| Runtime snapshot | Disposable cache | Current Runtime |
| TUI view state | Frontend preference | Human navigation |
| Session record | Adapter metadata | Agent integration |

## TaskSourceBinding

Fields: `kind` (MVP: `speckit`), project-relative regular-file `locator`,
`source_version`, complete `content_digest`, and Core-assigned `synced_at`.
The path cannot escape the Project. A failed candidate leaves the current binding unchanged.

An accepted normalized batch is stored once under its complete content digest before the Event
that references it. Existing digest artifacts are verified and reused. An unreferenced artifact
left by interruption is inert and may be diagnosed; MVP does not delete it automatically.

## DependencyExtractionArtifact

Fields: schema `version`, extraction `contract_version`, project-relative source `locator`, SHA-256
of the exact raw `tasks.md` bytes, ordered `edges`, and ordered `diagnostics`. Each edge contains a
`task_id`, ordered `depends_on` IDs, and one-based line/column evidence for the terminal dependency
clause. Evidence contains no copied title/prose. Diagnostics identify malformed, ambiguous, or
absent dependency declarations without inventing an edge.

The Core writes compact UTF-8 JSON with fixed schema field order, no insignificant whitespace, and
one trailing LF. Tasks and diagnostics follow document/source-span order; dependency IDs retain
declaration order. The artifact is valid only for an exact source digest and contract version. It
is a disposable projection, never a writable Definition input.

## DefinitionBatch

An atomic normalized result containing one binding candidate, ordered Phases, ordered
TaskDefinitions, and safe diagnostics. Duplicate IDs, missing/self dependencies, cycles, invalid
UTF-8, or invalid required text reject the entire batch.

## PhaseDefinition

Fields: stable batch-local `id`, non-empty `title`, unique contiguous `order`, and
`source` span pointing to its heading.

## TaskDefinition

| Field | Rules |
|------|-------|
| id | `T` plus digits; unique in batch |
| title | Non-empty valid UTF-8; at most 200 Unicode scalar values; no unsafe controls |
| phase_id | References a Phase |
| order | Unique document order |
| dependencies | Existing ordered ID set extracted only from an exact terminal dependency clause; no duplicate/self/cycle |
| parallel_hint | Scheduling hint only |
| story | Optional source label such as `US1` |
| source | Project-relative path and one-based line/column |
| source_checked | Metadata only; never sets Runtime |
| metadata | Extensible scalar values |

## TaskRuntime

Fields: `task_id`, `definition_state` (`current|missing`), Runtime `status`, optional
`agent` and `session_id`, `attempt`, start/update times, `current_action`,
`blocked_reason`, `last_error`, ordered pending interventions, derived unsatisfied dependency
IDs, and `last_event_seq`.

No lifecycle Event yields `ready` when all dependencies are completed/skipped; otherwise
`pending`. A missing definition retains its last status but is unschedulable.

## Runtime transitions

| Event | From | To | Rule |
|------|------|----|------|
| task.started | ready | running | First attempt becomes 1 |
| task.started | failed | running | Correlated pending retry required |
| task.progress | running | running | Update current action |
| task.paused | running | paused | May resolve pause request |
| task.resumed | paused, blocked | running | May resolve resume request |
| task.blocked | ready, running, paused | blocked | Reason required |
| task.failed | running, paused, blocked | failed | Error/reason required |
| task.completed | running | completed | Terminal |
| task.skipped | any nonterminal or failed | skipped | Terminal |
| task.comment | any known lifecycle | unchanged | No lifecycle mutation |

Completed/skipped Tasks accept comments only. Dependency completion/skip recalculates downstream
availability during the same reduction without a synthetic Event.

## Event

Fields: schema `version`, unique `event_id`, contiguous `seq`, unique `request_id`,
Core-assigned UTC `timestamp`, `actor`, `type`, optional `task_id`/`session_id`/
`correlation_id`, and a bounded typed `payload`.

Actor/session identifiers are at most 128 UTF-8 bytes. Comment, progress/current action,
blocked reason, and error text are at most 4,096 UTF-8 bytes each; source locators are at most
4,096 UTF-8 bytes; the canonical serialized Event is at most 65,536 UTF-8 bytes. Limits are
checked on raw normalized public input before credential sanitization and again on sanitized Event
fields; prohibited field names and unsafe controls are rejected before persistence.

Execution types: `task.started`, `task.progress`, `task.paused`, `task.resumed`,
`task.blocked`, `task.failed`, `task.completed`, `task.skipped`, `task.comment`.

Human types: `human.pause_requested`, `human.resume_requested`, `human.retry_requested`,
`human.stop_requested`, `human.skip_requested`, `human.inspect_requested`, `human.comment`.

`intervention.responded` records `acknowledged|rejected|unsupported|completed`.
Identical request retries return the prior Event; conflicting reuse is rejected.

System types: `project.initialized` establishes the Project Runtime and initial source binding;
`source.synced` records one accepted source revision, prior/new digests, exact change sets, and a
content-addressed reference to the accepted normalized Definition batch plus its dependency
extraction artifact digest. The referenced immutable artifacts are persisted before the Event and
are required for audit/reconstruction; neither replaces the Event as the fact that a sync was
accepted.

Each Event uses a type-specific closed payload schema. It cannot contain designated private
reasoning, raw transcript, raw stdout/stderr, authorization, or credential fields. Permitted text
stores only its sanitized value plus optional redaction field/class metadata; original values
matched by a redaction rule are not retained. Callers remain responsible for excluding unknown
secret forms from otherwise permitted free text.

## InterventionRequest

Fields: request Event ID, action, state (`pending|acknowledged|rejected|unsupported|resolved`),
request time, optional response Event ID, and optional lifecycle resolution Event ID.

Allowed creation: pause on running; resume on paused/blocked; retry on failed; stop on
running/paused/blocked; skip on any nonterminal; inspect/comment on any known Task, including
definition-missing. Conflicting unresolved controls are rejected.

## RuntimeSnapshot

Contains schema/compatibility metadata, source locator/digest, last Event sequence, log-prefix
identity, current and last-known Definitions, and Runtime projections. It is valid only when its
sequence and prefix identity match Event history; otherwise replay replaces it.

## Sync projection

- Added ID: derive pending/ready.
- Retained ID: preserve lifecycle, update Definition, recalculate nonterminal availability.
- Removed ID: retain history/last Definition and mark `definition_state=missing`.
- Reappearing ID: attach existing Runtime and report Definition differences.

Sync never writes `tasks.md` or converts checkbox state into Runtime status.
