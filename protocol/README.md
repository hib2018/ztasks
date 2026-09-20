# ztasks Core Protocol

The protocol is the language-neutral contract between frontends or agent
adapters and the Zig core. The Zig core owns validation, state transitions,
invariants, persistence, and state reconstruction. Clients present commands and
render results; they must not infer or impose runtime state transitions.

## Transport

- One UTF-8 JSON value per line over standard input and standard output.
- A long-running core process reads requests from standard input and emits one
  response for each request on standard output.
- Standard output is reserved exclusively for protocol messages.
- Diagnostics and operational logs go to standard error and must never contain
  unredacted sensitive event fields.
- Protocol version `1` is represented by a top-level integer `version` field on
  every request and response.

## Compatibility

A client must reject responses with an unsupported version. The core must reject
requests with a missing or unsupported version using a structured error response.
Additive optional fields may be introduced within a protocol version; removing a
field, changing its meaning, or changing operation behavior requires a new version.

Concrete request, response, operation, and event schemas are introduced in the
protocol phase. Until then this document fixes only ownership, framing, stream
discipline, and versioning.

## Published responsibility contracts

- Dependency extraction produces digest-bound JSON and never modifies the source Markdown.
- Every accepted mutation maps to exactly one Core-selected Event; queries append none.
- Source adapters translate external definitions into source-neutral TaskDefinition values.
- Closed payload schemas reject private reasoning and raw streams; recognized credentials are
  redacted before Event identity allocation or persistence.

The normative field limits, extraction grammar, mappings, and redaction classes are maintained in
`specs/001-task-execution-control/contracts/`. Shared JSONL fixtures under `protocol/fixtures/`
exercise the language-neutral surface.

## Existing-state bootstrap

`project.bootstrap` imports an existing Spec Kit checkbox state without changing
the source Markdown. The request payload is closed and requires
`{"mode":"speckit_checkboxes"}`; an optional `locator` selects `tasks.md`.

An accepted request appends exactly one `project.runtime_bootstrapped` Event.
Its payload contains the digest-bound Definition references and a `completed`
array of imported Task IDs. The reducer treats those IDs as `completed`, while
later task lifecycle Events still take precedence. This Event records an import;
it must not be represented as one or more `task.completed` Events.

The Core rejects the bootstrap when a checked Task depends on an unchecked,
non-terminal Task, when an imported Task already has conflicting Runtime state,
or when there is no new checked state to import.
