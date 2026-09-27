from __future__ import annotations

import plistlib
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

    def test_milestone_two_sources_are_members_of_xcode_targets(self) -> None:
        project = PROJECT_FILE.read_text(encoding="utf-8")
        source_files = {
            "ECGDisplay.swift",
            "ECGExportEncoder.swift",
            "ECGExampleFactory.swift",
            "ECGWaveformView.swift",
            "ECGExportSharing.swift",
            "ECGPresentationAndExportTests.swift",
            "AppLanguage.swift",
            "AppStyle.swift",
            "AppHomeView.swift",
            "OverviewView.swift",
            "SettingsView.swift",
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


if __name__ == "__main__":
    unittest.main()
