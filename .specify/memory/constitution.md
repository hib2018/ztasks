<!--
Sync Impact Report
- Version change: 1.0.0 -> 2.0.0
- Modified principles:
  - II. Definition and Runtime Separation -> permits only digest-bound, reproducible dependency
    extraction artifacts derived from read-only tasks.md
  - Architecture and Data Boundaries -> replaces an unimplementable absolute free-text secret
    guarantee with enforceable Core, Adapter, and caller responsibilities
- Added sections: none
- Removed sections: none
- Follow-up TODOs: none
-->
# ztasks Constitution

## Core Principles

### I. Human-Controlled Artifact Pipeline

ztasks MUST provide a Human Control Surface for Agent Task Execution. Work MUST be represented
through inspectable Tasks, Events, Runtime State, and resulting Artifacts so that a human can
review and intervene at any point. The system MUST NOT depend on access to an Agent's private
reasoning. It MUST expose what is running, what action is being performed, where execution is
stopped, and which intervention has been requested or acknowledged.

Human review MUST remain possible without imposing a universal approval gate before every
operation. Operations affecting definitions, history, protocol compatibility, or execution MUST
record enough information to identify the actor, time, target, request, and result. This preserves
human control through visibility, accountability, and recoverability rather than mandatory
pre-approval.

### II. Definition and Runtime Separation

Spec Kit `tasks.md` files are the canonical source of Task Definition. ztasks MUST treat them as
read-only and MUST NOT silently rewrite checkboxes, hierarchy, titles, dependencies, or metadata.
ztasks MUST NOT generate Tasks, operate an independent Planner, or make its own hierarchy
canonical.

Task Definition and Task Runtime MUST use separate models and persistence. Definition data comes
from a source adapter; Runtime data comes from validated Events. A completed Runtime Task MAY
correspond to an unchecked item in `tasks.md`. Any future reconciliation capability MUST be an
explicit, separately specified feature and MUST preserve the authority boundary.

ztasks MAY emit a machine-readable dependency extraction artifact only when it is produced
deterministically from explicit dependency statements in the bound `tasks.md`, includes the exact
source digest and parser-contract version, and can be discarded and regenerated without semantic
loss. The artifact MUST NOT become an independently editable Task Definition source. Ambiguous or
absent dependency prose MUST NOT be converted into inferred edges; it MUST remain unbound and be
reported as a diagnostic so correction occurs through the Spec Kit artifact workflow.

### III. Event-Driven, Auditable Runtime

Every Runtime change and human intervention MUST be represented by a typed, append-only Event.
Current Runtime State MUST be reproducible by reducing the Event stream. A material change MUST
remain reviewable after execution; deletion or compaction MUST NOT destroy the ability to explain
the resulting state.

Human requests and Agent acknowledgements MUST remain distinct. For example, a pause request MUST
NOT be presented as a paused Task until the executing Agent or Adapter confirms that execution has
paused. State snapshots MAY accelerate reads, but they MUST be disposable and reconstructible;
they MUST NOT become a second Runtime authority.

### IV. Core-Enforced Contracts and Tests

The Zig Core is the source of truth for Task models, Runtime State, Events, reduction, transition
validation, invariants, source parsing, protocol validation, and persistence. The Go Frontend MUST
present data and manage interaction, but MUST NOT reproduce or bypass state-transition rules.
Invalid input from a human, Frontend, or Agent MUST NOT create an invalid Runtime state.

Changes to the Core MUST include automated tests appropriate to their risk. Tests are mandatory
for state transitions, Event replay, invariant enforcement, persistence and recovery failures,
and JSON Lines Protocol contracts. Cross-language integration tests MUST verify that Go observes
the same decisions as the Zig Core. Failed validation or persistence MUST leave the last valid
durable state recoverable.

### V. Agent-Independent Control Surface

ztasks MUST remain usable without Pi or any other specific Agent. Agent-specific behavior MUST be
isolated behind an Adapter or Integration boundary and MUST communicate through the public CLI or
versioned protocol. The Core domain model and persistence format MUST NOT contain Pi-, Codex-,
Claude Code-, Gemini CLI-, or vendor-specific control semantics.

Adapters MAY translate generic intervention requests into capabilities supported by an Agent
harness. They MUST report whether an action was accepted, rejected, failed, or acknowledged, and
MUST NOT claim that an intervention took effect solely because it was requested.

