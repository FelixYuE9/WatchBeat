#!/usr/bin/env bash
set -euo pipefail

if (( $# > 1 )); then
  echo "Usage: bash Tools/run-peakswift-vote-bxb-development.sh [peakswift-development-run-dir]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
VALIDATION_DIR="$REPOSITORY_ROOT/Tools/Validation"
MANIFEST="$VALIDATION_DIR/output/mitdb-rpeak-manifest-v1.json"

if (( $# == 1 )); then
  RUN_DIR="$(cd -- "$1" && pwd)"
else
  shopt -s nullglob
  candidates=()
  for prediction in "$VALIDATION_DIR"/output/peakswift-development-*/peakswift-neurokit-development-predictions.json; do
    candidate="$(dirname -- "$prediction")"
    if [[ -f "$candidate/peakswift-pan-tompkins-development-predictions.json" &&
          -f "$candidate/peakswift-kalidas-development-predictions.json" ]]; then
      candidates+=("$candidate")
    fi
  done
  if (( ${#candidates[@]} != 1 )); then
    echo "Expected one complete PeakSwift development run; found ${#candidates[@]}." >&2
    printf 'Candidate directory: %s\n' "${candidates[@]}" >&2
    echo "Pass the desired run directory as the single argument." >&2
    exit 2
  fi
  RUN_DIR="${candidates[0]}"
fi

for algorithm in neurokit pan-tompkins kalidas; do
  if [[ ! -f "$RUN_DIR/peakswift-$algorithm-development-predictions.json" ||
        ! -f "$RUN_DIR/peakswift-$algorithm-development-report.json" ]]; then
    echo "Missing $algorithm prediction or report in $RUN_DIR" >&2
    exit 2
  fi
done
if [[ ! -f "$MANIFEST" ]]; then
  echo "Frozen development manifest is missing: $MANIFEST" >&2
  exit 2
fi

VOTE_PREDICTIONS="$RUN_DIR/peakswift-vote-2of3-100ms-development-predictions.json"
VOTE_REPORT="$RUN_DIR/peakswift-vote-2of3-100ms-development-report.json"

python3 "$VALIDATION_DIR/vote_r_peak_predictions.py" \
  "$MANIFEST" \
  "$RUN_DIR/peakswift-neurokit-development-predictions.json" \
  "$RUN_DIR/peakswift-pan-tompkins-development-predictions.json" \
  "$RUN_DIR/peakswift-kalidas-development-predictions.json" \
  --min-votes 2 --alignment-tolerance-ms 100 --output "$VOTE_PREDICTIONS"

python3 "$VALIDATION_DIR/evaluate_r_peaks.py" \
  "$MANIFEST" "$VOTE_PREDICTIONS" --split development --output "$VOTE_REPORT"

python3 "$VALIDATION_DIR/compare_r_peak_reports.py" \
  "$RUN_DIR/peakswift-neurokit-development-report.json" \
  "$RUN_DIR/peakswift-pan-tompkins-development-report.json" \
  "$RUN_DIR/peakswift-kalidas-development-report.json" \
  "$VOTE_REPORT" --split development \
  --output-json "$RUN_DIR/vote-2of3-100ms-comparison.json" \
  --output-markdown "$RUN_DIR/vote-2of3-100ms-comparison.md"

bash "$SCRIPT_DIR/run-bxb-development-crosscheck.sh" "$VOTE_PREDICTIONS"
