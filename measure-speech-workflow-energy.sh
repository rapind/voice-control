#!/usr/bin/env bash
set -euo pipefail

project_dir=$(cd "$(dirname "$0")" && pwd)
if [[ $# -ge 1 ]]; then
  manifest=$1
else
  manifests=("$project_dir"/.build/speech-workflow-comparison/airpods-*/manifest.json)
  if [[ ! -e "${manifests[0]}" ]]; then
    echo "No AirPods corpus manifest found" >&2
    exit 1
  fi
  manifest=${manifests[$((${#manifests[@]} - 1))]}
fi
manifest=$(cd "$(dirname "$manifest")" && pwd)/$(basename "$manifest")
output_dir="$(dirname "$manifest")/workflow-energy"
mkdir -p "$output_dir"

cat <<'EOF'
This measurement must run without builds, tests, video calls, or other sustained workloads.
System-wide CPU and ANE power cannot be attributed reliably while unrelated work is active.
Press Return when the Mac is otherwise idle, or Ctrl-C to stop.
EOF
read -r

swift build --package-path "$project_dir" -c release --product SpeechWorkflowComparisonProbe
bin_dir=$(swift build --package-path "$project_dir" -c release --show-bin-path)
binary="$bin_dir/SpeechWorkflowComparisonProbe"

"$binary" warmup apple "$manifest" >/dev/null
"$binary" warmup parakeet "$manifest" >/dev/null

sudo -v
metrics_pid=""
cleanup() {
  if [[ -n "$metrics_pid" ]]; then
    sudo kill -INT "$metrics_pid" 2>/dev/null || true
    wait "$metrics_pid" 2>/dev/null || true
    metrics_pid=""
  fi
}
trap cleanup EXIT INT TERM

collect() {
  local name=$1
  shift
  local output_file="$output_dir/$name.txt"
  echo "Collecting $name power metrics..."
  sudo /usr/bin/powermetrics \
    --sample-rate 500 \
    --sample-count -1 \
    --samplers tasks,battery,cpu_power,ane_power \
    --show-process-energy \
    --show-usage-summary \
    --buffer-size 1 \
    --output-file "$output_file" &
  metrics_pid=$!
  sleep 1
  "$@"
  cleanup
}

collect baseline /bin/sleep 60
collect apple "$binary" stress apple "$manifest" 1
collect parakeet "$binary" stress parakeet "$manifest" 1

echo "Workflow energy reports written to $output_dir"
