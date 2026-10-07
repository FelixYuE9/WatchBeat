from __future__ import annotations

import json
import plistlib
import struct
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).resolve().parents[3]
IOS_ROOT = REPOSITORY_ROOT / "iOS"
PROJECT_FILE = IOS_ROOT / "WatchBeat.xcodeproj" / "project.pbxproj"
SCHEME_FILE = (
    IOS_ROOT
    / "WatchBeat.xcodeproj"
    / "xcshareddata"
    / "xcschemes"
    / "WatchBeatApp.xcscheme"
)


class IOSProjectConfigurationTests(unittest.TestCase):
    def test_healthkit_entitlement_is_wired_to_code_signing(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")

        self.assertNotIn("CODE_ENTITLEMENTS", project)
        self.assertEqual(
            project.count(
                "CODE_SIGN_ENTITLEMENTS = Resources/WatchBeatApp.entitlements;"
            ),
            2,
        )
        self.assertIn(
            "com.apple.HealthKit = {\n\t\t\t\t\t\t\t\tenabled = 1;",
            project,
        )

        with (IOS_ROOT / "Resources" / "WatchBeatApp.entitlements").open("rb") as file:
            entitlements = plistlib.load(file)
        self.assertIs(entitlements.get("com.apple.developer.healthkit"), True)

    def test_app_target_is_iphone_only(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")

        self.assertEqual(project.count("TARGETED_DEVICE_FAMILY = 1;"), 2)
        self.assertNotIn('TARGETED_DEVICE_FAMILY = "1,2";', project)

    def test_app_icon_is_opaque_1024_asset_and_wired_to_target(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        asset_root = IOS_ROOT / "Resources" / "Assets.xcassets"
        app_icon_set = asset_root / "AppIcon.appiconset"

        contents = json.loads((app_icon_set / "Contents.json").read_text(encoding="utf-8"))
        image_entry = contents["images"][0]
        self.assertEqual(image_entry["idiom"], "universal")
        self.assertEqual(image_entry["platform"], "ios")
        self.assertEqual(image_entry["size"], "1024x1024")

        png = (app_icon_set / image_entry["filename"]).read_bytes()
        self.assertEqual(png[:8], b"\x89PNG\r\n\x1a\n")
        self.assertEqual(png[12:16], b"IHDR")
        width, height, bit_depth, color_type = struct.unpack(">IIBB", png[16:26])
        self.assertEqual((width, height, bit_depth), (1024, 1024, 8))
        self.assertEqual(color_type, 2, "App Store icon must not contain an alpha channel")

        self.assertIn("/* Assets.xcassets in Resources */", project)
        self.assertIn("/* Resources */ = {", project)
        self.assertEqual(
            project.count("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;"),
            2,
        )

    def test_embedded_frameworks_have_unique_bundle_identifiers(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        framework_identifiers = {
            "com.watchbeat.WatchBeat.ECGCore",
            "com.watchbeat.WatchBeat.Models",
            "com.watchbeat.WatchBeat.HealthKit",
        }

        for identifier in framework_identifiers:
            self.assertEqual(
                project.count(f"PRODUCT_BUNDLE_IDENTIFIER = {identifier};"),
                2,
            )

    def test_embedded_frameworks_load_from_rpath_on_device(self) -> None:
        # Without an @rpath install name, frameworks default to /Library/Frameworks and the App
        # aborts in dyld on a real iPhone (the simulator hides this via DYLD_FRAMEWORK_PATH).
        project = PROJECT_FILE.read_text(encoding="utf-8")

        self.assertEqual(project.count('DYLIB_INSTALL_NAME_BASE = "@rpath";'), 6)
        self.assertEqual(
            project.count('INSTALL_PATH = "$(LOCAL_LIBRARY_DIR)/Frameworks";'), 6
        )
        self.assertEqual(project.count('"@executable_path/Frameworks",'), 10)

    def test_shared_scheme_builds_app_and_runs_tests(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        scheme = ET.parse(SCHEME_FILE).getroot()
        references = scheme.findall(".//BuildableReference")
        blueprint_names = {reference.attrib["BlueprintName"] for reference in references}

        self.assertIn("WatchBeatApp", blueprint_names)
        self.assertIn("WatchBeatAppTests", blueprint_names)
        for reference in references:
            self.assertIn(reference.attrib["BlueprintIdentifier"], project)

        testable = scheme.find(
            "./TestAction/Testables/TestableReference/BuildableReference"
        )
        self.assertIsNotNone(testable)
        self.assertEqual(testable.attrib["BlueprintName"], "WatchBeatAppTests")

    def test_healthkit_usage_description_is_read_only(self) -> None:
        with (IOS_ROOT / "Resources" / "Info.plist").open("rb") as file:
            info = plistlib.load(file)

        self.assertTrue(info.get("NSHealthShareUsageDescription"))
        self.assertNotIn("NSHealthUpdateUsageDescription", info)

    def test_shipping_sources_are_members_of_xcode_targets(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        source_files = {
            "PrematureBeatAnalyzer.swift",
            "ECGAnalysisReport.swift",
            "GradientEnergyRPeakDetector.swift",
            "ECGQRSAmplitude.swift",
            "ECGDisplay.swift",
            "ECGExportEncoder.swift",
            "ECGExampleFactory.swift",
            "ECGWaveformView.swift",
            "ECGCaliperView.swift",
            "ECGAnalysisResultView.swift",
            "ECGExportSharing.swift",
            "ECGPresentationAndExportTests.swift",
            "AppLanguage.swift",
            "AppStyle.swift",
            "AppHomeView.swift",
            "OverviewView.swift",
            "SettingsView.swift",
            "ECGAnnotation.swift",
            "ECGAnnotationStore.swift",
            "ECGRecordInsights.swift",
            "ECGRecordFilterView.swift",
            "ECGAnnotationView.swift",
            "ECGRecordInsightsTests.swift",
            "ECGInsightsTestSupport.swift",
        }

        for file_name in source_files:
            self.assertIn(f"/* {file_name} */", project)
            self.assertEqual(project.count(f"/* {file_name} in Sources */"), 2)

        tests_group = project[project.index("/* Tests */ = {") :]
        tests_group = tests_group[: tests_group.index("/* End PBXGroup section */")]
        self.assertIn("ECGPresentationAndExportTests.swift", tests_group)

        list_view = (IOS_ROOT / "Features" / "ECGList" / "ECGListView.swift").read_text(
            encoding="utf-8"
        )
        self.assertIn('language.text("Example ECG Data", "示例 ECG 数据")', list_view)
        self.assertNotIn("Explore built-in synthetic ECG", list_view)
        self.assertNotIn("查看内置合成心电示例", list_view)

    def test_release_is_configured_for_real_iphone_packaging(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        scheme = ET.parse(SCHEME_FILE).getroot()
        with (IOS_ROOT / "Resources" / "Info.plist").open("rb") as file:
            info = plistlib.load(file)

        self.assertEqual(project.count("CODE_SIGN_STYLE = Automatic;"), 2)
        self.assertEqual(project.count("TARGETED_DEVICE_FAMILY = 1;"), 2)
        archive_action = scheme.find("./ArchiveAction")
        self.assertIsNotNone(archive_action)
        self.assertEqual(archive_action.attrib["buildConfiguration"], "Release")
        self.assertEqual(info["CFBundleShortVersionString"], "0.5.0")
        self.assertEqual(info["CFBundleVersion"], "6")
        self.assertIs(info["LSRequiresIPhoneOS"], True)

    def test_healthkit_and_synthetic_measurements_share_analysis_contract(self) -> None:
        measurement = (IOS_ROOT / "Models" / "ECGMeasurement.swift").read_text(
            encoding="utf-8"
        )
        mapper = (IOS_ROOT / "HealthKit" / "ECGHealthKitMapper.swift").read_text(
            encoding="utf-8"
        )
        example = (IOS_ROOT / "Models" / "ECGExampleFactory.swift").read_text(
            encoding="utf-8"
        )
        detail_model = (
            IOS_ROOT / "Features" / "ECGDetail" / "ECGDetailViewModel.swift"
        ).read_text(encoding="utf-8")

        self.assertIn("self.analysis = analyzer.analyze(signal)", measurement)
        self.assertIn("ECGSignal(", mapper)
        self.assertIn("ECGSignal(", example)
        self.assertIn("measurement.analysis.beats.map", detail_model)
        self.assertNotIn("syntheticRPeakMarkers()", detail_model)


if __name__ == "__main__":
    unittest.main()
