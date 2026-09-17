# Development and contracts

The Go Frontend presents commands and views. The Zig Core exclusively validates Task transitions,
Event schemas, source parsing, invariants, persistence, replay, and redaction. They communicate as
bounded JSON Lines over stdin/stdout; no implementation-specific Zig or Go types form part of the
wire contract.

Normative contracts live in the feature `contracts/` directory: dependency extraction defines the
derived dependency JSON; event mapping fixes each operation to exactly one Event; the Spec Kit
source adapter keeps Markdown read-only; and redaction defines prohibited fields, recognized
credential replacement, byte/scalar limits, and the pre-persistence boundary. Changes to these
rules must update fixtures, both language implementations, and the contract consistency test.
