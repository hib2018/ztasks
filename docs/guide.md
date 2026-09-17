# Usage guide

Run `ztasks init [tasks.md]` once, then `ztasks sync` whenever Spec Kit changes the source. Sync
never edits `tasks.md`; it writes immutable derived artifacts and one auditable Event. Use
`ztasks status`, `ztasks task show T001`, and `ztasks event list [T001]` for inspection.

Execution acknowledgements (`start`, progress emit, block, fail, complete) describe Agent facts.
Human actions (`pause`, `resume`, `comment`, `retry`, `stop`, `skip`, `inspect`) create intervention
requests; an Adapter reports whether the request was acknowledged or unsupported. A request is not
shown as a completed lifecycle transition until the Agent/Adapter confirms it.

The Runtime directory contains authoritative `events.jsonl`, rebuildable `state.json`, immutable
`sources/`, session data, and UI-only `view.json`. Deleting a snapshot does not delete history.
Do not edit Event history by hand. The normal Project `.gitignore` entry is `.ztasks/`; if Events
must be retained for audit, copy the append-only log to controlled storage instead of committing
ephemeral snapshots and locks.
