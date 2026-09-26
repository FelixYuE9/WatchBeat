# Private validation data — do not commit

This directory is reserved for ECG data that the user is authorized to use and
that has been appropriately de-identified. Its contents are ignored by Git,
except for this note.

- Never place personal ECG data in issues, pull requests, logs, or screenshots.
- Keep provenance, consent, annotation protocol, and dataset version beside the
  private data, but do not publish them if they contain identifying information.
- Do not use the same records for per-case threshold tuning and final evaluation.
- Before sharing any derived artifact, check whether it can reveal timestamps,
  identifiers, or recognizable waveform data.
