#!/usr/bin/env bash
set -euo pipefail

if (( $# != 1 )); then
  echo "Usage: bash Tools/run-bxb-development-crosscheck.sh <development-predictions.json>" >&2
  exit 2
fi

for command_name in python3 wrann rdann bxb; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command is unavailable: $command_name" >&2
    exit 2
  fi
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VALIDATION_DIR="$REPOSITORY_ROOT/Tools/Validation"
DATASET_DIR="$VALIDATION_DIR/data/mitdb-1.0.0"
MANIFEST="$VALIDATION_DIR/output/mitdb-rpeak-manifest-v1.json"
PREDICTIONS="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$1")"

if [[ ! -f "$PREDICTIONS" || ! -f "$MANIFEST" || ! -d "$DATASET_DIR" ]]; then
  echo "Predictions, frozen manifest, or checksum-verified MIT-BIH data are missing." >&2
  exit 2
fi

python3 "$VALIDATION_DIR/build_mitdb_manifest.py"

mkdir -p "$VALIDATION_DIR/output"
RUN_DIR="$(mktemp -d "$VALIDATION_DIR/output/bxb-development-XXXXXXXX")"
python3 "$VALIDATION_DIR/prepare_bxb_crosscheck.py" prepare \
  "$MANIFEST" "$PREDICTIONS" --output-dir "$RUN_DIR"

while IFS=$'\t' read -r record stop_time; do
  for extension in hea dat atr; do
    source_path="$DATASET_DIR/$record.$extension"
    if [[ ! -f "$source_path" ]]; then
      echo "Missing MIT-BIH file: $source_path" >&2
      exit 2
    fi
    ln -s "$source_path" "$RUN_DIR/$record.$extension"
  done
done < "$RUN_DIR/records.tsv"

cd "$RUN_DIR"
while IFS=$'\t' read -r record stop_time; do
  wrann -r "$record" -a vot < "$record.input.rdann.txt"
  rdann -r "$record" -a vot -f 0 > "$record.roundtrip.rdann.txt"
done < "$RUN_DIR/records.tsv"

python3 "$VALIDATION_DIR/prepare_bxb_crosscheck.py" verify --output-dir "$RUN_DIR"

while IFS=$'\t' read -r record stop_time; do
  bxb -r "$record" -a atr vot -f 0 -t "$stop_time" -s - > "$record.bxb.txt"
  if [[ ! -s "$record.bxb.txt" ]]; then
    echo "WFDB bxb produced an empty report for record $record" >&2
    exit 2
  fi
done < "$RUN_DIR/records.tsv"

echo "Official WFDB bxb record reports are in: $RUN_DIR"
echo "These are a cross-check, not a production detector result."
