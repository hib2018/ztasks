# CLI Contract

## General behavior

- `ztasks` opens the interactive monitor in the terminal's alternate screen buffer and restores the
  previous shell screen when it exits.
- Human-readable output is default; supported reads accept `--json`.
- Usage, domain, and transport failures have distinct non-zero exit classes.
- Machine-readable stdout contains one documented JSON value and no diagnostics.
- Current directory is Project root unless `--project` is supplied.

## Commands

```text
ztasks
ztasks init [--source <project-relative-tasks.md>]
ztasks sync [--source <project-relative-tasks.md>]
ztasks status [--json]
ztasks task show <id> [--json]

ztasks start <id> [--agent <id>] [--session <id>]
ztasks pause <id>
ztasks resume <id>
ztasks block <id> [reason]
ztasks fail <id> [reason]
ztasks complete <id>
ztasks skip <id>
ztasks retry <id>
ztasks stop <id>
ztasks inspect <id>
ztasks comment <id> <message>

ztasks event list [<id>] [--json]
ztasks event emit --type <type> --task <id> [event fields...]
ztasks doctor [--json]
ztasks help
ztasks version [--json]
```

Human pause/resume/retry/stop/skip/inspect/comment commands emit human Events. Confirmation is
submitted by `event emit` or an Adapter and is Core-validated. Successful human requests say
“requested”, never “paused” or “stopped”.

`event emit --type` accepts only the execution/response Event types listed in
[event-mapping.md](event-mapping.md) and translates them to their corresponding Core operation.
It cannot emit `project.*`, `source.*`, `human.*`, or an unknown Event type. Human Event types are
created only by their named human commands so actor and intervention validation cannot be bypassed.

All text follows [redaction.md](redaction.md). CLI diagnostics identify a rejected field and its
limit or policy class, but never repeat the rejected value or original redacted secret.

Invalid transitions show current status and corrective conditions. Pending dependencies list IDs.
Missing definitions remain inspectable but reject execution transitions. Destructive repair is
outside MVP; `doctor` gives guidance without silently truncating committed interior history.

The interactive view coordinates Task list, detail, Activity, and intervention areas with resize,
Unicode-safe navigation, filtering, refresh, and distinct lifecycle/pending-request indicators.
