#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
swift build --package-path "$project_dir" -c debug

bin_dir=$(swift build --package-path "$project_dir" -c debug --show-bin-path)
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/voice-control-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
build_app="$package_dir/Voice Control Prototype.app"
installed_app="$HOME/Applications/Voice Control Prototype.app"
contents_dir="$build_app/Contents"
macos_dir="$contents_dir/MacOS"

mkdir -p "$macos_dir"
cp -f "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp -f "$bin_dir/VoiceControlDaemon" "$macos_dir/VoiceControlDaemon"
codesign --force --sign - \
  --requirements '=designated => identifier "com.daverapin.voice-control-prototype"' \
  "$build_app" >/dev/null

if pgrep -x VoiceControlDaemon >/dev/null; then
  pkill -TERM -x VoiceControlDaemon
  for _ in {1..50}; do
    if ! pgrep -x VoiceControlDaemon >/dev/null; then
      break
    fi
    sleep 0.1
  done
fi

if pgrep -x VoiceControlDaemon >/dev/null; then
  echo "VoiceControlDaemon did not stop; refusing to launch a duplicate" >&2
  exit 1
fi

mkdir -p "$(dirname "$installed_app")"
ditto "$build_app" "$installed_app"
codesign --force --sign - \
  --requirements '=designated => identifier "com.daverapin.voice-control-prototype"' \
  "$installed_app" >/dev/null

rm -rf "$package_dir"
trap - EXIT
exec open --wait-apps "$installed_app" --args "$@"
