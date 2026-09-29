# Package and run on a real iPhone

WatchBeat v0.5.0 (6) is an iPhone application project, not a UI prototype: the shared Xcode scheme
builds an archiveable `.app`, automatic signing is enabled, the HealthKit capability and read-purpose
string are wired, and all runtime frameworks are embedded and signed with the App. After choosing a
development team and a unique bundle identifier, it can be packaged and installed on a real iPhone.

## One-time signing setup

1. On a Mac with Xcode, open `iOS/WatchBeat.xcodeproj`.
2. Select target **WatchBeatApp** → **Signing & Capabilities**.
3. Keep **Automatically manage signing** enabled, select your Apple Developer team, and replace
   `com.watchbeat.WatchBeat` with a bundle identifier owned by that team.
4. Confirm that **HealthKit** is still listed under Signing & Capabilities.
5. Connect an iPhone running iOS 17 or later, unlock it, trust the Mac, and enable Developer Mode if
   Xcode asks for it.

Signing identities, provisioning profiles, device identifiers and personal team IDs must stay out of
Git. The repository intentionally does not hard-code them.

## Install and run

Select the connected iPhone as the `WatchBeatApp` run destination and press **Run**. Xcode builds,
signs and installs the App. A release archive can also be produced with **Product → Archive** or:

```bash
cd iOS
xcodebuild -project WatchBeat.xcodeproj \
  -scheme WatchBeatApp \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$PWD/build/WatchBeat.xcarchive" \
  archive \
  DEVELOPMENT_TEAM='<your-team-id>' \
  PRODUCT_BUNDLE_IDENTIFIER='<your-unique-bundle-id>'
```

The command-line overrides are local build inputs; do not commit their values. Xcode's **Run** action
is the simplest way to install a development build. Distribution outside registered development
devices needs the matching Apple distribution method and provisioning profile.

## End-to-end flow on the phone

1. Accept the research disclaimer.
2. Open **Data**. The built-in synthetic record is always available and immediately runs through the
   same `watchbeat.ecg.signal.v1` analyzer as a HealthKit record.
3. Under Apple Health, request read-only ECG access. The App requests no write type.
4. After metadata appears, the Data page screens records one by one on device and shows a compact
   research badge on each row. This starts only after Data is opened and does not persist raw voltage.
5. Open an Apple Watch ECG. The App reads every Lead-I-like voltage measurement, converts it once to
   millivolts, preserves its timestamp/index, and passes that exact `ECGSignal` to the local classifier.
6. The detail screen shows model-derived R peaks/R–R intervals, a scrolling seconds axis, exact
   candidate times and the versioned research result. A
   refused input shows an explicit reason instead of a fabricated classification.
7. **Share analysis JSON** exports `ECGAnalysisReport` v1; **Share raw CSV** exports the exact model
   input as `time_s,voltage_mV`. Both synthetic and HealthKit data use these same contracts.

All analysis runs locally. The current RR-only model marks `prematureUncertain` candidates and does
not claim PAC/PVC subtype diagnosis. Packaging/installability is separate from medical validation;
record the real-device checks in `NEEDS_MACOS_VALIDATION.md` before making accuracy claims.
