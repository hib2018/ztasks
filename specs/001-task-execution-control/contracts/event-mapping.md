# Operation to Event Mapping v1

## Rule

An accepted mutation commits exactly one Event; a rejected mutation and every query commit none.
The Zig Core selects the Event type and validates actor, payload, transition, and persistence.
Callers cannot override the mapping. The response returns the committed Event. An identical
`request_id` retry returns that same Event without appending another.

## Queries

`version.get`, `project.inspect`, `task.list`, `task.show`, `event.list`, `source.validate`, and
`health.check` never append Events.

## Mutations

| Operation | Event | Allowed actor | Required intent/payload |
|---|---|---|---|
| `project.init` | `project.initialized` | human, system | accepted initial source binding, normalized-batch reference, dependency-artifact digest |
| `source.sync` | `source.synced` | human, agent, adapter, system | prior/new source digest, normalized-batch reference, dependency-artifact digest, added/changed/missing/reappeared ID sets |
| `task.start` | `task.started` | agent, adapter, human | task; agent/session when known |
| `task.progress` | `task.progress` | agent, adapter | task and observable current-action summary |
| `task.pause_ack` | `task.paused` | agent, adapter | task and optional pause-request correlation |
| `task.resume_ack` | `task.resumed` | agent, adapter | task and optional resume-request correlation |
| `task.block` | `task.blocked` | agent, adapter, human | task and reason |
| `task.fail` | `task.failed` | agent, adapter, human | task and safe error summary |
| `task.complete` | `task.completed` | agent, adapter, human | task and optional safe result summary |
| `task.skip` | `task.skipped` | agent, adapter | task and optional skip-request correlation |
| `task.comment` | `task.comment` | agent, adapter | task and message |
| `human.pause_request` | `human.pause_requested` | human | task |
| `human.resume_request` | `human.resume_requested` | human | task |
| `human.retry_request` | `human.retry_requested` | human | task |
| `human.stop_request` | `human.stop_requested` | human | task |
| `human.skip_request` | `human.skip_requested` | human | task |
| `human.inspect_request` | `human.inspect_requested` | human | task and optional focus |
| `human.comment` | `human.comment` | human | task and message |
| `intervention.respond` | `intervention.responded` | agent, adapter | request correlation, outcome, optional safe message |

Human-facing CLI commands `pause`, `resume`, `retry`, `stop`, `skip`, `inspect`, and `comment` use
the corresponding `human.*` operation. They never call acknowledgement operations. A manual
execution command such as `start`, `block`, `fail`, or `complete` may use actor kind `human`, but
remains an execution fact rather than an intervention request.

`task.skip` is an acknowledgement/execution fact and therefore excludes a human actor; a human
uses `human.skip_request`. `task.comment` similarly represents Agent/Adapter execution commentary;
a human uses `human.comment`.

## CLI `event emit`

`event emit` is a controlled alias for `task.progress`, `task.pause_ack`, `task.resume_ack`,
`task.block`, `task.fail`, `task.complete`, `task.skip`, `task.comment`, or
`intervention.respond`. Its `--type` value must equal the mapped Event type. It cannot append
system/source initialization Events or human-request Events, and it cannot bypass transition,
actor, field, redaction, or idempotency validation.
