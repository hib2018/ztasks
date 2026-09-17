# Quickstart Validation Guide

This guide defines end-to-end MVP evidence. Commands become runnable as implementation Tasks finish.

## Prerequisites and checks

- Zig 0.16.0, repository-pinned Go, macOS or Linux local filesystem
- Temporary Project with one Spec Kit `tasks.md`

```sh
zig build --build-file core/build.zig test
go test ./...
go test -race ./...
```

Expected: Core, Frontend, shared contract, process-failure, and race tests pass without a live
Agent or network.

## Established authority boundary

The Foundation suite fixes the following boundary before Runtime mutation exists:

- Zig Core owns Definition/Event/Runtime models, content limits, credential sanitization,
  closed payload validation, protocol request validation, and stable safe errors.
- Go owns transport-facing decode types and presentation compatibility only. It does not
  select Events, infer transitions, or mutate Runtime.
- `protocol/fixtures/` is the language-neutral contract input. `make test-contract` requires
  both implementations to consume the same envelope fixture successfully.
- Protocol stdout is JSON Lines only; diagnostics use stderr and may expose field/class/limit
  metadata but never rejected or redacted source values.

At this checkpoint there is deliberately no Event append, state reducer, source mutation,
or Agent-specific behavior.

Use a fixture containing these rows under a Phase heading:

```markdown
- [ ] T001 Create fixture foundation
- [ ] T002 Exercise dependent work (depends on T001)
- [ ] T003 [P] Exercise independent work
```

Expected source interpretation: T002 depends only on T001; T003 has no dependency. Narrative text,
Phase order, and `[P]` create no implicit edge.

After source validation, inspect
`.ztasks/sources/<source-digest>/dependencies.json`. It must identify the exact source digest,
contract version, T002→T001 edge and source coordinates, plus deterministic diagnostics for Tasks
without an explicit clause. Delete it and rerun validation; the regenerated JSON must have the same
bytes and readiness result. Modify `tasks.md`; the stale artifact must not be reused.

## Initialize and inspect

```sh
cd /path/to/fixture-project
ztasks init --source specs/001-demo/tasks.md
ztasks status
ztasks status --json
```

Expected: source bytes do not change; T001/T003 are ready; T002 is pending with T001 unsatisfied;
human and JSON output agree.

## Execute and unlock

```sh
ztasks start T001 --agent test-agent --session run-1
ztasks event emit --type task.progress --task T001 --message "implementing fixture"
ztasks complete T001
ztasks task show T002 --json
```

Expected: T001 completes and T002 becomes ready without a synthetic ready Event.

## Request and acknowledge pause

```sh
ztasks start T002 --agent test-agent --session run-1
ztasks pause T002
ztasks task show T002
ztasks event emit --type task.paused --task T002 --correlation <pause-request-id>
```

Expected: T002 remains running with a pending request before acknowledgement, then becomes paused
with the request/result relationship visible.

## Replay recovery

Back up and remove only derived `.ztasks/state.json`, then run `ztasks status --json`.
Expected: lifecycle, attempt, current action, and pending interventions rebuild identically without
changing Events.

## Source change and orphan

Add a Task and sync; then remove T002 and sync. `ztasks task show T002` and
`ztasks event list T002` must retain its history and report definition-missing. No source checkbox
is rewritten. Each successful sync, including a no-change sync, appends exactly one
`source.synced` Event with matching added/changed/missing/reappeared sets; a rejected sync appends
none.

## Operation/Event mapping

Exercise one query, one Task mutation, one human request, and one Adapter acknowledgement using
[event-mapping.md](contracts/event-mapping.md).

Expected: the query appends nothing; each accepted mutation appends exactly its mapped Event;
retrying the same request ID returns that Event without a second append; `event emit` rejects an
unknown, human, source, or project Event type.

## Redaction and field limits

Submit permitted raw text at its exact limit and one unit over, then exercise a prohibited
`private_reasoning` field, an authorization header, a recognized credential inside a comment,
unsafe terminal controls, and an Adapter attempt to submit raw stdout.

Expected: exact-limit sanitized content is accepted; over-limit, prohibited fields, and unsafe
controls are rejected before append without echoing their values; recognized credential material
is replaced before persistence and only the redaction field/class is recorded. Search Events,
snapshots, stdout, stderr, and diagnostics to verify that original secret bytes are absent.
Unknown secret-like prose is not claimed to be automatically classified; the fixture confirms the
documented caller/Adapter responsibility rather than treating it as a detector success case.

## Invalid input and durability

Exercise duplicate IDs, missing dependency, cycle, partial final Event, malformed committed Event,
duplicate request, lock contention, and simulated snapshot failure.

Expected: invalid sources do not publish; only an unterminated final fragment is auto-truncated;
interior corruption stops with a location; identical retry appends nothing; snapshot-only failure
does not undo an Event commit; concurrent mutation is serialized or returns `store_locked`.

## No Agent installed

`ztasks status`, `ztasks comment T001 "manual review"`, `ztasks event list T001`, and
`ztasks doctor` work without any Agent integration.

## Packaged installation evidence (2026-09-17)

The native macOS archive was installed into a clean temporary prefix and invoked with a restricted
`PATH` containing no Go or Zig toolchain. The Frontend discovered the bundled Core, completed the
product/Protocol/data handshake, and initialized two separate temporary Projects. Each Project
created only its own `.ztasks/events.jsonl`; no Runtime paths or Events were shared. This scenario
is automated by `tests/e2e/install_test.go`.

## Release validation evidence (2026-09-17)

- `zig fmt --check`, Zig Core tests, all Go tests, all contract/E2E tests, and `go test -race
  ./...` passed.
- The uncached 500-Task/10,000-Event performance scenario completed in 0.71 seconds (1.02 seconds
  wall time including the Go test process), below the two-second product limit.
- Quickstart scenarios ran in independent temporary Project roots. The packaged installation test
  took about 12 seconds including archive construction; ordinary E2E scenarios completed within
  the full suite's remaining few seconds. Cross-compilation still requires the release builder's
  Go and Zig toolchains; installed archives require neither.
- `strings` scans of both generated executables found none of the recognized fixture secret,
  prohibited private-reasoning field, or rejected fixture value. The cross-surface regression also
  verified non-echo in responses and Event history.

Normative references: [protocol-v1.md](contracts/protocol-v1.md),
[cli.md](contracts/cli.md), [dependency-extraction.md](contracts/dependency-extraction.md),
[event-mapping.md](contracts/event-mapping.md), [redaction.md](contracts/redaction.md), and
[speckit-source.md](contracts/speckit-source.md).
