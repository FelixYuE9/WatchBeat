#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$REPOSITORY_ROOT/Tools/PeakSwiftBenchmark"
VALIDATION_DIR="$REPOSITORY_ROOT/Tools/Validation"
DATASET_DIR="$VALIDATION_DIR/data/mitdb-1.0.0"
MANIFEST_PATH="$VALIDATION_DIR/output/mitdb-rpeak-manifest-v1.json"

ALL_ALGORITHMS=(
  christov
  nabian2018
  hamilton
  two-average
  neurokit
  pan-tompkins
  unsw
  engzee
  kalidas
)

if (( $# > 0 )); then
  ALGORITHMS=("$@")
else
  ALGORITHMS=("${ALL_ALGORITHMS[@]}")
fi

if (( ${#ALGORITHMS[@]} < 2 )); then
  echo "Development screening requires at least two algorithms." >&2
  exit 2
fi

for (( index=0; index<${#ALGORITHMS[@]}; index++ )); do
  algorithm="${ALGORITHMS[index]}"
  case "$algorithm" in
    christov|nabian2018|hamilton|two-average|neurokit|pan-tompkins|unsw|engzee|kalidas)
      ;;
    *)
      echo "Unsupported PeakSwift algorithm: $algorithm" >&2
      exit 2
      ;;
  esac
  for (( previous=0; previous<index; previous++ )); do
    if [[ "${ALGORITHMS[previous]}" == "$algorithm" ]]; then
      echo "Duplicate PeakSwift algorithm: $algorithm" >&2
      exit 2
    fi
  done
done

# PeakSwift v1.0.0 records wavelib with a GitHub SSH submodule URL. Keep this rewrite local to the
# process tree so no GitHub SSH key or global Git configuration change is required.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'
export GIT_CONFIG_VALUE_0='git@github.com:'

if [[ -d "$HOME/Downloads/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
fi

RUN_TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
HARNESS_REVISION="$(git -C "$REPOSITORY_ROOT" rev-parse --short HEAD 2>/dev/null || printf 'unknown')"

echo "Resolving the exact PeakSwift dependency lock..."
cd "$PACKAGE_DIR"
swift package resolve
cd "$REPOSITORY_ROOT"
python3 -m unittest discover -s Tools/Validation/tests \
  -p test_peakswift_benchmark_configuration.py -v

echo "Preparing checksum-verified MIT-BIH v1.0.0 data..."
python3 "$VALIDATION_DIR/download_mitdb.py" --workers 4
python3 "$VALIDATION_DIR/build_mitdb_manifest.py"

mkdir -p "$VALIDATION_DIR/output"
RUN_DIR="$(mktemp -d "$VALIDATION_DIR/output/peakswift-development-${RUN_TIMESTAMP}-${HARNESS_REVISION}-XXXXXX")"

REPORT_PATHS=()
FAILED_ALGORITHMS=()
REPORT_COUNT=0
FAILED_COUNT=0

for algorithm in "${ALGORITHMS[@]}"; do
  prediction_path="$RUN_DIR/peakswift-${algorithm}-development-predictions.json"
  report_path="$RUN_DIR/peakswift-${algorithm}-development-report.json"
  echo
  echo "=== Development screening: $algorithm ==="

  if swift run -c release --package-path "$PACKAGE_DIR" PeakSwiftBenchmark \
      --manifest "$MANIFEST_PATH" \
      --dataset-dir "$DATASET_DIR" \
      --algorithm "$algorithm" \
      --split development \
      --output "$prediction_path"; then
    if python3 "$VALIDATION_DIR/evaluate_r_peaks.py" \
        "$MANIFEST_PATH" \
        "$prediction_path" \
        --split development \
        --output "$report_path"; then
      REPORT_PATHS+=("$report_path")
      REPORT_COUNT=$((REPORT_COUNT + 1))
    else
      FAILED_ALGORITHMS+=("$algorithm:evaluator")
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi
  else
    FAILED_ALGORITHMS+=("$algorithm:runner")
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
done

if (( REPORT_COUNT < 2 )); then
  echo "Fewer than two detector reports succeeded; comparison was not produced." >&2
  printf 'Failed stages: %s\n' "${FAILED_ALGORITHMS[*]}" >&2
  exit 2
fi

python3 "$VALIDATION_DIR/compare_r_peak_reports.py" \
  "${REPORT_PATHS[@]}" \
  --split development \
  --output-json "$RUN_DIR/comparison.json" \
  --output-markdown "$RUN_DIR/comparison.md"

echo "Generated development-only artifacts in: $RUN_DIR"
if (( FAILED_COUNT > 0 )); then
  printf 'Incomplete algorithms: %s\n' "${FAILED_ALGORITHMS[*]}" >&2
  exit 2
fi

echo "All requested PeakSwift development candidates completed."
