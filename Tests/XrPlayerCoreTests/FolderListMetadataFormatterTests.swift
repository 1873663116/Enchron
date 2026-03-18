import Foundation
import XCTest
@testable import XrPlayerCore

final class FolderListMetadataFormatterTests: XCTestCase {
    func testFileSizeFormatsHumanReadableValue() {
        XCTAssertEqual(normalizedWhitespace(FolderListMetadataFormatter.fileSize(1024)), "1 KB")
    }

    func testModifiedDateRespectsSuppliedTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        let locale = Locale(identifier: "en_US_POSIX")

        let utc = FolderListMetadataFormatter.modifiedDate(
            date,
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let shanghai = FolderListMetadataFormatter.modifiedDate(
            date,
            locale: locale,
            timeZone: TimeZone(secondsFromGMT: 8 * 60 * 60)!
        )

        XCTAssertTrue(utc.contains("12:00"))
        XCTAssertTrue(shanghai.contains("8:00"))
        XCTAssertNotEqual(utc, shanghai)
    }

    func testSubtitleCombinesSizeAndModifiedDate() {
        let subtitle = normalizedWhitespace(
            FolderListMetadataFormatter.subtitle(
            sizeInBytes: 1024,
            modifiedAt: Date(timeIntervalSince1970: 0),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        )

        XCTAssertTrue(subtitle.contains("1 KB"))
        XCTAssertTrue(subtitle.contains("Jan 1, 1970"))
        XCTAssertTrue(subtitle.contains("•"))
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
