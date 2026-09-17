# ztasks

ztasks is a human control surface for Agent execution of Spec Kit Tasks. It reads `tasks.md`
without modifying it, while the Zig Core records append-only execution Events and reconstructs
Runtime state under `.ztasks/`.

Start with `ztasks init`, inspect with `ztasks status` or the default TUI, and use `start`, `pause`,
`resume`, `comment`, `retry`, `stop`, and `skip` to record execution and human intervention. The TUI
combines Task list, execution detail, Activity, and intervention state; `--json` provides stable
machine-readable CLI output.

`.ztasks/events.jsonl` is the audit authority. `state.json` is a rebuildable snapshot and
`sources/` contains immutable, digest-addressed Definition/dependency artifacts. Runtime data is
normally local, so add `.ztasks/` to each consuming Project's `.gitignore`; retain or export Events
separately when organizational audit policy requires it.

See [installation](docs/install.md), [usage guide](docs/guide.md), and
[development contracts](docs/development.md).
