# JSON Lines Protocol v1

## Transport

`ztasks-core serve --project-root <absolute-path>` reads one UTF-8 JSON object per stdin line and
writes one response object per stdout line. stderr is diagnostic-only. Maximum line size is 1 MiB.

## Envelopes

```json
{"version":1,"request_id":"01K5EXAMPLE","op":"task.start","actor":{"kind":"agent","id":"pi"},"task_id":"T023","payload":{"session_id":"pi-42"}}
```

```json
{"version":1,"request_id":"01K5EXAMPLE","ok":true,"result":{"event":{"event_id":"01K5EVENT","seq":42,"type":"task.started","task_id":"T023"},"runtime":{"task_id":"T023","status":"running","attempt":1}},"warnings":[]}
```

```json
{"version":1,"request_id":"01K5EXAMPLE","ok":false,"error":{"code":"dependency_unsatisfied","message":"task T023 is not ready","details":{"unsatisfied_dependencies":["T019"]}}}
```

`version`, `request_id`, `op`, and `actor` are required requests fields. Unknown envelope
fields are rejected. Mutation responses return the single committed Event and resulting
projection. Payloads are closed per operation; unknown or prohibited payload fields are rejected.

## Operations

Queries: `version.get`, `project.inspect`, `task.list`, `task.show`, `event.list`,
`source.validate`, `health.check`.

Mutations: `project.init`, `source.sync`, `task.start`, `task.progress`,
`task.pause_ack`, `task.resume_ack`, `task.block`, `task.fail`, `task.complete`,
`task.skip`, `task.comment`, all `human.*_request` operations, `human.comment`, and
`intervention.respond`.

The normative mapping, allowed caller, required payload, and resulting Event for every operation
is [event-mapping.md](event-mapping.md). `event.emit` in the CLI selects one of those operations;
the wire protocol does not expose a generic arbitrary-Event append operation.

Field limits and the pre-persistence sanitization contract are normative in
[redaction.md](redaction.md). The 1 MiB transport limit protects framing; an otherwise valid
mutation is still rejected when its canonical Event would exceed 65,536 UTF-8 bytes.

Project initialization and synchronization responses expose the accepted dependency artifact
digest but not a caller-supplied dependency override. Queries may return its extracted edges and
diagnostics; the artifact itself is never accepted as mutation input.

## Stable errors

- Request: `invalid_request`, `line_too_large`, `unsupported_version`, `unknown_operation`
- Content: `field_too_large`, `prohibited_field`, `invalid_text`, `event_too_large`
- Domain: `task_not_found`, `definition_missing`, `invalid_transition`,
  `dependency_unsatisfied`, `invalid_event`
- Intervention: `intervention_already_pending`, `intervention_conflict`
- Source: `source_not_found`, `source_ambiguous`, `source_invalid`, `source_changed`
- Storage: `idempotency_conflict`, `store_locked`, `store_corrupt`, `io_error`

Domain rejection leaves the process usable. Malformed stdout, mismatched identity/version, or
transport termination is fatal to the connection. Timeout does not prove mutation outcome; retry
uses the same request ID.

## Actor, ordering, and compatibility

Actor kind is `human|agent|adapter|system`; its optional ID is descriptive and introduces no
vendor semantics. The Core assigns Event sequence and timestamp under lock. An identical request
retry returns the original result without appending; different semantic reuse fails.

Protocol major 1 appears in every message. `version.get` advertises additive capabilities.
Removing fields or changing field/transition meaning requires a new major.
