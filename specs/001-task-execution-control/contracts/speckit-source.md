# Spec Kit Task Source Contract

## Binding

One Project Runtime binds one Task document, resolved by: explicit `--source`; active directory in
`.specify/feature.json`; then the sole `specs/*/tasks.md`. It must be a regular Project-contained
file. Zero candidates is `source_not_found`; multiple fallback candidates is
`source_ambiguous`. MVP never merges documents.

## Recognized row

A Task row contains a Markdown list marker and checkbox, ID matching `T[0-9]+`, optional `[P]`,
optional story label such as `[US1]`, and non-empty description.
The nearest preceding `## Phase ...` heading supplies Phase. Document order is preserved.
Checkbox state is metadata.

Only an exact terminal dependency clause in the Task description, as defined by
[dependency-extraction.md](dependency-extraction.md), creates edges. The adapter does not infer
dependencies from Task number, document/Phase order, checkpoint prose, `[P]`, story label, file
paths, general title prose, graphs, or narrative dependency sections.

## Atomic output and sync

The adapter returns the normalized batch in [data-model.md](../data-model.md), not Markdown tokens.
Unknown targets, self-dependencies, cycles, duplicate IDs, and invalid text reject the whole batch.
It also emits the deterministic, digest-bound dependency JSON defined by the extraction contract.
Warnings may accompany acceptance. Rejection preserves the last binding, catalog, Runtime, and
history. A stale dependency artifact is never trusted. Each accepted sync commits the
`source.synced` Event specified by
[event-mapping.md](event-mapping.md), including a no-change sync. Sync never writes the source or
maps checkboxes to Runtime.
