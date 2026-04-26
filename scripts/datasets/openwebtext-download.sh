#!/usr/bin/env bash
# Usage: ./openwebtext-download.sh /path/to/dir

set -euo pipefail
URL="https://zenodo.org/records/3834942/files/openwebtext.tar.xz?download=1"
N_PARTS="${N_PARTS:-12}"
SPLIT_SIZE_MIN="${SPLIT_SIZE_MIN:-1M}"


TARGET_DIR="${1:-.}"
mkdir -p "$TARGET_DIR"

if ! command -v aria2c >/dev/null 2>&1; then
  sudo apt install -y aria2
fi

download() {
  local url="$1" out="$2"
  echo "$url -> $out"
  # -x/-s = connections, -k = min split size, -c = resume, -d/-o set dest
  aria2c -c -x"$N_PARTS" -s"$N_PARTS" -k"$SPLIT_SIZE_MIN" \
         -d "$(dirname "$out")" -o "$(basename "$out")" \
         "$url"
}

download "$URL" "$TARGET_DIR/openwebtext.tar.xz"