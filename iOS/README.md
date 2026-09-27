# iOS application boundary

Status: **Milestone 1 — the Xcode app target builds; the app has never been run.**

Xcode 26.6 (build 17F113) is installed at `~/Downloads/Xcode.app` and builds the app target and the
unit-test bundle against the real iPhoneOS 26.5 and iPhoneSimulator 26.5 SDKs. The app has **not**
been run anywhere: no iOS simulator runtime and no iOS 26.5 device support are installed, so
scheme + destination builds fail. There is no screenshot and no on-device evidence.

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
| `WatchBeatModels` | `ECGRecord`, `ECGMeasurement`, typed states (`ECGListState`, `ECGDetailState`, outcomes) | no | yes |
| `WatchBeatHealthKit` | `ECGHealthKitReading` (protocol), `LiveHealthKitECGReader`, `ECGHealthKitMapper`, `ECGRepository` | no | yes |
| `WatchBeatApp` | SwiftUI app: disclaimer, ECG list, ECG detail | yes | yes (real iOS 26.5 SDK; Mac Catalyst is not possible, that SDK has no Catalyst SwiftUI) |
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
    ECGList/               # metadata-only history list
    ECGDetail/             # lazily loaded voltage measurements + integrity facts
  Resources/               # Info.plist and entitlements, used by the Xcode app target
  Tests/                   # Swift Testing suites + fakes
  Package.swift            # SwiftPM build (unit tests, iOS SDK compile)
  WatchBeat.xcodeproj/     # Xcode app build (app + unit-test bundle)
```

Planned but not created yet: `Features/BeatDetail`, `Features/Settings`, `Features/ResearchMode`,
`Export/` (Milestones 2 and 8).

## HealthKit configuration

- `Resources/Info.plist` — `NSHealthShareUsageDescription` only. There is deliberately no
  `NSHealthUpdateUsageDescription`: the app never writes to Health. `PRODUCT_BUNDLE_IDENTIFIER` is
  the placeholder `com.watchbeat.WatchBeat`; replace it with your own bundle identifier before any
  signed or real-device build.
- `Resources/WatchBeatApp.entitlements` — `com.apple.developer.healthkit` only; no background
  delivery, no clinical-record access and no HealthKit write entitlement. Both App configurations
  use `CODE_SIGN_ENTITLEMENTS`, and the project declares the HealthKit system capability.
- The App target is iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
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

## Build and test on this host

Unit tests, run from the repository root (the script resolves the active toolchain itself):

```bash
bash Tools/run-app-tests.sh --parallel
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

`-target` is used instead of `-scheme` because a scheme build needs a destination, and this host has
neither an iOS simulator runtime nor iOS 26.5 device support. That makes `-scheme` builds fail with
`Unable to find a destination matching the provided destination specifier` and
`iOS 26.5 is not installed. Please download and install the platform from Xcode > Settings >
Components.` A successful unsigned `-target` build proves the app compiles, links and processes its
Info.plist. It does **not** prove that the entitlement is present in a signed product or that the app
runs. The repository now includes a shared `WatchBeatApp` scheme; it still needs a real destination.

Actual commands and results are recorded in [Docs/VALIDATION.md](../Docs/VALIDATION.md).

## Still required before Milestone 1 can be called validated

1. Re-run the corrected iPhone-only project on macOS and confirm `CODE_SIGN_ENTITLEMENTS` in
   `xcodebuild -showBuildSettings`.
2. Install the iOS 26.5 platform and a simulator runtime (Xcode > Settings > Components), then build
   and test the shared scheme on a real destination.
3. Run the app on a simulator and on a real iPhone, inspect the signed entitlement, and record the outcome.
4. Run the real-iPhone checklist in [NEEDS_MACOS_VALIDATION.md](../NEEDS_MACOS_VALIDATION.md).
