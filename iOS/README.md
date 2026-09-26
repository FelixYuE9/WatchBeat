# iOS application boundary

The Xcode project is intentionally not generated in Milestone 0 because this workstation has neither
macOS nor Xcode. Hand-writing an unbuildable `.xcodeproj` would not satisfy the product's truthfulness
requirements.

When a macOS/Xcode environment is available, create the project here with this logical source layout:

```text
iOS/
  App/
  Models/
  HealthKit/
  Features/
    ECGList/
    ECGDetail/
    BeatDetail/
    Settings/
    ResearchMode/
  Export/
  Tests/
```

The iOS target imports the local `../ECGCore` package. HealthKit objects stop at the mapper boundary;
`ECGCore` never imports HealthKit or SwiftUI. Follow `NEEDS_MACOS_VALIDATION.md` before marking any
reader acceptance criterion complete.
