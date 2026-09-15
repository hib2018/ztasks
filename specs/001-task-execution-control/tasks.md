# Tasks: Agent Task Execution Control

**Input**: Design documents from `/specs/001-task-execution-control/`

**Prerequisites**: `plan.md`, `spec.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`

**Tests**: Core and Protocol changes require tests under the project constitution. Test tasks are
listed before their corresponding implementation tasks and must fail for the intended reason first.

**Organization**: Tasks are grouped by user story so each increment remains independently
demonstrable. ztasks does not rewrite this file as Runtime state.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel because it uses different files and has no incomplete dependency
- **[Story]**: User Story traceability label; Setup, Foundation, and Polish have no story label
- Every task names its concrete file target

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize independently buildable Zig Core and Go Frontend roots plus shared fixtures.

- [X] T001 Create Zig 0.16 library, executable, and test build steps in `core/build.zig` and `core/build.zig.zon`
- [X] T002 Create the minimal Core entry point and test aggregation root in `core/src/main.zig` and `core/src/root.zig` (depends on T001)
- [X] T003 [P] Create the Go 1.27 module and minimal Frontend entry point in `app/go.mod` and `app/cmd/ztasks/main.go`
- [X] T004 [P] Document protocol ownership, versioning, and stdout/stderr separation in `protocol/README.md`
- [X] T005 Add repository build, format, and test entry points in `Makefile` (depends on T001, T003, T004)

**Checkpoint**: Empty Core and Frontend build and test independently without implementing domain behavior.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Establish shared domain types, exact bounds/redaction rules, protocol envelopes, and fixtures.

**⚠️ CRITICAL**: Complete this phase before starting any User Story.

- [X] T006 [P] Create Protocol v1 success/error/idempotency golden fixtures in `protocol/fixtures/v1/envelopes.jsonl` (depends on T005)
- [X] T007 [P] Create valid, raw/sanitized boundary-size, prohibited-field, recognized-credential, and unknown-secret-responsibility fixtures in `protocol/fixtures/v1/content-policy.jsonl` (depends on T005)
- [X] T008 [P] Create exact, ambiguous, absent, stale-digest, and deterministic dependency extraction fixtures in `protocol/fixtures/speckit/dependencies/` (depends on T005)
- [X] T009 [P] Write failing PhaseDefinition, TaskDefinition, and SourceSpan validation tests in `core/src/domain/task_definition.zig` (depends on T005)
- [X] T010 [P] Write failing Actor, Event identity, typed payload, and 65,536-byte Event tests in `core/src/domain/event.zig` (depends on T005)
- [X] T011 [P] Write failing RuntimeStatus and TaskRuntime model tests in `core/src/domain/task_runtime.zig` (depends on T005)
- [X] T012 [P] Write failing raw-and-sanitized boundary, control-character, prohibited-field, recognized-credential, and non-echo tests in `core/src/domain/content_policy.zig` (depends on T005)
- [X] T013 Implement pre-redaction UTF-8 measurement, identifier, title, and source-locator validation in `core/src/domain/content_policy.zig` (depends on T012)
- [X] T014 Implement deterministic recognized-credential sanitization, non-secret redaction metadata, and caller-responsibility diagnostics in `core/src/domain/content_policy.zig` (depends on T012)
- [X] T015 Implement PhaseDefinition, TaskDefinition, SourceSpan, and metadata validation using T013 in `core/src/domain/task_definition.zig` (depends on T009, T013)
- [X] T016 [P] Implement RuntimeStatus, DefinitionState, TaskRuntime, and safe ErrorDetail models in `core/src/domain/task_runtime.zig` (depends on T011)
- [X] T017 Implement Actor, EventType, closed typed payloads, canonical Event sizing, and prohibited-field rejection in `core/src/domain/event.zig` (depends on T010, T013, T014)
- [X] T018 [P] Write failing strict envelope, 1 MiB line, version, request identity, and content-policy error tests in `core/src/protocol/request.zig` and `core/src/protocol/response.zig` (depends on T005)
- [X] T019 Implement Protocol v1 request/response decoding, stable errors, and sanitized diagnostics in `core/src/protocol/request.zig` and `core/src/protocol/response.zig` (depends on T006, T017, T018)
- [X] T020 [P] Write Go golden-fixture decoding and unknown-field rejection tests in `app/internal/protocol/protocol_test.go` (depends on T005)
- [X] T021 Implement language-neutral Go Protocol types without domain transitions in `app/internal/protocol/protocol.go` (depends on T006, T020)
- [X] T022 [P] Add a fixture checker that verifies Zig and Go accept the same envelopes in `tests/contract/protocol_fixture_test.go` (depends on T019, T021)
- [X] T023 [P] Document fixture update and secret-safe failure-output rules in `protocol/fixtures/README.md` (depends on T006, T007, T008)
- [X] T024 Run Foundation tests and record the established Core/Frontend authority boundary in `specs/001-task-execution-control/quickstart.md` (depends on T015, T016, T017, T019, T021, T022, T023)

