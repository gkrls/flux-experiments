#!/usr/bin/env bash
# Usage: ./openwebtext-prepare.sh /path/to/dir [--force] [--token-only]
#
# Directory layout (created automatically):
#   <dir>/
#     openwebtext/    ← raw .tar.xz inner archives (from Zenodo download)
#     parquet/        ← train/ and val/ Parquet shards
#     tokenized/      ← train.bin, val.bin (uint16 memmap)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 /path/to/openwebtext/dir [--force] [--token-only]" >&2
  exit 1
fi
BASE_DIR="$1"
shift

FORCE=0
TOKEN_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --force|--clean) FORCE=1 ;;
    --token-only)    TOKEN_ONLY=1 ;;
  esac
done

BASE_DIR="$(cd "$BASE_DIR" && pwd)"
ARCHIVE_DIR="$BASE_DIR/openwebtext"
PARQUET_DIR="$BASE_DIR/parquet"
TOKENIZ_DIR="$BASE_DIR/tokenized"

echo "[openwebtext-prepare] base_dir=$BASE_DIR"
echo "  archive_dir=$ARCHIVE_DIR"
echo "  parquet_dir=$PARQUET_DIR"
echo "  tokeniz_dir=$TOKENIZ_DIR"

# --- Parquet ---
if [ "$TOKEN_ONLY" -eq 1 ]; then
  echo "[openwebtext-to-parquet] SKIPPED (--token-only)"
elif [ "$FORCE" -eq 1 ] || ! { [ -d "$PARQUET_DIR/train" ] && [ -d "$PARQUET_DIR/val" ]; }; then
  echo "[openwebtext-to-parquet] ..."
  rm -rf "$PARQUET_DIR/train" "$PARQUET_DIR/val"
  python "$SCRIPT_DIR/openwebtext-to-parquet.py" \
    --arc_dir "$ARCHIVE_DIR" --out_dir "$PARQUET_DIR" --docs_per_shard 300000 --val_frac 0.01
else
  echo "[openwebtext-to-parquet] SKIPPED: parquet/train and parquet/val already exist"
fi

# --- Tokenize ---
if [ "$FORCE" -eq 1 ] || ! { [ -f "$TOKENIZ_DIR/train.bin" ] && [ -f "$TOKENIZ_DIR/val.bin" ]; }; then
  echo "[openwebtext-tokenize] ..."
  rm -rf "$TOKENIZ_DIR"
  python "$SCRIPT_DIR/openwebtext-tokenize.py" \
    --data "$PARQUET_DIR" --out "$TOKENIZ_DIR" --num_proc 24
else
  echo "[openwebtext-tokenize] SKIPPED: tokenized/train.bin and tokenized/val.bin already exist"
fi

echo "[openwebtext-prepare] done. Pass --data $TOKENIZ_DIR to the trainer."