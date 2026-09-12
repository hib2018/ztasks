# Implementation Plan: Agent Task Execution Control

**Branch**: `001-task-execution-control` | **Date**: 2026-09-12 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/001-task-execution-control/spec.md`

## Summary

Build a project-local control surface that reads one Spec Kit `tasks.md` as immutable Task
Definition, records Agent execution and human intervention as an append-only Event history, and
reconstructs current Runtime State through a strict reducer. A Go CLI/TUI presents data and sends
requests to an independently executable Zig Core over versioned JSON Lines. The Core alone parses
definitions, validates transitions, enforces invariants, and commits durable state.

## Technical Context

**Language/Version**: Zig 0.16.0 Core; Go 1.27.x Frontend

**Primary Dependencies**: Zig standard library; Go standard library; Bubble Tea v2 for TUI

**Storage**: Project-local `.ztasks/events.jsonl` Runtime authority, immutable content-addressed
`.ztasks/sources/<source-digest>/definition.json` Definition batches and reproducible
`dependencies.json` extraction artifacts referenced by sync Events, atomic `state.json` cache,
`view.json`, lock file, and optional session records

**Testing**: `zig build test`; `go test ./...`; Go race tests; shared protocol fixtures;
fake child-process tests; cross-binary end-to-end tests

**Target Platform**: Local macOS and Linux terminals; local filesystem required for MVP durability

**Project Type**: Two-process local CLI/TUI application with independently testable Core

**Performance Goals**: Open and identify active/problem Tasks within 2 seconds for 500 Tasks and
10,000 Events; interactive navigation remains responsive at common terminal sizes

**Constraints**: `tasks.md` read-only; no FFI; no Agent-specific Core semantics; 1 MiB maximum
protocol line; 64 KiB maximum canonical Event; event-first durable commit; exact replay; no event
compaction in MVP; dependencies only from exact source declarations ending in
`(depends on T001, T002)`; digest-bound reproducible dependency JSON; typed payload allowlists,
pre-persistence redaction, and explicit caller responsibility for unknown free-text secrets

**Scale/Scope**: One bound Task source per Project Runtime; 500 Tasks, 10,000 Events, one trusted
local user, multiple cooperating frontend/adapter processes serialized by a project lock

## Constitution Check

*GATE: Passed before Phase 0 and re-checked after Phase 1 design.*

- **Human-Controlled Artifact Pipeline — PASS**: Tasks, Events, current projections, pending
  interventions, acknowledgements, and artifacts remain inspectable. No private reasoning is used.
- **Definition and Runtime Separation — PASS**: The source contract is read-only. Event history is
  the Runtime authority; the snapshot is disposable.
- **Event-Driven, Auditable Runtime — PASS**: Every Runtime mutation and intervention is typed,
  ordered, append-only, and replayable. Requests do not impersonate acknowledgements.
- **Core-Enforced Contracts and Tests — PASS**: Domain rules, parsing, transitions, persistence, and
  protocol validation reside in Zig. Go consumes Core results and has cross-language contract tests.
- **Agent-Independent Control Surface — PASS**: The protocol uses generic actors and capabilities;
  Pi is deferred to an adapter after the MVP.
- **Architecture and Data Boundaries — PASS**: Go/Zig process boundary, JSON Lines, project-local
  storage, crash-aware ordering, canonical dependency grammar, Core-owned operation/Event mapping,
  bounded/redacted text, and MVP limits are preserved.
- **Development Quality Gates — PASS**: Work can be split into reversible source, reducer, storage,
  protocol, CLI, TUI, intervention, adapter, and packaging phases with tests at each boundary.

Post-design re-check: all gates remain PASS. No complexity exception is required.

## Project Structure

### Documentation (this feature)

```text
specs/001-task-execution-control/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   ├── protocol-v1.md
│   ├── cli.md
│   ├── dependency-extraction.md
│   ├── event-mapping.md
│   ├── redaction.md
│   └── speckit-source.md
├── checklists/
│   └── requirements.md
└── tasks.md
```

### Source Code (repository root)

```text
core/
├── build.zig
├── build.zig.zon
└── src/
    ├── main.zig
    ├── root.zig
    ├── application/
    ├── domain/
    ├── protocol/
    ├── sources/
    └── storage/

app/
├── go.mod
├── cmd/ztasks/main.go
└── internal/
    ├── agent/
    ├── cli/
    ├── coreclient/
    ├── intervention/
    ├── protocol/
    └── tui/

protocol/
├── README.md
├── examples/
└── fixtures/

tests/
└── e2e/

scripts/
```

**Structure Decision**: Use two build roots because the Frontend and Core are separate executables
with a mandatory process boundary. Keep domain, source, storage, application, and transport concerns
separate inside the Core. Shared language-neutral examples and golden fixtures live at repository
root and are consumed by both test suites.

The public contracts deliberately separate three rule sets: dependency extraction and its derived
JSON, operation-to-Event causality, and enforceable redaction responsibilities. This prevents the
Markdown adapter, CLI, and Agent adapters from independently inventing domain semantics or turning
a cache into a second Definition authority.

## Complexity Tracking

No Constitution violations require justification.