**Checkpoint**: Both languages agree on envelopes, limits, and sanitized errors; no Runtime mutation exists yet.

---

## Phase 3: User Story 1 - 実行状況を把握する (Priority: P1) 🎯 Monitor MVP

**Goal**: Read one Spec Kit `tasks.md` without mutation, emit digest-bound dependency JSON, and show Phase-grouped Task readiness and detail.

**Independent Test**: Load the canonical dependency fixture, verify deterministic
`dependencies.json`, T001/T003 ready, T002 pending on T001, stale-artifact rejection,
human/JSON/TUI agreement, and unchanged source bytes.

### Tests for User Story 1

- [X] T025 [P] [US1] Write source binding resolution and Project path-escape rejection tests in `core/src/sources/source.zig` (depends on T024)
- [X] T026 [P] [US1] Write recognized row, Phase, P/story, checkbox, order, and title parsing tests in `core/src/sources/speckit.zig` (depends on T024)
- [X] T027 [P] [US1] Write exact terminal clause, ambiguous/absent diagnostic, canonical JSON, raw SHA-256, and stale-artifact tests in `core/src/sources/dependency_extraction.zig` (depends on T024)
- [X] T028 [P] [US1] Write duplicate, missing, self, and cyclic dependency batch rejection tests in `core/src/application/definition_query.zig` (depends on T024)
- [X] T029 [P] [US1] Write pending/ready and unsatisfied dependency projection tests in `core/src/domain/reducer.zig` (depends on T024)
- [X] T030 [P] [US1] Write no-Event query mapping tests for task.list, task.show, and source.validate in `core/src/application/query.zig` (depends on T024)
- [X] T031 [P] [US1] Write status and task-show human/JSON CLI output tests in `app/internal/cli/status_test.go` (depends on T024)
- [X] T032 [P] [US1] Write Phase/Task selection, filtering, and detail model tests in `app/internal/tui/model/model_test.go` (depends on T024)

### Implementation for User Story 1

- [X] T033 [US1] Implement explicit, feature.json, and sole-candidate Task source resolution in `core/src/sources/source.zig` (depends on T025)
- [X] T034 [US1] Implement exact terminal dependency extraction, evidence spans, deterministic diagnostics, and canonical JSON in `core/src/sources/dependency_extraction.zig` (depends on T027)
- [X] T035 [US1] Implement the normalized read-only Spec Kit adapter in `core/src/sources/speckit.zig` (depends on T026, T034)
- [X] T036 [US1] Implement atomic DefinitionBatch validation for read queries in `core/src/application/definition_query.zig` (depends on T028, T033, T035)
- [X] T037 [US1] Implement initial pending/ready projection and unsatisfied IDs in `core/src/domain/reducer.zig` (depends on T029, T036)
- [X] T038 [US1] Implement task.list, task.show, and source.validate query services in `core/src/application/query.zig` (depends on T030, T037)
- [X] T039 [US1] Implement the read-only Core serve loop with protocol-only stdout in `core/src/protocol/handler.zig` (depends on T038)
- [X] T040 [US1] Implement shell-free Core process startup and response correlation in `app/internal/coreclient/client.go` (depends on T039)
- [X] T041 [US1] Implement status and task show human/JSON commands in `app/internal/cli/status.go` (depends on T031, T040)
- [X] T042 [US1] Implement read-only Task list/detail/filter/resize TUI in `app/internal/tui/model/model.go`, `app/internal/tui/update/update.go`, and `app/internal/tui/view/view.go` (depends on T032, T040)
- [X] T043 [US1] Add cross-binary monitor, dependency artifact regeneration/stale rejection, and source byte-invariance coverage in `tests/e2e/monitor_test.go` (depends on T041, T042)

