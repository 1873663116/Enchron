@testable import BluRayDisc
import BluRayDiscBridge
import Darwin
import Foundation
import Testing

private let corpusRoot = ProcessInfo.processInfo.environment["ENCHRON_BLURAY_CORPUS"]
    .map { URL(fileURLWithPath: $0, isDirectory: true) }

private struct LocalDiscTree: BluRayDiscFileSystem {
    let root: URL

    func contents(of relativePath: String) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: root.appending(path: relativePath).path
        )
    }

    func openFile(at relativePath: String) async throws -> any BluRayDiscRandomAccessFile {
        try LocalDiscFile(url: root.appending(path: relativePath))
    }
}

private struct MarkerFile: BluRayDiscRandomAccessFile {
    var size: Int64 { get async throws { 1 } }
    func read(at offset: Int64, count: Int) async throws -> Data {
        offset == 0 && count > 0 ? Data([0]) : Data()
    }
}

private struct DataDiscFile: BluRayDiscRandomAccessFile {
    let data: Data

    var size: Int64 { get async throws { Int64(data.count) } }

    func read(at offset: Int64, count: Int) async throws -> Data {
        guard offset >= 0, count >= 0, offset <= Int64(data.count) else { return Data() }
        let lowerBound = Int(offset)
        let upperBound = lowerBound + min(count, data.count - lowerBound)
        return data[lowerBound..<upperBound]
    }
}

private struct MetadataDiscTree: BluRayDiscFileSystem {
    let base: LocalDiscTree
    let metadata: Data

    func contents(of relativePath: String) async throws -> [String] {
        if relativePath == "BDMV/META/DL" { return ["bdmt_eng.xml"] }
        return try await base.contents(of: relativePath)
    }

    func openFile(at relativePath: String) async throws -> any BluRayDiscRandomAccessFile {
        if relativePath == "BDMV/META/DL/bdmt_eng.xml" {
            return DataDiscFile(data: metadata)
        }
        return try await base.openFile(at: relativePath)
    }
}

private struct EncryptedDiscTree: BluRayDiscFileSystem {
    let base: LocalDiscTree

    func contents(of relativePath: String) async throws -> [String] {
        if relativePath == "AACS" { return ["Unit_Key_RO.inf"] }
        return try await base.contents(of: relativePath)
    }

    func openFile(at relativePath: String) async throws -> any BluRayDiscRandomAccessFile {
        if relativePath == "AACS/Unit_Key_RO.inf" { return MarkerFile() }
        return try await base.openFile(at: relativePath)
    }
}

private final class LocalDiscFile: BluRayDiscRandomAccessFile, @unchecked Sendable {
    let descriptor: Int32
    let fileSize: Int64

    init(url: URL) throws {
        let opened = Darwin.open(url.path, O_RDONLY)
        guard opened >= 0 else { throw BluRayDiscError.io("Cannot open fixture file") }
        var metadata = stat()
        guard fstat(opened, &metadata) == 0 else {
            Darwin.close(opened)
            throw BluRayDiscError.io("Cannot stat fixture file")
        }
        descriptor = opened
        fileSize = metadata.st_size
    }

    deinit { Darwin.close(descriptor) }

    var size: Int64 { get async throws { fileSize } }

    func read(at offset: Int64, count: Int) async throws -> Data {
        var data = Data(count: count)
        let received = data.withUnsafeMutableBytes { bytes in
            Darwin.pread(descriptor, bytes.baseAddress, count, offset)
        }
        guard received >= 0 else { throw BluRayDiscError.io("Fixture read failed") }
        data.count = received
        return data
    }
}

