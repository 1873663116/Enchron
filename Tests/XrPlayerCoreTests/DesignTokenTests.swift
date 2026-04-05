import XCTest

/// Verifies the Enchron semantic color palette design contract.
///
/// The actual Color assets live in the app's Asset Catalog and are loaded via
/// `Color("name", bundle: .main)` in `Color+DesignTokens.swift`. Since SPM tests
/// don't have access to the app bundle, we verify the design spec values here
/// as a contract test — ensuring the expected hex values are documented and
/// the palette is complete.
final class DesignTokenTests: XCTestCase {

    // MARK: - Design Spec Contract

    /// The 9-color semantic palette from the design spec.
    /// If a color is added/removed/changed, this test must be updated in lockstep.
    private static let designPalette: [(name: String, hex: String)] = [
        ("enchronSurface",                "#131313"),
        ("enchronOnSurface",              "#E5E2E1"),
        ("enchronTertiary",               "#ADC6FF"),
        ("enchronOnTertiary",             "#002E6A"),
        ("enchronPrimary",                "#C6C6C7"),
        ("enchronOnPrimary",              "#2F3131"),
        ("enchronSurfaceContainerLow",    "#1C1B1B"),
        ("enchronSurfaceContainerHighest","#353535"),
        ("enchronOnSurfaceVariant",       "#C1C6D7"),
    ]

    func testPaletteContainsExactlyNineColors() {
        XCTAssertEqual(Self.designPalette.count, 9,
                       "Enchron design palette must have exactly 9 semantic colors")
    }

    func testAllColorNamesAreUnique() {
        let names = Self.designPalette.map(\.name)
        XCTAssertEqual(Set(names).count, names.count,
                       "Color names must be unique — found duplicates")
    }

    func testAllHexValuesAreValidSixDigit() {
        let hexPattern = /^#[0-9A-Fa-f]{6}$/
        for entry in Self.designPalette {
            XCTAssertNotNil(entry.hex.firstMatch(of: hexPattern),
                            "\(entry.name) has invalid hex: \(entry.hex)")
        }
    }

    func testSurfaceColorIsDesignBaseDark() {
        let surface = Self.designPalette.first { $0.name == "enchronSurface" }
        XCTAssertEqual(surface?.hex, "#131313",
                       "Surface must be the design base dark color")
    }

    func testTertiaryColorIsDesignAccent() {
        let tertiary = Self.designPalette.first { $0.name == "enchronTertiary" }
        XCTAssertEqual(tertiary?.hex, "#ADC6FF",
                       "Tertiary must be the design accent color")
    }

    func testColorNamesFollowEnchronPrefix() {
        for entry in Self.designPalette {
            XCTAssertTrue(entry.name.hasPrefix("enchron"),
                          "\(entry.name) must start with 'enchron' prefix")
        }
    }

    // MARK: - Hex-to-RGB Conversion Verification

    /// Verifies the hex-to-RGB conversion matches what the Asset Catalog should contain.
    /// These are the exact sRGB float values written to the .colorset JSON files.
    func testHexToRGBConversion() {
        let expectations: [(name: String, r: Double, g: Double, b: Double)] = [
            ("enchronSurface",                0.075, 0.075, 0.075),
            ("enchronOnSurface",              0.898, 0.886, 0.882),
            ("enchronTertiary",               0.678, 0.776, 1.000),
            ("enchronOnTertiary",             0.000, 0.180, 0.416),
            ("enchronPrimary",                0.776, 0.776, 0.780),
            ("enchronOnPrimary",              0.184, 0.192, 0.192),
            ("enchronSurfaceContainerLow",    0.110, 0.106, 0.106),
            ("enchronSurfaceContainerHighest",0.208, 0.208, 0.208),
            ("enchronOnSurfaceVariant",       0.757, 0.776, 0.843),
        ]

        for expected in expectations {
            guard let entry = Self.designPalette.first(where: { $0.name == expected.name }) else {
                XCTFail("Missing palette entry: \(expected.name)")
                continue
            }

            let (r, g, b) = hexToRGB(entry.hex)
            XCTAssertEqual(r, expected.r, accuracy: 0.002, "\(expected.name) red component")
            XCTAssertEqual(g, expected.g, accuracy: 0.002, "\(expected.name) green component")
            XCTAssertEqual(b, expected.b, accuracy: 0.002, "\(expected.name) blue component")
        }
    }

    // MARK: - Helpers

    private func hexToRGB(_ hex: String) -> (r: Double, g: Double, b: Double) {
        let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard stripped.count == 6, let value = UInt64(stripped, radix: 16) else {
            return (0, 0, 0)
        }
        return (
            r: Double((value >> 16) & 0xFF) / 255.0,
            g: Double((value >> 8) & 0xFF) / 255.0,
            b: Double(value & 0xFF) / 255.0
        )
    }
}
