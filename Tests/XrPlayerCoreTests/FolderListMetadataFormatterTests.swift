import Foundation
import XCTest
@testable import XrPlayerCore

final class FolderListMetadataFormatterTests: XCTestCase {
    func testFileSizeFormatsHumanReadableValue() {
        XCTAssertEqual(normalizedWhitespace(FolderListMetadataFormatter.fileSize(1024)), "1 KB")
    }

    func testByteCountFormatterReusesSameLocaleCacheKey() {
        let first = FolderListMetadataFormatter.byteCountFormatter(localeIdentifier: "en_US")
        let second = FolderListMetadataFormatter.byteCountFormatter(localeIdentifier: "en_US")

        XCTAssertTrue(first === second)
    }

    func testByteCountFormatterRecreatesFormatterWhenLocaleKeyChanges() {
        let first = FolderListMetadataFormatter.byteCountFormatter(localeIdentifier: "en_US")
        let second = FolderListMetadataFormatter.byteCountFormatter(localeIdentifier: "fr_FR")

        XCTAssertFalse(first === second)
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

    func testDateFormatterReusesSameFormatPreferenceSignature() {
        let locale = Locale(identifier: "en_US")
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let first = FolderListMetadataFormatter.dateFormatter(
            locale: locale,
            timeZone: timeZone,
            formatPreferenceSignature: "gregorian.MMM d, y 'at' h:mm a"
        )
        let second = FolderListMetadataFormatter.dateFormatter(
            locale: locale,
            timeZone: timeZone,
            formatPreferenceSignature: "gregorian.MMM d, y 'at' h:mm a"
        )

        XCTAssertTrue(first === second)
    }

    func testDateFormatterRecreatesFormatterWhenFormatPreferenceSignatureChanges() {
        let locale = Locale(identifier: "en_US")
        let timeZone = TimeZone(secondsFromGMT: 0)!

        let first = FolderListMetadataFormatter.dateFormatter(
            locale: locale,
            timeZone: timeZone,
            formatPreferenceSignature: "gregorian.MMM d, y 'at' h:mm a"
        )
        let second = FolderListMetadataFormatter.dateFormatter(
            locale: locale,
            timeZone: timeZone,
            formatPreferenceSignature: "buddhist.d MMM y 'at' HH:mm"
        )

        XCTAssertFalse(first === second)
    }

    func testFormatPreferenceSignatureIncludesCalendarAndDateFormat() {
        let locale = Locale(identifier: "en_GB")
        let expectedDateFormat = DateFormatter.dateFormat(
            fromTemplate: "yMMMdj",
            options: 0,
            locale: locale
        ) ?? "default"

        let signature = FolderListMetadataFormatter.computedFormatPreferenceSignature(for: locale)

        XCTAssertEqual(signature, "gregorian.\(expectedDateFormat)")
    }

    private func normalizedWhitespace(_ value: String) -> String {
        value.components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }
}