**Checkpoint**: Users can monitor Definition and derived readiness without initialization, Event mutation, or an Agent.

---

## Phase 4: User Story 2 - Agent実行を記録する (Priority: P2)

**Goal**: Validate, durably append, and replay Agent execution Events with exact operation/Event causality.

**Independent Test**: Submit valid and invalid Event sequences, retry a committed request, remove the
snapshot, and verify only mapped Events persist and replay reconstructs identical Runtime.

### Tests for User Story 2

- [ ] T044 [P] [US2] Write all execution transitions, terminal rules, and reason/error precondition tests in `core/src/domain/transition.zig` (depends on T043)
- [ ] T045 [P] [US2] Write progress, attempt, dependency unlock, and deterministic replay tests in `core/src/domain/reducer.zig` (depends on T043)
- [ ] T046 [P] [US2] Create execution operation/Event mapping fixtures in `protocol/fixtures/v1/execution.jsonl` (depends on T043)
- [ ] T047 [P] [US2] Write Core-owned task operation/Event and actor mapping tests in `core/src/application/operation_map.zig` (depends on T043)
- [ ] T048 [P] [US2] Write append/sync, contiguous sequence, duplicate request, and conflict tests in `core/src/storage/event_log.zig` (depends on T043)
- [ ] T049 [P] [US2] Write lock contention and process-exit release tests in `core/src/storage/lock.zig` (depends on T043)
- [ ] T050 [P] [US2] Write snapshot round-trip and stale/prefix mismatch rejection tests in `core/src/storage/snapshot.zig` (depends on T043)
- [ ] T051 [P] [US2] Write truncated-tail and interior-corruption replay tests in `core/src/storage/replay.zig` (depends on T043)
- [ ] T052 [P] [US2] Write malformed response, wrong ID, stderr flood, timeout, and retry tests in `app/internal/coreclient/process_test.go` (depends on T043)
- [ ] T053 [P] [US2] Write execution command, event-list, and restricted event-emit CLI tests in `app/internal/cli/execution_test.go` (depends on T043)

### Implementation for User Story 2

- [ ] T054 [US2] Implement the execution transition table in `core/src/domain/transition.zig` (depends on T043)
- [ ] T055 [US2] Implement execution Event reduction, attempts, current action, and dependency reevaluation in `core/src/domain/reducer.zig` (depends on T043)
- [ ] T056 [US2] Implement the closed task operation/Event mapping and actor rules in `core/src/application/operation_map.zig` (depends on T043)
- [ ] T057 [US2] Implement Project-local `.ztasks/` path ownership checks in `core/src/storage/paths.zig` (depends on T043)
- [ ] T058 [US2] Implement stable cross-process Project locking in `core/src/storage/lock.zig` (depends on T043)
- [ ] T059 [US2] Implement append-first synced Event storage and persistent request-id deduplication in `core/src/storage/event_log.zig` (depends on T043)
- [ ] T060 [US2] Implement strict replay and locked final-fragment recovery in `core/src/storage/replay.zig` (depends on T043)
- [ ] T061 [US2] Implement same-directory atomic disposable snapshots with prefix identity in `core/src/storage/snapshot.zig` (depends on T043)
- [ ] T062 [US2] Implement validate→map→redact→append/sync→snapshot command transactions in `core/src/application/command.zig` (depends on T043)
- [ ] T063 [US2] Connect execution mutations and event.list to the Core handler in `core/src/protocol/handler.zig` (depends on T043)
- [ ] T064 [US2] Implement concurrent pipe draining, cancellation, and same-request retry in `app/internal/coreclient/client.go` (depends on T043)
- [ ] T065 [US2] Implement execution commands, event list, and allowlisted event emit in `app/internal/cli/execution.go` (depends on T043)
- [ ] T066 [US2] Add Runtime status, action, agent/session, and Activity rendering in `app/internal/tui/view/activity.go` (depends on T043)
- [ ] T067 [US2] Add cross-binary mapping, replay, durability, and idempotency tests in `tests/e2e/execution_test.go` (depends on T043)

