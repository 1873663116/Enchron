import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


WORKTREE = Path(__file__).resolve().parents[2]
CHECKER = WORKTREE / "Scripts" / "rules" / "verify_design_source_architecture.py"


class DesignSourceArchitectureTests(unittest.TestCase):
    def setUp(self):
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        (self.root / "Apps/Enchron").mkdir(parents=True)
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

    def invoke(self, *arguments, expected_code=0):
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
        )
        self.assertEqual(result.returncode, expected_code, result.stderr or result.stdout)
        return result

    def test_production_component_composition_passes(self):
        self.write(
            "Apps/Enchron/CardScreen.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardScreen: View {\n"
            "    var body: some View { ProductionCard.sample() }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_production_feature_must_not_construct_parallel_glass_capsule(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    var body: some View {\n"
            "        Button(\"More\") {}\n"
            "            .enchronGlassBackground(in: Capsule())\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn(
            "Apps/Enchron/PlayerControls.swift:6: error: "
            "[production-parallel-glass-component]",
            result.stderr,
        )

    def test_production_feature_can_compose_design_system_component(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    var body: some View { CircleIconButton.environment() }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_design_system_owns_raw_glass_capsule_construction(self):
        self.write(
            "Modules/DesignSystem/GlassButton.swift",
            "import SwiftUI\n"
            "public struct GlassButton: View {\n"
            "    public var body: some View {\n"
            "        Button(\"More\") {}\n"
            "            .enchronGlassBackground(in: Capsule())\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_production_visual_literals_must_use_design_tokens(self):
        literal_lines = (
            ".frame(width: 17)",
            ".padding(.horizontal, 17)",
            ".offset(x: -17)",
            "HStack(spacing: 17) { EmptyView() }",
            "RoundedRectangle(cornerRadius: 17)",
            ".font(.system(size: 17))",
            ".stroke(.white, lineWidth: 17)",
        )
        for literal_line in literal_lines:
            with self.subTest(literal_line=literal_line):
                self.write(
                    "Apps/Enchron/PlayerControls.swift",
                    "import SwiftUI\n"
                    "struct PlayerControls: View {\n"
                    "    var body: some View {\n"
                    "        Text(\"Controls\")\n"
                    f"            {literal_line}\n"
                    "    }\n"
                    "}\n",
                )
                result = self.invoke(expected_code=1)
                self.assertIn(
                    "Apps/Enchron/PlayerControls.swift:5: error: "
                    "[production-hardcoded-visual]",
                    result.stderr,
                )

    def test_production_identity_values_and_unbounded_frame_are_not_visual_literals(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    let isEnabled: Bool\n"
            "    let progress: Double\n"
            "    var body: some View {\n"
            "        Text(\"Controls\")\n"
            "            .frame(maxWidth: .infinity)\n"
            "            .opacity(isEnabled ? 1 : 0)\n"
            "            .opacity(1 - min(progress, 1))\n"
            "            .scaleEffect(isEnabled ? DesignTokens.Motion.pressScale : 1.0)\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_non_identity_opacity_and_scale_values_remain_visual_literals(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    let isEnabled: Bool\n"
            "    var body: some View {\n"
            "        Text(\"Controls\")\n"
            "            .opacity(isEnabled ? 1 : 0.42)\n"
            "            .scaleEffect(isEnabled ? 1 : 0.98)\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertEqual(result.stderr.count("[production-hardcoded-visual]"), 2)

    def test_design_system_owns_visual_literals(self):
        self.write(
            "Modules/DesignSystem/MeasuredCard.swift",
            "import SwiftUI\n"
            "public struct MeasuredCard: View {\n"
            "    public var body: some View {\n"
            "        RoundedRectangle(cornerRadius: 17)\n"
            "            .frame(width: 44)\n"
            "            .padding(8)\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_swift_comments_do_not_create_production_visual_findings(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    // .padding(.horizontal, 17)\n"
            "    /*\n"
            "     .frame(width: 44)\n"
            "     HStack(spacing: 8) {}\n"
            "     */\n"
            "    var body: some View { Text(\"Controls\") }\n"
            "}\n",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_xcode_mode_also_checks_production_sources(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    var body: some View {\n"
            "        Button(\"More\") {}\n"
            "            .enchronGlassBackground(in: Capsule())\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke("--xcode-inputs", expected_code=1)
        self.assertIn("[production-parallel-glass-component]", result.stderr)

    def test_xcode_mode_also_checks_production_visual_literals(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    var body: some View {\n"
            "        Text(\"Controls\")\n"
            "            .padding(.horizontal, 17)\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke("--xcode-inputs", expected_code=1)
        self.assertIn("[production-hardcoded-visual]", result.stderr)

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

    def test_multiline_visual_literal_cannot_bypass_the_check(self):
        self.write(
            "Apps/Enchron/CardScreen.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardScreen: View {\n"
            "    var body: some View {\n"
            "        Text(\"Card\")\n"
            "        .frame(\n"
            "            width: 44\n"
            "        )\n"
            "    }\n"
            "}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn(
            "Apps/Enchron/CardScreen.swift:6: error: [production-hardcoded-visual]",
            result.stderr,
        )

    def test_xcode_mode_passes_on_a_clean_production_tree(self):
        self.write(
            "Apps/Enchron/CardScreen.swift",
            "import DesignSystem\n"
            "import SwiftUI\n"
            "struct CardScreen: View {\n"
            "    var body: some View { ProductionCard.sample() }\n"
            "}\n",
        )
        result = self.invoke("--xcode-inputs")
        self.assertIn("Design source architecture passed", result.stdout)

    def test_repository_mode_requires_a_design_source_architecture_phase(self):
        self.write(
            "Enchron.xcodeproj/project.pbxproj",
            "// !$*UTF8*$!\n{\n}\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn("[xcode-build-inputs]", result.stderr)
        self.assertIn(
            "the Enchron target must run one Design Source Architecture build phase",
            result.stderr,
        )

    def test_repository_mode_rejects_a_phase_that_skips_the_sandbox_contract(self):
        self.write(
            "Enchron.xcodeproj/project.pbxproj",
            "E30000012FA3000100E1C001 /* Design Source Architecture */ = {\n"
            "    inputPaths = (\n"
            "    );\n"
            '    shellScript = "python3 checker.py";\n'
            "};\n",
        )
        result = self.invoke(expected_code=1)
        self.assertIn("[xcode-build-inputs]", result.stderr)
        self.assertIn("shell script does not use --xcode-inputs", result.stderr)
        self.assertIn("missing production input list", result.stderr)

    def test_exact_baseline_allows_history_but_rejects_an_added_occurrence(self):
        self.write(
            "Apps/Enchron/CardScreen.swift",
            "import SwiftUI\n"
            "struct CardScreen: View {\n"
            "    var body: some View {\n"
            "        Text(\"Card\")\n"
            "            .padding(.horizontal, 17)\n"
            "    }\n"
            "}\n",
        )
        self.invoke("--write-baseline")
        self.invoke()

        path = self.root / "Apps/Enchron/CardScreen.swift"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "            .padding(.horizontal, 17)\n",
                "            .padding(.horizontal, 17)\n"
                "            .padding(.horizontal, 17)\n",
            ),
            encoding="utf-8",
        )
        result = self.invoke(expected_code=1)
        self.assertIn("[production-hardcoded-visual]", result.stderr)

    def test_baseline_signature_survives_unrelated_line_movement(self):
        self.write(
            "Apps/Enchron/PlayerControls.swift",
            "import SwiftUI\n"
            "struct PlayerControls: View {\n"
            "    var body: some View {\n"
            "        Text(\"Controls\")\n"
            "            .padding(.horizontal, 17)\n"
            "    }\n"
            "}\n",
        )
        self.invoke("--write-baseline")

        path = self.root / "Apps/Enchron/PlayerControls.swift"
        path.write_text(
            path.read_text(encoding="utf-8").replace(
                "struct PlayerControls: View {",
                "// Unrelated declaration moved the finding down.\n"
                "struct PlayerControls: View {",
            ),
            encoding="utf-8",
        )
        result = self.invoke()
        self.assertIn("Design source architecture passed", result.stdout)

    def test_stale_baseline_must_be_shrunk(self):
        baseline = {
            "version": 1,
            "allowances": [
                {
                    "rule": "production-hardcoded-visual",
                    "path": "Apps/Enchron/RemovedScreen.swift",
                    "signature": ".padding(.horizontal, 17)",
                    "count": 1,
                }
            ],
        }
        self.write("Config/baseline.json", json.dumps(baseline))
        result = self.invoke(expected_code=1)
        self.assertIn("[baseline-stale]", result.stderr)


if __name__ == "__main__":
    unittest.main()
