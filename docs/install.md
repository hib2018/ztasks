# Installation

Release archives contain a matching pair of executables:

```text
bin/ztasks
libexec/ztasks/ztasks-core
```

Install once into a user-owned prefix, then add its `bin` directory to `PATH`:

```sh
./scripts/install.sh install "$HOME/.local" ztasks-<version>-<os>-<arch>.tar.gz
export PATH="$HOME/.local/bin:$PATH"
```

No Go or Zig toolchain is required when installing a release archive. `ztasks` discovers the Core
relative to its own installed path and checks product, Protocol, and data compatibility before it
can mutate a Project. `ZTASKS_CORE` is an explicit diagnostic/development override.

Update atomically with `install.sh update PREFIX ARCHIVE`. Uninstall only the two known files with
`install.sh uninstall PREFIX`. Each Project retains its own `.ztasks/` Runtime; one installation can
therefore serve any number of Projects without sharing Events or state between them.