**Checkpoint**: Event history is the Runtime authority and Go cannot create an unmapped or invalid state.

---

## Phase 5: User Story 3 - 実行途中に介入する (Priority: P3)

**Goal**: Record human requests separately from Agent acknowledgements/results and keep both observable.

**Independent Test**: Request pause on a running Task, verify running+pending before acknowledgement,
then submit task.paused and verify paused+resolved with correlated Activity in CLI and TUI.

### Tests for User Story 3

- [ ] T068 [P] [US3] Write intervention creation, status, conflict, and missing-definition tests in `core/src/domain/intervention.zig` (depends on T067)
- [ ] T069 [P] [US3] Write pending/acknowledged/rejected/unsupported/resolved reducer tests in `core/src/domain/reducer.zig` (depends on T067)
- [ ] T070 [P] [US3] Create human-request and response operation/Event fixtures in `protocol/fixtures/v1/interventions.jsonl` (depends on T067)
- [ ] T071 [P] [US3] Write human-versus-acknowledgement mapping and actor rejection tests in `core/src/application/operation_map.zig` (depends on T067)
- [ ] T072 [P] [US3] Write pause/resume/retry/stop/skip/inspect/comment wording tests in `app/internal/cli/intervention_test.go` (depends on T067)
- [ ] T073 [P] [US3] Write pending-versus-confirmed TUI model/view tests in `app/internal/tui/view/intervention_test.go` (depends on T067)

### Implementation for User Story 3

- [ ] T074 [US3] Implement InterventionRequest state and control-conflict validation in `core/src/domain/intervention.zig` (depends on T067)
- [ ] T075 [US3] Implement intervention request/response/lifecycle correlation reduction in `core/src/domain/reducer.zig` (depends on T067)
- [ ] T076 [US3] Extend the operation/Event mapping with all human and response operations in `core/src/application/operation_map.zig` (depends on T067)
- [ ] T077 [US3] Implement human request and intervention.respond transactions in `core/src/application/command.zig` (depends on T067)
- [ ] T078 [US3] Connect intervention operations to the Core handler in `core/src/protocol/handler.zig` (depends on T067)
- [ ] T079 [US3] Implement human intervention CLI with requested/acknowledged wording in `app/internal/cli/intervention.go` (depends on T067)
- [ ] T080 [US3] Implement Human Intervention pane and pending/result rendering in `app/internal/tui/view/intervention.go` (depends on T067)
- [ ] T081 [US3] Define vendor-neutral Adapter capability and safe-summary interfaces in `app/internal/agent/adapter.go` (depends on T067)
- [ ] T082 [US3] Add Adapter conformance fixtures for supported, rejected, and unsupported actions in `app/internal/agent/adapter_test.go` (depends on T067)
- [ ] T083 [US3] Add pause timing, first-attempt distinction, and 30-second workflow usability validation in `tests/e2e/intervention_test.go` (depends on T067)

**Checkpoint**: Request and effect cannot be confused, and the workflow remains usable without a live Agent.

---

## Phase 6: User Story 4 - Projectを安全に再開・診断する (Priority: P4)

**Goal**: Initialize, sync, restart, preserve historical Definitions, and diagnose failures without history loss.

**Independent Test**: Initialize a Project, perform changed and no-change syncs, remove/reappear a Task,
delete the snapshot, inject storage failures, and verify exact source.synced Events and safe recovery.

### Tests for User Story 4