@Suite struct BluRayDiscTests {
    @Test func interruptUnblocksRemoteCallbackAndAllowsFreshOperation() async throws {
        let box = CallbackBox(storage: .image(MarkerFile()))
        let started = ContinuousClock.now
        let blocked = Task.detached { () -> Bool in
            do {
                _ = try waitFor(box: box) {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    return 1
                }
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }
        try await Task.sleep(nanoseconds: 50_000_000)
        box.setInterrupted(true)
        #expect(await blocked.value)
        #expect(started.duration(to: .now) < .seconds(2))
        box.setInterrupted(false)
        let fresh = try waitFor(box: box) { 7 }
        #expect(fresh == 7)
    }

    @Test(.enabled(if: corpusRoot != nil))
    func felISOAndDirectoryExposeTheSameSelectedTitle() async throws {
        let root = try #require(corpusRoot)
        let folder = root.appending(path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS")
        let image = root.appending(path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS.iso")
        let imageCatalog = try BluRayDisc.catalog(at: image)
        let directoryCatalog = try BluRayDisc.catalog(at: folder.appending(path: "BDMV"))
        let rangedImageCatalog = try await BluRayDisc.catalog(image: LocalDiscFile(url: image))
        #expect(imageCatalog == directoryCatalog)
        #expect(imageCatalog == rangedImageCatalog)
        #expect(imageCatalog.optionalName == nil)
        #expect(imageCatalog.titles.count == 1)
        let title = try #require(imageCatalog.titles.first)
        #expect(title.playlistID.rawValue == 0)
        #expect(title.isMain)
        #expect(title.chapterCount == 1)
        #expect(abs(title.durationSeconds - 119.911_444_444) < 0.000_001)
        #expect(title.clips.count == 1)
        let clip = try #require(title.clips.first)
        #expect(clip.clipID == "00000")
        #expect(clip.startTimeSeconds == 0)
        #expect(clip.inTimeSeconds == 4200)
        #expect(abs(clip.outTimeSeconds - 4319.911_444_444) < 0.000_001)
        #expect(clip.byteStart == 0)
        #expect(clip.byteEnd == 169_881_600)
        #expect(clip.stillMode == 0)
        #expect(clip.stillTime == 0)
        #expect(!clip.hasInteractiveGraphics)
        #expect(clip.streams.map(\.format) == [8])
        #expect(clip.streams.map(\.rate) == [1])

        let reader = try await BluRayDisc.open(source: .url(image), playlistID: title.playlistID)
        let handle = try #require(reader.takeNativeHandle())
        defer { PBBlurayClose(handle) }
        var bytes = [UInt8](repeating: 0, count: 192)
        #expect(PBBlurayRead(handle, &bytes, Int32(bytes.count)) == 192)
        #expect(Array(bytes.prefix(5)) == [0x26, 0x5c, 0x57, 0xbc, 0x47])
        #expect(PBBluraySize(handle) == 169_881_600)
    }

    @Test(.enabled(if: corpusRoot != nil))
    func avsCatalogKeepsStablePlaylistIDsAcrossISOAndDirectory() async throws {
        let root = try #require(corpusRoot)
        let folder = root.appending(path: "AVS-HD-709/HDMV-2d")
        let image = root.appending(path: "AVS-HD-709/HDMV-2d.iso")
        let imageCatalog = try BluRayDisc.catalog(at: image)
        let directoryCatalog = try BluRayDisc.catalog(at: folder)
        #expect(imageCatalog == directoryCatalog)
        #expect(imageCatalog.titles.count == 110)
        #expect(imageCatalog.titles.prefix(3).map(\.playlistID.rawValue) == [0, 1, 2])
        let title = try #require(imageCatalog.titles.first { $0.playlistID.rawValue == 2 })
        #expect(title.durationSeconds == 3603.6)
        let clip = try #require(title.clips.first)
        #expect(clip.clipID == "00004")
        #expect(clip.inTimeSeconds == 600)
        #expect(clip.outTimeSeconds == 4203.6)
        #expect(clip.byteStart == 0)
        #expect(clip.byteEnd == 58_841_088)

        let playlist99 = try #require(
            imageCatalog.titles.first { $0.playlistID.rawValue == 99 }
        )
        #expect(playlist99.chapterCount == 2)
        let playlist99FirstClip = try #require(playlist99.clips.first)
        #expect(playlist99FirstClip.stillMode == 0)
        #expect(playlist99FirstClip.stillTime == 0)
        #expect(playlist99FirstClip.hasInteractiveGraphics)

        let reader = try await BluRayDisc.open(source: .url(image),
                                               playlistID: BluRayPlaylistID(rawValue: 99))
        let handle = try #require(reader.takeNativeHandle())
        defer { PBBlurayClose(handle) }
        #expect(PBBlurayReaderClipCount(handle) == 30)
        var middle = PBBlurayClipInfo()
        #expect(PBBlurayReaderClipAt(handle, 10, &middle))
        #expect(middle.byteStart == 208_128)
        #expect(middle.startTime90k == 900_900)
        let sought = PBBluraySeekTime(handle, 900_900)
        #expect(sought >= 0)
        #expect(UInt64(sought) < PBBluraySize(handle))
        var packet = [UInt8](repeating: 0, count: 192)
        #expect(PBBlurayRead(handle, &packet, Int32(packet.count)) == 192)
        #expect(packet[4] == 0x47)
    }

    @Test(.enabled(if: corpusRoot != nil))
    func directoryCallbacksReadTheRealRemoteShape() async throws {
        let root = try #require(corpusRoot)
        let folder = root.appending(path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS")
        let source = BluRayDiscSource.fileSystem(rootURL: folder, LocalDiscTree(root: folder))
        let catalog = try await BluRayDisc.catalog(source: source)
        #expect(catalog.titles.map(\.playlistID.rawValue) == [0])
        #expect(catalog.titles[0].clips[0].byteEnd == 169_881_600)
        let reader = try await BluRayDisc.open(source: source,
                                                playlistID: BluRayPlaylistID(rawValue: 0))
        let handle = try #require(reader.takeNativeHandle())
        defer { PBBlurayClose(handle) }
        var bytes = [UInt8](repeating: 0, count: 192)
        #expect(PBBlurayRead(handle, &bytes, Int32(bytes.count)) == 192)
        #expect(Array(bytes.prefix(5)) == [0x26, 0x5c, 0x57, 0xbc, 0x47])
    }

    @Test(.enabled(if: corpusRoot != nil))
    func callbackCatalogReadsAuthoritativeDiscName() async throws {
        let root = try #require(corpusRoot)
        let folder = root.appending(path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS")
        let metadata = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <disclib xmlns="urn:BDA:bdmv;disclib"
                     xmlns:di="urn:BDA:bdmv;discinfo">
              <di:discinfo><di:title><di:name>Injected Authoritative Name</di:name></di:title></di:discinfo>
            </disclib>
            """.utf8)
        let tree = MetadataDiscTree(base: LocalDiscTree(root: folder), metadata: metadata)
        let catalog = try await BluRayDisc.catalog(files: tree)
        #expect(catalog.optionalName == "Injected Authoritative Name")
    }

    @Test func metadataParserReadsOnlyStandardDiscNamePath() {
        let metadata = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <disclib xmlns="urn:BDA:bdmv;disclib"
                     xmlns:di="urn:BDA:bdmv;discinfo">
              <di:discinfo>
                <di:title><di:name>  Sintel Blu-ray  </di:name></di:title>
                <di:toc><di:title di:title_number="7"><di:name>Not a disc name</di:name></di:title></di:toc>
              </di:discinfo>
            </disclib>
            """.utf8)
        #expect(BluRayDiscMetadataParser.parseDiscName(metadata) == "Sintel Blu-ray")
    }

    @Test func metadataParserRejectsMalformedXMLAndWrongNamePath() {
        let malformed = Data("<disclib><discinfo><title>".utf8)
        let wrongPath = Data("""
            <disclib xmlns="urn:BDA:bdmv;disclib"
                     xmlns:di="urn:BDA:bdmv;discinfo">
              <di:discinfo><di:toc><di:title><di:name>Playlist label</di:name></di:title></di:toc></di:discinfo>
            </disclib>
            """.utf8)
        #expect(BluRayDiscMetadataParser.parseDiscName(malformed) == nil)
        #expect(BluRayDiscMetadataParser.parseDiscName(wrongPath) == nil)
    }

    @Test func metadataParserRejectsExternalEntities() {
        let metadata = Data("""
            <?xml version="1.0"?>
            <!DOCTYPE disclib [<!ENTITY xxe SYSTEM "file:///etc/passwd">]>
            <disclib xmlns="urn:BDA:bdmv;disclib"
                     xmlns:di="urn:BDA:bdmv;discinfo">
              <di:discinfo><di:title><di:name>&xxe;</di:name></di:title></di:discinfo>
            </disclib>
            """.utf8)
        #expect(BluRayDiscMetadataParser.parseDiscName(metadata) == nil)
    }

    @Test(.enabled(if: corpusRoot != nil))
    func rawM2TSIsNotMisidentifiedAsBluRayImage() throws {
        let root = try #require(corpusRoot)
        let file = root.appending(path:
            "DolbyVision-Profile7-FEL/FEL_test_for_AVS/BDMV/STREAM/00000.m2ts")
        var failure: BluRayDiscError?
        do { _ = try BluRayDisc.catalog(at: file) }
        catch { failure = error as? BluRayDiscError }
        guard case .some(.unsupported) = failure else {
            Issue.record("Raw M2TS was not classified as an unsupported disc image")
            return
        }
    }

    @Test(.enabled(if: corpusRoot != nil))
    func encryptedDiscIsRejectedEvenWhenItsPlaylistIsReadable() async throws {
        let root = try #require(corpusRoot)
        let folder = root.appending(path: "DolbyVision-Profile7-FEL/FEL_test_for_AVS")
        let tree = EncryptedDiscTree(base: LocalDiscTree(root: folder))
        var failure: BluRayDiscError?
        do { _ = try await BluRayDisc.catalog(files: tree) }
        catch { failure = error as? BluRayDiscError }
        #expect(failure == .encrypted)
    }

    @Test func malformedBDMVIndexIsReportedAsCorrupt() throws {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "enchron-corrupt-bluray-\(UUID().uuidString)")
        let bdmv = folder.appending(path: "BDMV")
        try FileManager.default.createDirectory(at: bdmv,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data([0x00, 0x01, 0x02]).write(to: bdmv.appending(path: "index.bdmv"))
        var failure: BluRayDiscError?
        do { _ = try BluRayDisc.catalog(at: folder) }
        catch { failure = error as? BluRayDiscError }
        guard case .corrupt = failure else {
            Issue.record("Malformed BDMV/index.bdmv was not classified as corrupt")
            return
        }
    }
}
