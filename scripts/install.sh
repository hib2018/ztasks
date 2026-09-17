#!/bin/sh
set -eu

action=${1:-}
prefix=${2:-}
archive=${3:-}
if [ -z "$action" ] || [ -z "$prefix" ]; then
  echo "usage: install.sh install|update|uninstall PREFIX [ARCHIVE]" >&2
  exit 2
fi
case "$prefix" in /|"$HOME"|"") echo "refusing broad installation prefix" >&2; exit 2 ;; esac

frontend="$prefix/bin/ztasks"
core="$prefix/libexec/ztasks/ztasks-core"
case "$action" in
  install|update)
    [ -n "$archive" ] || { echo "archive is required" >&2; exit 2; }
    stage_dir=$(mktemp -d)
    trap 'rm -rf "$stage_dir"' EXIT HUP INT TERM
    tar -C "$stage_dir" -xzf "$archive"
    package_dir=$(find "$stage_dir" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    [ -x "$package_dir/bin/ztasks" ] && [ -x "$package_dir/libexec/ztasks/ztasks-core" ] || { echo "invalid ztasks archive" >&2; exit 2; }
    mkdir -p "$prefix/bin" "$prefix/libexec/ztasks"
    install -m 0755 "$package_dir/bin/ztasks" "$frontend.new"
    install -m 0755 "$package_dir/libexec/ztasks/ztasks-core" "$core.new"
    mv "$core.new" "$core"
    mv "$frontend.new" "$frontend"
    ;;
  uninstall)
    rm -f "$frontend" "$core"
    ;;
  *) echo "unknown action: $action" >&2; exit 2 ;;
esac