- [ ] T084 [P] [US4] Write content-addressed Definition and dependency artifact verify/reuse/interruption tests in `core/src/storage/source_artifact_store.zig` (depends on T067)
- [ ] T085 [P] [US4] Write project.initialized and source.synced payload, dependency-artifact digest, and change-set tests in `core/src/domain/event.zig` (depends on T067)
- [ ] T086 [P] [US4] Write added/changed/missing/reappeared/no-change sync projection tests in `core/src/application/sync.zig` (depends on T067)
- [ ] T087 [US4] Write invalid-source and failed-artifact/Event persistence rollback tests in `core/src/application/sync.zig` (depends on T086)
- [ ] T088 [P] [US4] Write exact project.init/source.sync operation/Event mapping tests in `core/src/application/operation_map.zig` (depends on T067)
- [ ] T089 [P] [US4] Create init, sync, inspect, and health Protocol fixtures in `protocol/fixtures/v1/project.jsonl` (depends on T067)
- [ ] T090 [P] [US4] Write corrupt history, stale snapshot, orphan artifact, and filesystem diagnostic tests in `core/src/application/doctor.zig` (depends on T067)
- [ ] T091 [P] [US4] Write init/sync/doctor/help/version CLI tests in `app/internal/cli/project_test.go` (depends on T067)
- [ ] T092 [P] [US4] Write view selection/filter preference round-trip tests in `app/internal/tui/model/view_store_test.go` (depends on T067)

### Implementation for User Story 4

- [ ] T093 [US4] Implement verified content-addressed Definition batch and dependency JSON writes in `core/src/storage/source_artifact_store.zig` (depends on T067)
- [ ] T094 [US4] Implement project.initialized and source.synced typed payloads with both artifact digests in `core/src/domain/event.zig` (depends on T067)
- [ ] T095 [US4] Implement Project initialization without modifying Task source in `core/src/application/project_init.zig` (depends on T067)
- [ ] T096 [US4] Implement atomic sync diff, missing/reattach projection, and no-change Event creation in `core/src/application/sync.zig` (depends on T067)
- [ ] T097 [US4] Enforce artifact-sync before Event commit and inert unreferenced-artifact recovery in `core/src/application/sync.zig` (depends on T067)
- [ ] T098 [US4] Extend the operation/Event mapping for project.init and source.sync in `core/src/application/operation_map.zig` (depends on T067)
- [ ] T099 [US4] Connect project.init, source.sync, project.inspect, and health.check in `core/src/protocol/handler.zig` (depends on T067)
- [ ] T100 [US4] Implement source/history/snapshot/artifact/lock/filesystem diagnostics in `core/src/application/doctor.zig` (depends on T067)
- [ ] T101 [US4] Implement init, sync, doctor, help, and version commands with actionable errors in `app/internal/cli/project.go` (depends on T067)
- [ ] T102 [US4] Implement Runtime-independent atomic TUI preferences in `app/internal/tui/model/view_store.go` (depends on T067)
- [ ] T103 [US4] Render missing Definitions, sync diffs, warnings, and stale activity in `app/internal/tui/view/view.go` (depends on T067)
- [ ] T104 [US4] Add sync/orphan/reattach/restart and rejected-sync E2E coverage in `tests/e2e/recovery_test.go` (depends on T067)
- [ ] T105 [US4] Add Event-committed/snapshot-failed and artifact-written/Event-failed crash scenarios in `tests/e2e/crash_recovery_test.go` (depends on T067)

**Checkpoint**: Every accepted sync is auditable and reconstructible; rejected syncs preserve prior authority.

---

## Phase 7: User Story 5 - 一度導入して複数Projectで利用する (Priority: P5)

**Goal**: Install one compatible Frontend/Core pair and safely use it across isolated Projects.

**Independent Test**: Install a release archive into a clean user prefix without build toolchains,
operate on two fixture Projects, and verify missing/mismatched components fail before mutation.

### Tests for User Story 5

- [ ] T106 [P] [US5] Write bundled-Core discovery precedence and missing-component tests in `app/internal/coreclient/discovery_test.go` (depends on T105)
- [ ] T107 [P] [US5] Write product/protocol/data compatibility handshake tests in `core/src/protocol/compatibility.zig` (depends on T105)
- [ ] T108 [P] [US5] Write Frontend mismatch refusal and actionable guidance tests in `app/internal/coreclient/compatibility_test.go` (depends on T105)
- [ ] T109 [P] [US5] Add clean-prefix, no-toolchain, two-Project isolation install tests in `tests/e2e/install_test.go` (depends on T105)

### Implementation for User Story 5

