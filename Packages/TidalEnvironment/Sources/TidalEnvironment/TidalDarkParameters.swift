import Foundation
import zlib

nonisolated struct TidalDarkParameters: Sendable {
    static let tableWidth = 4096
    static let macroblockWidth = 1024

    let macroblocks: Data
    let codes: Data
    let tableHeight: Int

    var textureBytes: Int { macroblocks.count + codes.count }

    enum Failure: Error {
        case invalidContainer
        case unsupportedFormat
        case invalidStream(String)
        case invalidCodes
    }

    private struct Header: Decodable {
        let format: String
        let image_size: Int
        let macroblock: Int
        let grid_px: [Int]
        let slots_per_macroblock: [Int]
        let code_bits: Int
        let log2_lo: Float
        let log2_hi: Float
        let value_dtype: String
        let type_bit_order: String
        let level_bit_order: String
        let n_macroblocks: Int
        let n_values: Int
        let streams: [String: Stream]
    }

    private struct Stream: Decodable {
        let offset: Int
        let compressed_size: Int
        let raw_size: Int
        let crc32: UInt32
    }

    static func load(from url: URL) throws -> Self {
        try parse(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func parse(_ data: Data) throws -> Self {
        guard data.count >= 8, data.prefix(4) == Data("SKDP".utf8) else {
            throw Failure.invalidContainer
        }
        let headerCount = data.withUnsafeBytes {
            Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)))
        }
        guard headerCount <= data.count - 8 else { throw Failure.invalidContainer }
        let header = try JSONDecoder().decode(Header.self, from: data[8..<(8 + headerCount)])
        guard header.format == "SkyPool dark-state params v1",
              header.image_size == 16384, header.macroblock == 16,
              header.grid_px == [16, 8, 4, 2],
              header.slots_per_macroblock == [3, 12, 48, 192],
              header.code_bits == 10, header.log2_lo == -14, header.log2_hi == 4,
              header.value_dtype == "<u2", header.type_bit_order == "big",
              header.level_bit_order == "little", header.n_macroblocks == 1024 * 1024,
              header.n_values > 0, header.n_values < 1 << 24,
              Set(header.streams.keys) == ["values", "types", "levels"] else {
            throw Failure.unsupportedFormat
        }
        let height = (header.n_values + tableWidth - 1) / tableWidth
        func decompress(_ name: String, count: Int, paddedCount: Int? = nil) throws -> Data {
            guard let stream = header.streams[name],
                  stream.offset >= 8 + headerCount, stream.offset <= data.count,
                  stream.compressed_size > 0, stream.compressed_size <= data.count - stream.offset,
                  stream.raw_size == count else {
                throw Failure.invalidStream(name)
            }
            var output = Data(count: paddedCount ?? count)
            var decodedCount = uLongf(count)
            let status = output.withUnsafeMutableBytes { destination in
                data.withUnsafeBytes { source in
                    uncompress(
                        destination.bindMemory(to: Bytef.self).baseAddress, &decodedCount,
                        source.bindMemory(to: Bytef.self).baseAddress!.advanced(by: stream.offset),
                        uLong(stream.compressed_size)
                    )
                }
            }
            guard status == Z_OK, decodedCount == count else { throw Failure.invalidStream(name) }
            let checksum = output.withUnsafeBytes {
                zlib.crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(count))
            }
            guard UInt32(checksum) == stream.crc32 else { throw Failure.invalidStream(name) }
            return output
        }
        var values = try decompress("values", count: header.n_values * 2, paddedCount: tableWidth * height * 2)
        let types = try decompress("types", count: (header.n_values + 7) / 8)
        let levels = try decompress("levels", count: header.n_macroblocks / 4)
        var macroblocks = Data(count: header.n_macroblocks * 4)
        try macroblocks.withUnsafeMutableBytes { raw in
            try levels.withUnsafeBytes { levelBytes in
                let output = raw.bindMemory(to: UInt8.self)
                let input = levelBytes.bindMemory(to: UInt8.self)
                var offset = 0
                for index in 0..<header.n_macroblocks {
                    let level = Int((input[index / 4] >> (2 * (index % 4))) & 3)
                    output[index * 4] = UInt8(truncatingIfNeeded: offset)
                    output[index * 4 + 1] = UInt8(truncatingIfNeeded: offset >> 8)
                    output[index * 4 + 2] = UInt8(truncatingIfNeeded: offset >> 16)
                    output[index * 4 + 3] = UInt8(level)
                    offset += header.slots_per_macroblock[level]
                }
                guard offset == header.n_values else { throw Failure.invalidCodes }
            }
        }
        try values.withUnsafeMutableBytes { raw in
            try types.withUnsafeBytes { typeBytes in
                let output = raw.bindMemory(to: UInt16.self)
                let flags = typeBytes.bindMemory(to: UInt8.self)
                for index in 0..<header.n_values {
                    if index % 65536 == 0 { try Task.checkCancellation() }
                    let code = UInt16(littleEndian: output[index])
                    guard code <= 1023 else { throw Failure.invalidCodes }
                    let absolute = UInt16((flags[index / 8] >> (7 - index % 8)) & 1)
                    output[index] = Float16(code + absolute * 1024).bitPattern.littleEndian
                }
            }
        }
        return Self(macroblocks: macroblocks, codes: values, tableHeight: height)
    }
}
