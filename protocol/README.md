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
