# iOS application boundary

Status: **v0.3.0 UI source implemented; current simulator rebuild and tests are pending.**

Xcode 26.6 (build 17F113) is installed at `~/Downloads/Xcode.app` and builds the app target and the
unit-test bundle against the real iPhoneOS 26.5 and iPhoneSimulator 26.5 SDKs. A user-provided
2026-09-27 screenshot confirms the corrected App installs and runs on an iPhone 17 Pro simulator
with iOS 26.5. A later screenshot shows the previous v0.2.0 source rendering the full 15,000-sample
synthetic ECG, and the user reported that the test data looked correct. The exact command and the
shared scheme test action were not recorded, the current v0.3.0 UI has not been rebuilt, and there is
still no real-iPhone evidence.

A follow-up review corrected entitlement wiring, made the target iPhone-only, committed a shared
scheme and stabilized view-model ownership. Those corrections pass repository configuration tests
but have not yet been rebuilt with Xcode; the earlier target-build evidence predates them.

`xcode-select` on this host still points at `/Library/Developer/CommandLineTools`, so every
`xcodebuild` / `xcrun` command needs the developer directory explicitly:

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
# or permanently (needs sudo):
sudo xcode-select -s "$HOME/Downloads/Xcode.app/Contents/Developer"
```

## Modules

| Module | Contents | SwiftUI | Built for iOS 17 |
|---|---|---|---|
| `WatchBeatModels` | records, measurements, typed states, display downsampling, export encoding, synthetic tutorial | no | yes |
| `WatchBeatHealthKit` | `ECGHealthKitReading` (protocol), `LiveHealthKitECGReader`, `ECGHealthKitMapper`, `ECGRepository` | no | yes |
| `WatchBeatApp` | SwiftUI app: disclaimer, overview/data/settings tabs, language setting, ECG list/detail, waveform and share sheet | yes | yes (earlier source revision; current v0.3.0 changes await rebuild) |
| `WatchBeatAppTests` | Swift Testing suites for the mapper and repository states | no | yes (build) |

The same modules exist twice: as SwiftPM targets (`Package.swift`) and as Xcode targets
(`WatchBeat.xcodeproj`). The Xcode project compiles `../ECGCore/Sources` into an `ECGCore`
framework target instead of resolving the SwiftPM package, which keeps `import ECGCore` working.

## Source layout

```text
iOS/
  App/                     # @main entry, scene container, root routing
  Models/                  # platform-neutral app models and typed states
  HealthKit/               # the only HealthKit-touching module
  Features/
    Disclaimer/            # first-launch gate + reusable disclaimer text
    Overview/              # default summary and safe entry points
    ECGList/               # metadata-only history list
    ECGDetail/             # voltage data, waveform, export confirmation + system sharing
    Settings/              # in-app language selection
  Resources/               # Info.plist and entitlements, used by the Xcode app target
  Tests/                   # Swift Testing suites + fakes
  Package.swift            # SwiftPM build (unit tests, iOS SDK compile)
  WatchBeat.xcodeproj/     # Xcode app build (app + unit-test bundle)
