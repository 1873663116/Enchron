import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKTREE = Path(__file__).resolve().parents[2]
CHECKER = WORKTREE / "Scripts" / "verification" / "verify_design_source_architecture.py"


class DesignSourceArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        (self.root / "Apps/DesignPreview").mkdir(parents=True)
        (self.root / "Modules/DesignSystem").mkdir(parents=True)
        (self.root / "Config").mkdir()
        self.write("Config/baseline.json", '{"version": 1, "allowances": []}\n')
        self.write(
            "Modules/DesignSystem/DesignTokens.swift",
            "import SwiftUI\n"
            "public enum DesignTokens {\n"
            "    public static let accent = Color.accentColor\n"
            "}\n",
        )

    def tearDown(self):
        self.temporary_directory.cleanup()

    def write(self, relative_path, contents):
        path = self.root / relative_path
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents, encoding="utf-8")

    def invoke(self, *arguments, expected_code=0, environment=None):
        result = subprocess.run(
            [
                sys.executable,
                str(CHECKER),
                "--root",
                str(self.root),
                "--baseline",
                "Config/baseline.json",
                *arguments,
            ],
            text=True,
            capture_output=True,
            env=environment,
        )
        self.assertEqual(result.returncode, expected_code, result.stderr or result.stdout)
        return result

    def xcode_environment(self, *relative_inputs):
        environment = os.environ.copy()
        environment["SCRIPT_INPUT_FILE_COUNT"] = str(len(relative_inputs))
        for index, relative_path in enumerate(relative_inputs):
            environment[f"SCRIPT_INPUT_FILE_{index}"] = str(self.root / relative_path)
        return environment

    def test_production_component_composition_passes(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View { ProductionCard.sample() }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_parallel_style_raw_control_and_literal_report_file_and_line(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "private struct LocalStyle: ButtonStyle {\n"
            "    func makeBody(configuration: Configuration) -> some View {\n"
            "        Button(\"Parallel\") {}\n"
            "            .frame(width: 44)\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn(
            "Apps/DesignPreview/CardPreview.swift:3: error: [preview-parallel-style]",
            result.stderr,
        )
        self.assertIn(
            "Apps/DesignPreview/CardPreview.swift:5: error: [preview-raw-control]",
            result.stderr,
        )
        self.assertIn(
            "Apps/DesignPreview/CardPreview.swift:6: error: [preview-hardcoded-visual]",
            result.stderr,
        )

    def test_design_tokens_cannot_define_view_structure(self):
        self.write(
            "Modules/DesignSystem/DesignTokens.swift",
            "import SwiftUI\n"
            "public enum DesignTokens {\n"
            "    public struct CardRecipe: View {\n"
            "        public var body: some View { Text(\"Parallel\") }\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn(
            "Modules/DesignSystem/DesignTokens.swift:3: error: [token-layer-structure]",
            result.stderr,
        )
        self.assertIn(
            "Modules/DesignSystem/DesignTokens.swift:4: error: [token-layer-structure]",
            result.stderr,
        )

    def test_multiline_control_and_visual_literal_cannot_bypass_the_check(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View {\n"
            "        Button\n"
            "        {\n"
            "        }\n"
            "        label: { Text(\"Parallel\") }\n"
            "        .frame(\n"
            "            width: 44\n"
            "        )\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn(
            "Apps/DesignPreview/CardPreview.swift:5: error: [preview-raw-control]",
            result.stderr,
        )
        self.assertIn(
            "Apps/DesignPreview/CardPreview.swift:9: error: [preview-hardcoded-visual]",
            result.stderr,
        )

    def test_xcode_mode_rejects_a_design_preview_directory_input(self):
        result = self.invoke(
            "--xcode-inputs",
            expected_code=1,
            environment=self.xcode_environment(
                "Apps/DesignPreview",
                "Config/baseline.json",
                "Modules/DesignSystem/DesignTokens.swift",
            ),
        )
        self.assertIn("[xcode-input-scope]", result.stderr)
        self.assertIn("must name Swift files", result.stderr)

    def test_xcode_mode_reads_declared_swift_files_without_entering_assets(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View { ProductionCard.sample() }\n"
            "}\n",
        )
        self.write("Apps/DesignPreview/Assets.xcassets/Contents.json", "{}\n")
        environment = self.xcode_environment(
            "Apps/DesignPreview/CardPreview.swift",
            "Config/baseline.json",
            "Modules/DesignSystem/DesignTokens.swift",
        )
        result = self.invoke("--xcode-inputs", environment=environment)
        self.assertIn("Design source architecture passed", result.stdout)

    def test_xcode_mode_still_blocks_a_declared_source_violation(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View { Button(\"Parallel\") {} }\n"
            "}\n",
        )
        environment = self.xcode_environment(
            "Apps/DesignPreview/CardPreview.swift",
            "Config/baseline.json",
            "Modules/DesignSystem/DesignTokens.swift",
        )
        result = self.invoke(
            "--xcode-inputs",
            expected_code=1,
            environment=environment,
        )
        self.assertIn("[preview-raw-control]", result.stderr)

    def test_repository_mode_rejects_a_build_phase_source_list_drift(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View { ProductionCard.sample() }\n"
            "}\n",
        )
        phase = (
            "E30000012FA3000100E1C001 /* Design Source Architecture */ = {\n"
            "    inputPaths = (\n"
            '        "$(SRCROOT)/Apps/DesignPreview/OldPreview.swift",\n'
            "    );\n"
            '    shellScript = "python3 checker.py --xcode-inputs";\n'
            "};\n"
        )
        self.write(
            "Enchron.xcodeproj/project.pbxproj",
            phase + phase.replace("001 /*", "002 /*") + phase.replace("001 /*", "003 /*"),
        )
        result = self.invoke(expected_code=1)
        self.assertIn("[xcode-build-inputs]", result.stderr)
        self.assertIn("CardPreview.swift", result.stderr)

    def test_exact_baseline_allows_history_but_rejects_an_added_occurrence(self):
        self.write(
            "Apps/DesignPreview/CardPreview.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardPreview: View {\n"
            "    var body: some View { Button(\"Legacy\") {} }\n"
            "}\n",
        )
        self.invoke("--write-baseline")
        self.invoke()

        path = self.root / "Apps/DesignPreview/CardPreview.swift"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "Button(\"Legacy\") {}",
                "VStack { Button(\"Legacy\") {}; Button(\"Legacy\") {} }",
            ),
            encoding="utf-8",
        )
        result = self.invoke(expected_code=1)
        self.assertIn("[preview-raw-control]", result.stderr)

    def test_stale_baseline_must_be_shrunk(self):
        baseline = {
            "version": 1,
            "allowances": [
                {
                    "rule": "preview-raw-control",
                    "path": "Apps/DesignPreview/RemovedPreview.swift",
                    "signature": 'Button("Old") {}',
                    "count": 1,
                }
            ],
        }
        self.write("Config/baseline.json", json.dumps(baseline))
        result = self.invoke(expected_code=1)
        self.assertIn("[baseline-stale]", result.stderr)


if __name__ == "__main__":
    unittest.main()
