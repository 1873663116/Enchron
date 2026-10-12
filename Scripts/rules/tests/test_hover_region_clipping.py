import sys
import unittest
from pathlib import Path


sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import check_hover_region_clipping as checker


class HoverRegionClippingTests(unittest.TestCase):
    def audit(self, chain):
        source = "struct Number: View { var body: some View {\nButton {} label: {\nText(\"1\")\n" + chain + "\n} } }\n"
        findings, _, _ = checker.audit_sources({Path("Modules/DesignSystem/Components/Number.swift"): source})
        return [finding.reason for finding in findings if finding.classification == "violation"]

    def test_visual_background_expanded_before_hover_is_rejected(self):
        self.assertEqual(self.audit(
            ".frame(width: DesignTokens.Interactive.regular)\n"
            ".background(DesignTokens.Surface.selected, in: DesignTokens.ShapeToken.menuNumber)\n"
            ".padding(insets)\n"
            ".enchronHoverContentShape(DesignTokens.ShapeToken.menuNumber)\n"
            ".enchronHoverEffect()"
        ), ["visual background is enlarged before hover without matching insets in that hover call"])

    def test_visual_background_frame_expansion_is_rejected(self):
        self.assertEqual(len(self.audit(
            ".background(DesignTokens.Surface.selected)\n"
            ".frame(width: DesignTokens.Interactive.large)\n"
            ".enchronHoverContentShape(Circle())"
        )), 1)

    def test_same_hover_call_must_own_the_insets(self):
        self.assertEqual(len(self.audit(
            ".background(DesignTokens.Surface.selected)\n.padding(insets)\n"
            ".enchronHoverContentShape(Circle())\n"
            ".anotherModifier(insets: insets)"
        )), 1)

    def test_unrelated_hover_insets_do_not_match_padding(self):
        self.assertEqual(len(self.audit(
            ".background(DesignTokens.Surface.selected)\n.padding(insets)\n"
            ".enchronHoverContentShape(Circle(), insets: otherInsets)"
        )), 1)

    def test_nested_shape_factory_insets_do_not_define_hover_insets(self):
        self.assertEqual(len(self.audit(
            ".background(DesignTokens.Surface.selected)\n.padding(insets)\n"
            ".enchronHoverContentShape(makeShape(insets: insets))"
        )), 1)

    def test_comment_does_not_supply_hover_insets(self):
        self.assertEqual(len(self.audit(
            ".background(DesignTokens.Surface.selected)\n.padding(insets)\n"
            ".enchronHoverContentShape(Circle() /* insets: insets */)"
        )), 1)

    def test_matching_inset_hover_after_expansion_passes(self):
        self.assertEqual(self.audit(
            ".frame(width: DesignTokens.Interactive.regular)\n"
            ".background(DesignTokens.Surface.selected, in: DesignTokens.ShapeToken.menuNumber)\n"
            ".enchronHoverContentShape(DesignTokens.ShapeToken.menuNumber)\n"
            ".enchronHoverEffect()\n.padding(insets)\n"
            ".enchronHoverContentShape(DesignTokens.ShapeToken.menuNumberTarget, insets: insets)"
        ), [])

    def test_padding_before_visible_background_passes(self):
        self.assertEqual(self.audit(
            ".padding(insets)\n.background(DesignTokens.Surface.selected)\n"
            ".enchronHoverContentShape(DesignTokens.ShapeToken.menuRow)"
        ), [])

    def test_background_builder_is_checked_after_its_closure(self):
        self.assertEqual(len(self.audit(
            ".background { DesignTokens.ShapeToken.menuNumber.fill(DesignTokens.Surface.selected) }\n"
            ".padding(insets)\n.enchronHoverContentShape(Circle())"
        )), 1)

    def test_nested_background_does_not_define_outer_hover_bounds(self):
        self.assertEqual(self.audit(
            ".overlay { Text(\"Nested\").background(DesignTokens.Surface.selected) }\n"
            ".padding(insets)\n.enchronHoverContentShape(Circle())"
        ), [])

    def test_hover_carrier_expansion_requires_its_own_insets(self):
        self.assertEqual(len(self.audit(
            ".enchronHoverContentShape(Circle()).enchronHoverEffect()\n"
            ".frame(width: DesignTokens.Interactive.large)\n"
            ".enchronHoverContentShape(Circle())\n.anotherModifier(insets: insets)"
        )), 1)
        carrier = """
struct VisualLabel: View {
    var body: some View {
        Circle().enchronHoverContentShape(Circle()).enchronHoverEffect()
    }
}
"""
        cases = (
            ("expanded", "VisualLabel().frame(width: targetSize, height: targetSize)", "", 1),
            ("inset", "VisualLabel().frame(width: targetSize, height: targetSize)", ".enchronHoverContentShape(Circle(), insets: EdgeInsets(top: (targetSize - visualSize) / 2, leading: (targetSize - visualSize) / 2, bottom: (targetSize - visualSize) / 2, trailing: (targetSize - visualSize) / 2))", 0),
            ("same_bounds", "Circle().frame(width: 44, height: 44).enchronHoverContentShape(Circle()).enchronHoverEffect()", "", 0),
        )
        for name, label, hover, expected in cases:
            with self.subTest(name=name):
                source = carrier + "struct Host: View {\n var body: some View {\n  Button {} label: {\n   " + label + "\n  }\n  " + hover + "\n }\n}\n"
                findings, carriers, count = checker.audit_sources({Path("Host.swift"): source})
                self.assertIn("VisualLabel", carriers)
                self.assertEqual(count, 1)
                self.assertEqual(sum(finding.classification == "violation" for finding in findings), expected)


    def test_button_style_hover_expansion_is_rejected(self):
        source = """
struct MenuStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { Capsule().fill(.gray) }
            .enchronHoverContentShape(Capsule())
            .enchronHoverEffect(.highlight)
            .padding(insets)
            .enchronHoverContentShape(Capsule(), insets: insets)
    }
}
"""
        findings, _, count = checker.audit_sources({Path("Style.swift"): source})
        self.assertEqual(count, 1)
        self.assertEqual([f.reason for f in findings if f.classification == "violation"],
                         ["ButtonStyle expands a hover-bearing label; use the shared visual/interaction target"])

    def test_capsule_parent_cannot_own_two_buttons_hover(self):
        source = """
struct Toggle: View {
    var body: some View {
        HStack {
            Button {} label: { Text("Grid") }
            Button {} label: { Text("List") }
        }
        .enchronGlassControl()
    }
}
"""
        findings, _, _ = checker.audit_sources({Path("Toggle.swift"): source})
        self.assertEqual([f.reason for f in findings if f.classification == "violation"],
                         ["container hover covers multiple buttons; attach hover to each visible button"])
        findings, _, _ = checker.audit_sources({Path("Toggle.swift"): source.replace("enchronGlassControl()", "enchronGlassControlSurface()")})
        self.assertEqual([f for f in findings if f.classification == "violation"], [])

    def test_shared_target_requires_distinct_visual_and_hit_shapes(self):
        source = """
func enchronHoverTarget<Visual: Shape, Interaction: Shape>(visual: Visual, interaction: Interaction,
                                                         insets: EdgeInsets) -> some View {
    let hover = EnchronHoverRegion(visual, insets: insets)
    return self.padding(insets).clipShape(hover)
        .contentShape(.interaction, interaction)
        .contentShape(.hoverEffect, hover)
        .enchronHoverEffect(.highlight)
}
"""
        findings, _, _ = checker.audit_sources({Path("Platform.swift"): source})
        self.assertEqual(findings, [])
        for faulty in (source.replace(".clipShape(hover)", ".clipShape(interaction)"),
                       source.replace(".contentShape(.hoverEffect, hover)", ".contentShape(.hoverEffect, interaction)"),
                       source.replace(".contentShape(.interaction, interaction)", "")):
            findings, _, _ = checker.audit_sources({Path("Platform.swift"): faulty})
            self.assertEqual(len([f for f in findings if f.classification == "violation"]), 1)


if __name__ == "__main__":
    unittest.main()
