# Protocol Fixture Policy

Fixtures are shared contract inputs, not snapshots of one implementation. Zig and
Go must consume the same files and agree on acceptance or the documented stable
error class.

## Updating fixtures

1. Change the normative contract under `specs/001-task-execution-control/contracts/`
   first and identify whether the change is additive or requires a protocol or
   extraction contract version increment.
2. Add a focused fixture; do not silently repurpose an existing case with different
   semantics.
3. Keep JSON Lines compact, UTF-8, one object per physical line, with a final LF.
4. Keep dependency inputs and expected artifacts paired. Recompute raw source
   digests from the exact `tasks.md` bytes and retain one-based evidence positions.
5. Run `make test-contract`, then the full `make test` suite.

## Secret-safe failures

- Fixtures must use unmistakably synthetic values and must never contain live
  credentials, private Agent reasoning, raw transcripts, or raw process streams.
- A rejection assertion may identify the case, field path, stable error code,
  policy class, or numeric limit. It must not print the rejected field value.
- Credential fixtures assert only sanitized output and redaction class metadata.
  They must also assert that the original synthetic value is absent from Events,
  responses, diagnostics, snapshots, and test failure output.
- Unknown secret forms in permitted prose remain the fixture caller's
  responsibility; such cases document that boundary and do not claim detection.
