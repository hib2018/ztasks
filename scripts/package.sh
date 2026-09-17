#!/bin/sh
set -eu

target_os=${1:-$(go env GOOS)}
target_arch=${2:-$(go env GOARCH)}
version=${ZTASKS_VERSION:-0.1.0-dev}
case "$target_os/$target_arch" in
  darwin/amd64) zig_target=x86_64-macos ;;
  darwin/arm64) zig_target=aarch64-macos ;;
  linux/amd64) zig_target=x86_64-linux ;;
  linux/arm64) zig_target=aarch64-linux ;;
  *) echo "unsupported target: $target_os/$target_arch" >&2; exit 2 ;;
esac

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
stage_dir=$(mktemp -d)
trap 'rm -rf "$stage_dir"' EXIT HUP INT TERM
archive_root="ztasks-$version-$target_os-$target_arch"
mkdir -p "$stage_dir/$archive_root/bin" "$stage_dir/$archive_root/libexec/ztasks"

(cd "$repo_dir/app" && GOCACHE="$repo_dir/.go-build-cache" GOOS="$target_os" GOARCH="$target_arch" CGO_ENABLED=0 go build -trimpath -o "$stage_dir/$archive_root/bin/ztasks" ./cmd/ztasks)
(cd "$repo_dir" && ZIG_GLOBAL_CACHE_DIR="$repo_dir/.zig-global-cache" zig build --build-file core/build.zig --cache-dir .zig-cache -Doptimize=ReleaseSafe -Dtarget="$zig_target")
cp "$repo_dir/core/zig-out/bin/ztasks-core" "$stage_dir/$archive_root/libexec/ztasks/ztasks-core"

mkdir -p "$repo_dir/dist"
archive="$repo_dir/dist/$archive_root.tar.gz"
tar -C "$stage_dir" -czf "$archive" "$archive_root"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$archive" > "$archive.sha256"
else
  shasum -a 256 "$archive" > "$archive.sha256"
fi
printf '%s\n' "$archive"
