from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


REPOSITORY_ROOT = Path(__file__).parents[3]
PACKAGE_ROOT = REPOSITORY_ROOT / "Tools" / "PeakSwiftBenchmark"


class PeakSwiftBenchmarkConfigurationTests(unittest.TestCase):
    def test_package_uses_exact_released_versions_and_no_branch(self) -> None:
        package = (PACKAGE_ROOT / "Package.swift").read_text(encoding="utf-8")

        self.assertIn('exact: "1.0.0"', package)
        self.assertIn('exact: "2.3.2"', package)
        self.assertNotIn("branch:", package)
        self.assertNotIn('.branch(', package)

    def test_resolved_packages_match_reviewed_full_revisions(self) -> None:
        lock = json.loads((PACKAGE_ROOT / "dependency-lock.json").read_text(encoding="utf-8"))
        resolved = json.loads((PACKAGE_ROOT / "Package.resolved").read_text(encoding="utf-8"))
        pins = {pin["identity"]: pin for pin in resolved["pins"]}

        self.assertEqual(set(pins), set(lock["packages"]))
        for identity, expected in lock["packages"].items():
            state = pins[identity]["state"]
            self.assertEqual(state["version"], expected["version"])
            self.assertEqual(state["revision"], expected["revision"])
            self.assertEqual(len(state["revision"]), 40)

    def test_submodule_revisions_and_licenses_are_frozen(self) -> None:
        lock = json.loads((PACKAGE_ROOT / "dependency-lock.json").read_text(encoding="utf-8"))
        submodules = lock["peakSwiftGitSubmodules"]

        self.assertEqual(set(submodules), {"iir1", "wavelib"})
        self.assertEqual(submodules["iir1"]["license"], "MIT")
        self.assertEqual(submodules["wavelib"]["license"], "BSD-3-Clause")
        for component in submodules.values():
            self.assertEqual(len(component["revision"]), 40)

    def test_prediction_metadata_matches_dependency_lock(self) -> None:
        lock = json.loads((PACKAGE_ROOT / "dependency-lock.json").read_text(encoding="utf-8"))
        source = (
            PACKAGE_ROOT
            / "Sources"
            / "PeakSwiftBenchmarkSupport"
            / "PeakSwiftPredictionRunner.swift"
        ).read_text(encoding="utf-8")

        constants = dict(
            re.findall(
                r'private static let (peakSwiftVersion|peakSwiftRevision|surgeRevision) = "([^"]+)"',
                source,
            )
        )
        self.assertEqual(
            constants,
            {
                "peakSwiftVersion": lock["packages"]["peakswift"]["version"],
                "peakSwiftRevision": lock["packages"]["peakswift"]["revision"],
                "surgeRevision": lock["packages"]["surge"]["revision"],
            },
        )

    def test_adapter_cannot_decode_reference_labels(self) -> None:
        source = "\n".join(
            path.read_text(encoding="utf-8")
            for path in sorted((PACKAGE_ROOT / "Sources").rglob("*.swift"))
        )

        self.assertNotIn("referencePeakSamples", source)
        self.assertIn("detectedPeakSamples", source)
        self.assertIn("--allow-held-out-test", source)

    def test_test_script_uses_process_local_https_rewrite(self) -> None:
        script = (
            REPOSITORY_ROOT / "Tools" / "run-peakswift-benchmark-tests.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("GIT_CONFIG_KEY_0='url.https://github.com/.insteadOf'", script)
        self.assertIn("GIT_CONFIG_VALUE_0='git@github.com:'", script)
        self.assertNotIn("git config --global", script)


if __name__ == "__main__":
    unittest.main()
