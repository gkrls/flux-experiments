#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REMOTE_PATH=""
OUT_DIR=""
IGNORE=""
PREFIX=""
SHORT=0
HOSTS_FILE="${SCRIPT_DIR}/hosts.txt"

usage() {
  cat <<EOF
Usage: $(basename "$0") <remote_path> [-o <out_dir>] [-f <hosts_file>] [--prefix <tag>] [--ignore <r1,r2,...>] [--short]

Collect a file from every cluster node, saving them under a directory

  <remote_path>  Remote file path to collect (positional, required)
  -f             Hosts file, one hostname per line  [default: hosts.txt next to script]
  -o             Local output directory  [default: $PWD/files-<timestamp>]
  --prefix       Filename prefix tag     [default: none]
  --ignore       Comma-separated ranks to skip
  --short        Name output files as rank<N>.<ext> instead of rank<N>_<filename>.<ext>
EOF
  exit 1
}

# Args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)       HOSTS_FILE="$2"; shift 2 ;;
    -o)       OUT_DIR="$2";    shift 2 ;;
    --prefix) PREFIX="$2";     shift 2 ;;
    --ignore) IGNORE="$2";     shift 2 ;;
    --short)  SHORT=1;         shift ;;
    -h|--help) usage ;;
    -*)       echo "Unknown flag: $1"; usage ;;
    *)        REMOTE_PATH="$1"; shift ;;
  esac
done

[[ -z "$REMOTE_PATH" ]] && { echo "Error: remote path is required"; usage; }
[[ ! -f "$HOSTS_FILE" ]] && { echo "Error: hosts file '$HOSTS_FILE' not found"; exit 1; }

# load hosts, skip blank lines etc
mapfile -t HOSTS < <(sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d; s/^[[:space:]]*//' "$HOSTS_FILE")
[[ ${#HOSTS[@]} -eq 0 ]] && { echo "Error: no hosts in $HOSTS_FILE"; exit 1; }

OUT_DIR="${OUT_DIR:-files-$(date +%Y%m%d_%H%M%S)}"
mkdir -p "$OUT_DIR"

# build skip set
declare -A SKIP=()
if [[ -n "$IGNORE" ]]; then
  IFS=',' read -ra _skip <<< "$IGNORE"
  for s in "${_skip[@]}"; do SKIP[$s]=1; done
fi

# collect files
BASENAME="$(basename "$REMOTE_PATH")"
EXT="${BASENAME##*.}"
OK=0; FAIL=0

for rank in "${!HOSTS[@]}"; do
  host="${HOSTS[$rank]}"

  if [[ -n "${SKIP[$rank]+_}" ]]; then
    echo "[rank $rank] SKIP  $host"
    continue
  fi

  tag="${PREFIX:+${PREFIX}_}"
  if [[ $SHORT -eq 1 ]]; then
    dest="${OUT_DIR}/${tag}rank${rank}.${EXT}"
  else
    dest="${OUT_DIR}/${tag}rank${rank}_${BASENAME}"
  fi
  printf "[rank %d] %s:%s → %s ... " "$rank" "$host" "$REMOTE_PATH" "$dest"

  if scp -q "$host:$REMOTE_PATH" "$dest" 2>/dev/null; then
    echo "OK";   ((++OK))
  else
    echo "FAIL"; ((++FAIL))
  fi
done

echo ""
echo "Done: $OK collected, $FAIL failed, ${#SKIP[@]} skipped → $OUT_DIR/"
ls -lh "$OUT_DIR/" 2>/dev/null || echo "  (none)"