```

Planned but not created yet: `Features/BeatDetail` and `Features/ResearchMode`.

Every build includes one deterministic mathematical ECG example so the interface is learnable
without Apple Watch data. It is not routed through HealthKit and is identified as synthetic in the
screen, exported JSON and filenames. Known R-peak positions from its generating equation are used to
label every synthetic R–R interval in milliseconds. It is not validation data or a peak-detector result.

## HealthKit configuration

- `Resources/Info.plist` — `NSHealthShareUsageDescription` only. There is deliberately no
  `NSHealthUpdateUsageDescription`: the app never writes to Health. `PRODUCT_BUNDLE_IDENTIFIER` is
  the placeholder `com.watchbeat.WatchBeat`; replace it with your own bundle identifier before any
  signed or real-device build.
- `Resources/WatchBeatApp.entitlements` — `com.apple.developer.healthkit` only; no background
  delivery, no clinical-record access and no HealthKit write entitlement. Both App configurations
  use `CODE_SIGN_ENTITLEMENTS`, and the project declares the HealthKit system capability.
- The App target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
- `ECGCore`, `WatchBeatModels` and `WatchBeatHealthKit` each have a unique
  `PRODUCT_BUNDLE_IDENTIFIER`; otherwise the embedded framework plist is invalid at App validation.
- `LiveHealthKitECGReader.requestReadOnlyAuthorization()` calls
  `requestAuthorization(toShare: [], read: [HKObjectType.electrocardiogramType()])`. The `toShare`
  set is always empty.
- No network, analytics, crash upload, iCloud health container or background mode is configured.

## Invariants enforced in this target

- Measurement order, timestamps and missing lead values survive mapping untouched.
- `.appleWatchSimilarToLeadI` voltage is converted to mV exactly once, in `ECGHealthKitMapper`.
- Empty query result becomes `noAccessibleRecords`, never "read denied": HealthKit exposes no
  reliable read-denial state.
- Measurement incompleteness (`declaredCountMismatch`, `missingLeadVoltage`,
  `nonIncreasingTimeOrder`, `nonFiniteValue`) is reported separately from query failure.
- Every load takes a generation number, so a stale or cancelled request cannot overwrite a newer
  selection.
- `HKElectrocardiogram` objects stay inside `LiveHealthKitECGReader`; sample UUIDs are in-memory
  keys only and are never logged, persisted, or exported.
- Display downsampling never replaces the full-resolution signal used by raw export and future analysis.
- Real HealthKit waveforms do not receive R–R labels until a detector has been benchmarked and validated.
- Export requires a user action and confirmation; temporary files are protected and removed after sharing.

## Build and test on this host

Unit tests, run from the repository root (the script resolves the active toolchain itself):

```bash
bash Tools/run-app-tests.sh --parallel  # current source should run 25 tests
```

SwiftPM builds:

```bash
cd iOS
swift build                                              # macOS target: everything, incl. SwiftUI
swift build --triple arm64-apple-ios17.0 \
            --sdk "$(xcrun --sdk iphoneos --show-sdk-path)"          # real iOS SDK, device
swift build --triple x86_64-apple-ios17.0-simulator \
            --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)"   # real iOS SDK, simulator
```

Xcode app build (Xcode 26.6, build 17F113):

```bash
export DEVELOPER_DIR="$HOME/Downloads/Xcode.app/Contents/Developer"
cd iOS
xcodebuild -project WatchBeat.xcodeproj -list
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -configuration Debug -sdk iphonesimulator26.5 -arch x86_64 \
           CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatAppTests \
           -configuration Debug -sdk iphonesimulator26.5 -arch x86_64 \
           CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WatchBeat.xcodeproj -target WatchBeatApp \
           -configuration Debug -sdk iphoneos26.5 -arch arm64 \
           CODE_SIGNING_ALLOWED=NO build
```

These `-target` commands are retained as historical SDK-compile checks. A simulator destination is
now installed and the App has launched, so current validation must use the shared scheme:

```bash
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' build
xcodebuild -project WatchBeat.xcodeproj -scheme WatchBeatApp \
           -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' test
```

The exact current-revision command/output is still pending. Simulator success cannot prove that HealthKit is
present in a signed real-device product.

Actual commands and results are recorded in [Docs/VALIDATION.md](../Docs/VALIDATION.md).

## Still required before Milestone 1 can be called validated

1. Build and test the current v0.3.0 source through the shared scheme on the installed simulator.
2. Check the default Overview, all three tabs, immediate language switching, and the synthetic
   waveform's per-beat millisecond labels; recheck zoom/scroll and both share-sheet exports.
3. Run on a real iPhone, inspect the signed entitlement, and record the outcome.
4. Complete the real-iPhone checklist in [NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md).