## Architecture and Data Boundaries

- The Frontend MUST be implemented in Go and own CLI/TUI UX, rendering, input handling, human
  intervention interaction, Agent process integration, and the Zig Core protocol client.
- The Core MUST be implemented in Zig and own all domain rules and durable Runtime persistence.
- Go and Zig MUST initially communicate across a process boundary using versioned JSON Lines over
  stdin/stdout. FFI MUST NOT be introduced without a separately reviewed architectural amendment.
- Protocol messages MUST expose language-neutral domain concepts and MUST NOT leak Go or Zig
  implementation details. Machine-readable output MUST remain stable within a protocol version.
- The Spec Kit parser MUST implement a Task Source abstraction. The normalized Core model MUST NOT
  depend on Markdown tokens such as checkbox spelling or heading syntax.
- Project-local Runtime data MUST live under `.ztasks/`. Event history is authoritative; snapshots,
  view preferences, locks, and session data MUST be identifiable as separate concerns.
- Durable writes MUST be crash-aware. Event persistence MUST precede derived snapshot publication,
  and snapshot replacement MUST be atomic. Concurrent writers MUST be serialized or rejected.
- Event and Protocol schemas MUST NOT accept fields designated for credentials, private Agent
  reasoning, unrestricted transcripts, or raw process output. The Core MUST redact recognized
  credential forms before persistence and MUST NOT retain or echo original redacted values in
  Events, snapshots, responses, diagnostics, logs, or telemetry. Adapters and callers MUST submit
  only bounded, reviewable, secret-free action/result summaries; unknown secrets embedded in
  otherwise permitted free text are outside automatic classification guarantees. User-controlled
  text MUST still be validated and safely rendered.
- The MVP MUST remain limited to Spec Kit ingestion, Runtime states, Events and replay, CLI state
  operations, a Go monitoring TUI, and basic human intervention Events. Planner features and
  advanced Agent automation are outside this boundary.

## Development Workflow and Quality Gates

Work MUST be organized into small, inspectable Tasks with explicit completion evidence. Progress,
decisions, failures, and follow-up work MUST be visible through artifacts that a user can inspect
during or after execution. Large rewrites, repository renames, history changes, and irreversible
migrations MUST be decomposed into independently testable and reversible phases.

Each change MUST preserve these gates:

1. State the affected authority boundary: Definition, Event history, Runtime snapshot, Protocol,
   Frontend, or Adapter.
2. Keep domain decisions in Zig and presentation decisions in Go.
3. Add or update tests before considering a Core or Protocol behavior complete.
4. Verify malformed input, invalid transitions, interrupted writes, and replay where applicable.
5. Keep `tasks.md` unchanged unless a separately authorized Spec Kit workflow owns that change.
6. Record compatibility impact and provide a migration path for schema or Protocol changes.
7. Prefer the smallest implementation that satisfies the current Task; new frameworks and Agent-
   specific dependencies require explicit justification in the design artifact.

A feature is complete only when its behavior is observable through the public interface, its Core
rules are tested, its persisted state can be recovered as designed, and documentation reflects the
actual contract. TUI behavior MUST be testable independently from live Agents and external
services.

## Governance

This Constitution is the highest project-level engineering policy for ztasks. Specifications,
plans, Tasks, implementation, and reviews MUST demonstrate compliance. When another project
document conflicts with this Constitution, this Constitution governs until it is amended.

Amendments MUST be made through a reviewable change to this file. An amendment MUST include its
rationale, compatibility and migration impact, affected principles, and an updated Sync Impact
Report. Approval MAY occur before or after implementation according to the user's workflow, but
the amendment and its effects MUST remain discoverable and auditable.

Constitution versions follow semantic versioning:

- MAJOR: removes or incompatibly redefines a principle or authority boundary.
- MINOR: adds a principle or materially expands mandatory governance.
- PATCH: clarifies wording without changing required behavior.

Every feature specification and plan review MUST check the Definition/Runtime boundary, human
observability, Event auditability, Agent independence, and Core ownership of rules. Every release
review MUST verify Core and Protocol tests, replay/recovery behavior, documentation consistency,
and version compatibility. Exceptions MUST be documented with scope, rationale, risk, and a
follow-up Task; undocumented exceptions are not permitted.

**Version**: 2.0.0 | **Ratified**: 2026-09-12 | **Last Amended**: 2026-09-12
