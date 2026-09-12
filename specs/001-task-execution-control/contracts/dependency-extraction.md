# Spec Kit Dependency Extraction Contract v1

## Authority boundary

The bound Spec Kit `tasks.md` remains the only Task Definition source. ztasks reads it without
modification and writes a reproducible projection to:

```text
.ztasks/sources/<source-digest>/dependencies.json
```

The JSON is not accepted as input, is not user-editable configuration, and has no meaning when its
embedded source digest or extraction-contract version differs. Deleting it and regenerating it
must not change dependency meaning or Task readiness.

## Explicit source clause

The only MVP text that creates dependency edges is a single case-sensitive terminal clause in a
recognized Task description:

```text
 (depends on <task-id>(, <task-id>)*)
```

A Task ID is `T` followed by one or more ASCII digits. Exactly one ASCII space follows each comma;
the clause is preceded by one ASCII space and ends the Task row apart from trailing ASCII spaces.

```markdown
- [ ] T023 [P] [US2] Implement parser (depends on T019, T020)
- [ ] T024 Validate parser (depends on T023)
```

Dependency IDs retain declaration order for display and form a semantic set. Every dependency must
be `completed` or `skipped` before the Task is ready.

Task numbering, document or Phase order, `[P]`, story labels, paths, file overlap, titles without
the terminal clause, headings, graphs, and narrative dependency sections create no edges.

## Validation and diagnostics

A syntactically valid clause with a duplicate ID, self-dependency, unknown ID, or dependency cycle
rejects the Definition batch. Text that resembles but does not match the exact clause—wrong case,
spacing, separators, placement, or multiple clauses—creates no edge and emits a deterministic
`dependency_ambiguous` diagnostic. A Task without any clause emits an informational
`dependency_not_declared` diagnostic. Neither diagnostic authorizes inference.

Diagnostics contain code, Task ID when recognized, and one-based line/column span. They do not copy
the Task title or surrounding prose. Diagnostic and edge ordering follows document order.

## Canonical JSON

The raw source digest is lowercase SHA-256 over the exact `tasks.md` bytes, including line endings
and without text normalization. `dependencies.json` is UTF-8 without BOM, compact JSON with no
insignificant whitespace and exactly one trailing LF. Object keys use the schema order shown below;
Tasks and diagnostics use document/span order, and dependency IDs use declaration order.

```json
{"version":1,"contract_version":1,"source":{"locator":"specs/001-feature/tasks.md","digest":"sha256:0123..."},"dependencies":[{"task_id":"T023","depends_on":["T019","T020"],"evidence":{"line":42,"column":58}}],"diagnostics":[{"code":"dependency_not_declared","task_id":"T024","line":43,"column":1}]}
```

Schema keys are exactly:

1. Root: `version`, `contract_version`, `source`, `dependencies`, `diagnostics`
2. Source: `locator`, `digest`
3. Dependency: `task_id`, `depends_on`, `evidence`
4. Evidence: `line`, `column`
5. Diagnostic: `code`, `task_id`, `line`, `column`

JSON strings use the shortest required escaping for quotation mark, reverse solidus, and control
characters; other valid Unicode is emitted as UTF-8. Integers are unsigned base-10 without leading
zeroes. The artifact digest used by sync Events is lowercase SHA-256 over these complete canonical
bytes, including the trailing LF.

Changing accepted source syntax or canonical bytes incompatibly requires a new
`contract_version`. Adding a new diagnostic code without changing edges or canonical field shape is
additive only when older consumers reject an unsupported contract version safely.
