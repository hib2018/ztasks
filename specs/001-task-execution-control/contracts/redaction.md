# Redaction and Safe Text Contract v1

## Boundary and order

Every public mutation passes this Core-owned pipeline before Event sequence allocation:

1. Decode the closed operation schema and reject unknown fields.
2. Reject prohibited field names and prohibited content classes.
3. Validate UTF-8, required/non-empty rules, unsafe control characters, and raw normalized field
   limits.
4. Sanitize recognized credential forms in permitted text with deterministic redaction markers.
5. Recheck sanitized field limits and measure the complete canonical Event.
6. Only then allocate identity/sequence and persist.

Rejection appends no Event and mutates no projection. Errors contain field path, policy/limit code,
and limit metadata, never the rejected value. Redaction happens before any Event, snapshot,
diagnostic, stdout/stderr, debug log, or telemetry rendering.

## Closed payloads and prohibited content

Each operation accepts only fields documented in [event-mapping.md](event-mapping.md). The
following concepts are never Event payload fields: `private_reasoning`, `reasoning`,
`chain_of_thought`, `transcript`, `raw_stdout`, `raw_stderr`, `environment`, `headers`, `cookies`,
`authorization`, `credentials`, `password`, `secret`, `token`, and `api_key`. Case-folded and
separator-normalized matches are rejected as `prohibited_field`.

Adapters may report only observable action, status, error, result, artifact/file reference, and
capability outcome through their typed fields. They must summarize process output; unrestricted
transcripts and raw process streams are not accepted. Adapters and callers are responsible for
sending bounded, reviewable, secret-free summaries. ztasks neither requests nor attempts to
classify an Agent's private reasoning or unknown secret semantics from permitted prose.

## Text rules and limits

| Field class | Limit | Measurement |
|---|---:|---|
| Task/Phase title | 200 | Unicode scalar values |
| actor/session identifier | 128 | UTF-8 bytes |
| comment, progress/current action, blocked reason, error/result message | 4,096 | UTF-8 bytes each |
| source locator | 4,096 | UTF-8 bytes |
| complete canonical Event | 65,536 | UTF-8 bytes |

Field limits apply to raw normalized input before credential replacement, so redaction cannot turn
an oversized request into an accepted one. The same limits are checked again after replacement.

Required text cannot be empty after normalization. NUL, C0/C1 controls other than permitted
line-feed/tab in multiline message fields, bidi overrides/isolates, and terminal escape sequences
are rejected as `invalid_text`; renderers still escape untrusted text defensively.

## Credential sanitization

Permitted free text is scanned for deterministic credential classes: authorization header values,
cookie header values, PEM private-key blocks, URI userinfo passwords, recognized provider token
prefixes, and assignment forms whose normalized key is `password`, `secret`, `token`, `api_key`,
or `authorization`. The matched value is replaced with `[REDACTED:<class>]`.

An accepted Event may record `redactions` entries containing only the field path and class. It
never records the matched bytes, a reversible encoding, or a digest of the secret. The response
returns the sanitized Event so caller and durable history agree.

Pattern detection is defense in depth, not permission to submit credentials. The Core guarantees
structural rejection of designated fields and non-retention of values matched by configured
detectors; it does not guarantee semantic discovery of unknown secret forms inside permitted free
text. Adding a detector is compatible; removing a detector or weakening a prohibited class
requires security review and a contract-version change.