- [ ] T110 [US5] Implement Core product/protocol/data capability reporting in `core/src/protocol/compatibility.zig` (depends on T105)
- [ ] T111 [US5] Implement bundled Core discovery relative to the Frontend installation in `app/internal/coreclient/discovery.go` (depends on T105)
- [ ] T112 [US5] Enforce compatibility handshake before Project Runtime mutations in `app/internal/coreclient/compatibility.go` (depends on T105)
- [ ] T113 [US5] Add missing/incompatible component guidance to version and doctor in `app/internal/cli/project.go` (depends on T105)
- [ ] T114 [US5] Create macOS/Linux two-binary archive assembly and checksum generation in `scripts/package.sh` (depends on T105)
- [ ] T115 [US5] Create user-prefix install/update/uninstall helper with explicit targets in `scripts/install.sh` (depends on T105)
- [ ] T116 [US5] Document one-time installation, layout, upgrades, and Project isolation in `docs/install.md` (depends on T105)
- [ ] T117 [US5] Run the packaged binaries against two fixture Projects and record evidence in `specs/001-task-execution-control/quickstart.md` (depends on T105)

**Checkpoint**: One installation serves multiple Projects without source clone or per-Project toolchains.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Verify performance, security, documentation, and end-to-end contract consistency.

- [ ] T118 [P] Add a 500-Task/10,000-Event two-second performance test in `tests/e2e/performance_test.go` (depends on T083, T105, T117)
- [ ] T119 [P] Add cross-surface recognized-secret absence, prohibited-field, non-echo, and pre/post-redaction boundary regression tests in `tests/e2e/content_policy_test.go` (depends on T083, T105, T117)
- [ ] T120 [P] Add narrow-terminal, resize, Unicode wrapping, and keyboard navigation tests in `app/internal/tui/view/view_test.go` (depends on T083, T105, T117)
- [ ] T121 [P] Add fuzz/property coverage for dependency extraction, Protocol decoding, and Event replay in `core/src/root.zig` (depends on T083, T105, T117)
- [ ] T122 [P] Document CLI/TUI workflow, Runtime storage, audit retention, and `.gitignore` guidance in `README.md` and `docs/guide.md` (depends on T083, T105, T117)
- [ ] T123 [P] Publish dependency extraction/JSON, operation/Event, source adapter, and redaction responsibility contracts in `protocol/README.md` and `docs/development.md` (depends on T083, T105, T117)
- [ ] T124 Add a contract consistency check covering documented operations, Events, fixtures, and Core mappings in `tests/contract/mapping_test.go` (depends on T083, T105, T117)
- [ ] T125 Run `zig fmt --check`, Core tests, Go tests, race tests, and all E2E tests and record results in `specs/001-task-execution-control/quickstart.md` (depends on T083, T105, T117)
- [ ] T126 Run every quickstart validation in isolated Projects and record timings and constraints in `specs/001-task-execution-control/quickstart.md` (depends on T083, T105, T117)
- [ ] T127 Review generated binaries and diagnostics for recognized fixture secrets, prohibited private-reasoning fields, and accidental value echo in `tests/e2e/content_policy_test.go` (depends on T083, T105, T117)

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 Setup**: No dependencies.
- **Phase 2 Foundation**: Depends on Setup and blocks every User Story.
- **Phase 3 US1**: Depends on Foundation; delivers the read-only Monitor MVP.
- **Phase 4 US2**: Depends on US1 Definition/query projection.
- **Phase 5 US3**: Depends on US2 Event transactions and reducer.
- **Phase 6 US4**: Depends on US2 storage/replay; its Core sync work may overlap US3 where files do not conflict.
- **Phase 7 US5**: Depends on US4 initialization/diagnostics and the complete process protocol.
- **Phase 8 Polish**: Depends on all User Stories selected for release.

### User Story Dependency Graph

```text
Setup -> Foundation -> US1 Monitor -> US2 Event Runtime -> US3 Intervention
                                      └───────────────> US4 Sync/Recovery -> US5 Installation

US1 + US2 + US3 + US4 + US5 -> Polish
```

### User Story Independence

- **US1**: Uses a source fixture and read-only Core to regenerate dependency JSON; no initialization, Event mutation, or Agent required.
- **US2**: Uses fixture Definitions to prove mapping, persistence, replay, and CLI independently of TUI.
- **US3**: Uses a fake Adapter and fixture Runtime to prove request/ack semantics without a live Agent.
- **US4**: Uses fixture sources/stores to prove init, sync Events, artifacts, recovery, and diagnostics.
- **US5**: Uses release archives and isolated Project fixtures to prove installation and compatibility.

