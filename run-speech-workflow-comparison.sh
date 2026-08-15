#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
swift build --package-path "$project_dir" -c release --product SpeechWorkflowComparisonProbe

bin_dir=$(swift build --package-path "$project_dir" -c release --show-bin-path)
app_dir="$project_dir/.build/SpeechWorkflowComparisonProbe.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"

mkdir -p "$macos_dir"
cp -f "$project_dir/SpeechWorkflowComparisonInfo.plist" "$contents_dir/Info.plist"
cp -f "$bin_dir/SpeechWorkflowComparisonProbe" "$macos_dir/SpeechWorkflowComparisonProbe"
codesign --force --sign - \
  --requirements '=designated => identifier "com.daverapin.voice-control-speech-workflow-comparison"' \
  "$app_dir" >/dev/null

cd "$project_dir"
if [[ $# -eq 0 ]]; then
  set -- record
fi
exec "$macos_dir/SpeechWorkflowComparisonProbe" "$@"
