#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
swift build --package-path "$project_dir" -c debug

bin_dir=$(swift build --package-path "$project_dir" -c debug --show-bin-path)
package_dir=$(mktemp -d "${TMPDIR:-/tmp}/voice-control-package.XXXXXX")
trap 'rm -rf "$package_dir"' EXIT
build_app="$package_dir/Voice Control Prototype.app"
installed_app="$HOME/Applications/Voice Control Prototype.app"
installed_executable="$installed_app/Contents/MacOS/VoiceControlDaemon"
launch_agent_label="com.daverapin.voice-control-prototype"
launch_agent="$HOME/Library/LaunchAgents/$launch_agent_label.plist"
launch_agent_template="$project_dir/$launch_agent_label.plist.template"
launch_agent_build="$package_dir/$launch_agent_label.plist"
launch_agent_log="$HOME/Library/Logs/VoiceControlPrototype.launchagent.log"
launch_domain="gui/$(id -u)"
contents_dir="$build_app/Contents"
macos_dir="$contents_dir/MacOS"

mkdir -p "$macos_dir"
cp -f "$project_dir/Info.plist" "$contents_dir/Info.plist"
cp -f "$bin_dir/VoiceControlDaemon" "$macos_dir/VoiceControlDaemon"
codesign --force --sign - \
  --requirements '=designated => identifier "com.daverapin.voice-control-prototype"' \
  "$build_app" >/dev/null

launchctl bootout "$launch_domain/$launch_agent_label" 2>/dev/null || true

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

cp -f "$launch_agent_template" "$launch_agent_build"
/usr/libexec/PlistBuddy \
  -c "Set :ProgramArguments:0 $installed_executable" \
  "$launch_agent_build"
argument_index=1
for argument in "$@"; do
  /usr/libexec/PlistBuddy \
    -c "Add :ProgramArguments:$argument_index string $argument" \
    "$launch_agent_build"
  argument_index=$((argument_index + 1))
done
/usr/libexec/PlistBuddy \
  -c "Set :StandardErrorPath $launch_agent_log" \
  "$launch_agent_build"
/usr/libexec/PlistBuddy \
  -c "Set :StandardOutPath $launch_agent_log" \
  "$launch_agent_build"
plutil -lint "$launch_agent_build" >/dev/null
mkdir -p "$(dirname "$launch_agent")" "$(dirname "$launch_agent_log")"
install -m 0644 "$launch_agent_build" "$launch_agent"

launchctl bootstrap "$launch_domain" "$launch_agent"
for _ in {1..50}; do
  if pgrep -x VoiceControlDaemon >/dev/null; then
    break
  fi
  sleep 0.1
done

if ! pgrep -x VoiceControlDaemon >/dev/null; then
  echo "VoiceControlDaemon did not start under launchd" >&2
  launchctl print "$launch_domain/$launch_agent_label" >&2 || true
  exit 1
fi

rm -rf "$package_dir"
trap - EXIT
echo "Voice Control Prototype rebuilt and running under launchd"