### Within Each User Story

- Write each listed test first and confirm it fails for the intended missing behavior.
- Implement domain/content rules before application services, then Protocol, then Go presentation.
- Persist Definition artifacts before referencing Events; persist Events before derived snapshots.
- Stop at each Checkpoint and preserve source byte identity and prior durable history.

### Parallel Opportunities

- T003–T005 can run alongside T001–T002 without file conflicts.
- Foundation fixture/model test tasks marked `[P]` can run in parallel.
- Tests marked `[P]` within each User Story target independent files or fixtures.
- After US2, US3 and the non-overlapping US4 storage/diagnostic tasks may proceed in parallel.
- US5 packaging documentation can begin after layout is fixed while compatibility code is completed.
- Polish performance, content policy, TUI, fuzzing, and documentation tasks can run in parallel.

---

## Parallel Examples

### User Story 1

```text
Task T025: source binding tests in core/src/sources/source.zig
Task T027: dependency extraction tests in core/src/sources/dependency_extraction.zig
Task T029: readiness tests in core/src/domain/reducer.zig
Task T031: CLI status tests in app/internal/cli/status_test.go
Task T032: TUI model tests in app/internal/tui/model/model_test.go
```

### User Story 2

```text
Task T044: transition tests in core/src/domain/transition.zig
Task T047: operation/Event mapping tests in core/src/application/operation_map.zig
Task T048: Event log tests in core/src/storage/event_log.zig
Task T050: snapshot tests in core/src/storage/snapshot.zig
Task T052: Core process tests in app/internal/coreclient/process_test.go
```

### User Story 3

```text
Task T068: intervention domain tests in core/src/domain/intervention.zig
Task T070: intervention fixtures in protocol/fixtures/v1/interventions.jsonl
Task T072: intervention CLI tests in app/internal/cli/intervention_test.go
Task T073: intervention TUI tests in app/internal/tui/view/intervention_test.go
```

### User Story 4

```text
Task T084: source artifact store tests in core/src/storage/source_artifact_store.zig
Task T086: sync projection tests in core/src/application/sync.zig
Task T089: Project Protocol fixtures in protocol/fixtures/v1/project.jsonl
Task T090: doctor tests in core/src/application/doctor.zig
Task T091: Project CLI tests in app/internal/cli/project_test.go
```

### User Story 5

```text
Task T106: Core discovery tests in app/internal/coreclient/discovery_test.go
Task T107: Core compatibility tests in core/src/protocol/compatibility.zig
Task T108: Frontend compatibility tests in app/internal/coreclient/compatibility_test.go
Task T109: installation E2E tests in tests/e2e/install_test.go
```

---

## Implementation Strategy

### Monitor MVP First (User Story 1)

1. Complete Setup.
2. Complete Foundation.
3. Complete US1 only.
4. Stop and validate read-only monitoring and source byte invariance.
5. Present Task list/detail/readiness to the user before enabling Runtime mutation.

### Incremental Delivery

1. Setup + Foundation: two-process skeleton, shared contract, and content policy.
2. US1: Spec Kit read-only Task monitoring and deterministic dependency JSON extraction.
3. US2: mapped execution Events, durable Runtime, replay, and Activity.
4. US3: Human Intervention request/result loop.
5. US4: initialization, sync Event/artifact, restart, orphan handling, and doctor.
6. US5: one-time installation, compatibility, and multi-Project isolation.
7. Polish: performance, security, consistency, and documentation evidence.

Each phase should be one reversible commit or a small reviewable commit series. Do not rename or
delete `ztodo`/`ztodo-fx`, rewrite Spec Kit `tasks.md`, add Planner responsibilities, or couple the
Core to a specific Agent.

## Notes

- `[P]` appears only where tasks can proceed without editing the same target or waiting on an incomplete task.
- Every User Story task carries `[USn]`; Setup, Foundation, and Polish tasks do not.
- Core and Protocol tests are mandatory under the constitution; UI tests avoid live Agent/network dependencies.
- Task checkboxes are planning artifacts and are never synchronized from ztasks Runtime state.
- Progress, decisions, failures, and evidence remain reviewable through Tasks, Events, and linked artifacts.
