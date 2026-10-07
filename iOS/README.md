# iOS application boundary

Status: **v0.5.0 (6) MVP** — complete iPhone waveform-to-result App, configured for automatic
signing, Archive and real-device installation. Choose a developer Team and unique Bundle ID, then use
the shared `WatchBeatApp` scheme; see `../Docs/IPHONE_INSTALL.md`. This revision was cleaned up on
Windows and still needs its Xcode build/test run; follow `../NEEDS_MACOS_VALIDATION.md`.

Build 6 adds an analysis-time row for on-device speed checks, a synthetic example containing one
PAC-like and one PVC-like beat (detected by the model, not injected), and removes unused scaffolding.

The current source also adds recording trends and analysis coverage to Overview, combined date /
result / tag / note filtering to Data, and protected local symptom/tag/note annotations to each ECG
detail. History queries now return all accessible metadata. The new Swift tests and Swift Charts UI
still need macOS/Xcode validation; see the 2026-10-07 checklist in `../NEEDS_MACOS_VALIDATION.md`.

Actual commands and results are recorded in [Docs/VALIDATION.md](../Docs/VALIDATION.md).

## Still required before the current revision can be called device-validated

1. Build and test the current v0.5.0 (6) source through the shared scheme on the installed simulator.
2. Check the default Overview, all three tabs, immediate language switching, high-contrast Data
   cards and screening badges, plus the synthetic waveform's millisecond labels, scrolling seconds
   axis and exact red candidate times; recheck zoom/scroll and all three share-sheet exports.
3. Select a Team/unique Bundle ID, package and install on a real iPhone, inspect the signed entitlement,
   then record the HealthKit → waveform → analysis result outcome.
4. Complete the real-iPhone checklist in [NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md).
