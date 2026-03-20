import XCTest
@testable import XrPlayerCore

final class SortCriteriaTests: XCTestCase {
    func testSortByNameAscendingUsesLocalizedCaseInsensitiveOrder() {
        let sorted = FileBrowsingDomain.SortCriteria(key: .name, order: .ascending).sorted(sampleFiles)
        XCTAssertEqual(sorted.map(\.name), ["Alpha.mp4", "beta.mp4", "Gamma.mp4"])
    }

    func testSortByModifiedDateDescendingKeepsNewestFirst() {
        let sorted = FileBrowsingDomain.SortCriteria(key: .modifiedDate, order: .descending).sorted(sampleFiles)
        XCTAssertEqual(sorted.map(\.name), ["beta.mp4", "Gamma.mp4", "Alpha.mp4"])
    }

    func testSortBySizeAscendingKeepsSmallestFirst() {
        let sorted = FileBrowsingDomain.SortCriteria(key: .size, order: .ascending).sorted(sampleFiles)
        XCTAssertEqual(sorted.map(\.name), ["beta.mp4", "Alpha.mp4", "Gamma.mp4"])
    }

    private var sampleFiles: [FileBrowsingDomain.MediaFile] {
        [
            .init(
                name: "Gamma.mp4",
                sizeInBytes: 30,
                modifiedAt: Date(timeIntervalSince1970: 20),
                fileExtension: "mp4",
                url: URL(fileURLWithPath: "/tmp/gamma.mp4")
            ),
            .init(
                name: "beta.mp4",
                sizeInBytes: 10,
                modifiedAt: Date(timeIntervalSince1970: 30),
                fileExtension: "mp4",
                url: URL(fileURLWithPath: "/tmp/beta.mp4")
            ),
            .init(
                name: "Alpha.mp4",
                sizeInBytes: 20,
                modifiedAt: Date(timeIntervalSince1970: 10),
                fileExtension: "mp4",
                url: URL(fileURLWithPath: "/tmp/alpha.mp4")
            )
        ]
    }
}
