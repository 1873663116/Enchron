import Foundation

// swiftlint:disable nesting
extension PlaybackCoreDomain {
    public struct HDRProbeRGB: Equatable, Sendable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public var maxChannel: Double {
            max(red, green, blue)
        }
    }

    public struct HDRProbeStatistics: Equatable, Sendable {
        public let maxRGB: HDRProbeRGB
        public let averageRGB: HDRProbeRGB
        public let p99Luminance: Double
        public let p95Luminance: Double
        public let countAbove1: Int
        public let countAbove2: Int
        public let sampledPixelCount: Int

        public init(
            maxRGB: HDRProbeRGB,
            averageRGB: HDRProbeRGB,
            p99Luminance: Double,
            p95Luminance: Double,
            countAbove1: Int,
            countAbove2: Int,
            sampledPixelCount: Int
        ) {
            self.maxRGB = maxRGB
            self.averageRGB = averageRGB
            self.p99Luminance = p99Luminance
            self.p95Luminance = p95Luminance
            self.countAbove1 = countAbove1
            self.countAbove2 = countAbove2
            self.sampledPixelCount = sampledPixelCount
        }
    }

    public struct HDRProbeSample: Equatable, Sendable {
        public enum Source: String, Equatable, Sendable {
            case syntheticEDR
            case mpvDrawable
        }

        public let source: Source
        public let hdrOutputEnabled: Bool?
        public let pixelFormat: String
        public let colorspace: String
        public let width: Int
        public let height: Int
        public let statistics: HDRProbeStatistics
        public let hostTime: Date
        public let videoTime: Double?
        public let contract: String

        public init(
            source: Source,
            hdrOutputEnabled: Bool?,
            pixelFormat: String,
            colorspace: String,
            width: Int,
            height: Int,
            statistics: HDRProbeStatistics,
            hostTime: Date = Date(),
            videoTime: Double?,
            contract: String
        ) {
            self.source = source
            self.hdrOutputEnabled = hdrOutputEnabled
            self.pixelFormat = pixelFormat
            self.colorspace = colorspace
            self.width = width
            self.height = height
            self.statistics = statistics
            self.hostTime = hostTime
            self.videoTime = videoTime
            self.contract = contract
        }
    }

    public struct HDRProbeDelta: Equatable, Sendable {
        public let maxRGBDelta: Double
        public let p99LuminanceDelta: Double
        public let countAbove1Delta: Int
        public let countAbove2Delta: Int

        public init(onSample: HDRProbeSample, offSample: HDRProbeSample) {
            self.maxRGBDelta = onSample.statistics.maxRGB.maxChannel
                - offSample.statistics.maxRGB.maxChannel
            self.p99LuminanceDelta = onSample.statistics.p99Luminance
                - offSample.statistics.p99Luminance
            self.countAbove1Delta = onSample.statistics.countAbove1
                - offSample.statistics.countAbove1
            self.countAbove2Delta = onSample.statistics.countAbove2
                - offSample.statistics.countAbove2
        }
    }

    public enum HDRProbeCalculator {
        public struct Pixel: Sendable {
            public let red: Double
            public let green: Double
            public let blue: Double

            public init(red: Double, green: Double, blue: Double) {
                self.red = red
                self.green = green
                self.blue = blue
            }
        }

        public static func statistics(for pixels: [Pixel]) -> HDRProbeStatistics {
            guard pixels.isEmpty == false else {
                return emptyStatistics
            }

            var maxRed = 0.0
            var maxGreen = 0.0
            var maxBlue = 0.0
            var totalRed = 0.0
            var totalGreen = 0.0
            var totalBlue = 0.0
            var countAbove1 = 0
            var countAbove2 = 0
            var luminanceValues: [Double] = []
            luminanceValues.reserveCapacity(pixels.count)

            for pixel in pixels {
                maxRed = max(maxRed, pixel.red)
                maxGreen = max(maxGreen, pixel.green)
                maxBlue = max(maxBlue, pixel.blue)
                totalRed += pixel.red
                totalGreen += pixel.green
                totalBlue += pixel.blue

                let maxChannel = max(pixel.red, pixel.green, pixel.blue)
                if maxChannel > 1.0 {
                    countAbove1 += 1
                }
                if maxChannel > 2.0 {
                    countAbove2 += 1
                }
                luminanceValues.append(linearDisplayP3Luminance(pixel))
            }

            luminanceValues.sort()
            let count = Double(pixels.count)
            return HDRProbeStatistics(
                maxRGB: HDRProbeRGB(red: maxRed, green: maxGreen, blue: maxBlue),
                averageRGB: averageRGB(red: totalRed, green: totalGreen, blue: totalBlue, count: count),
                p99Luminance: percentile(0.99, in: luminanceValues),
                p95Luminance: percentile(0.95, in: luminanceValues),
                countAbove1: countAbove1,
                countAbove2: countAbove2,
                sampledPixelCount: pixels.count
            )
        }

        private static var emptyStatistics: HDRProbeStatistics {
            HDRProbeStatistics(
                maxRGB: HDRProbeRGB(red: 0, green: 0, blue: 0),
                averageRGB: HDRProbeRGB(red: 0, green: 0, blue: 0),
                p99Luminance: 0,
                p95Luminance: 0,
                countAbove1: 0,
                countAbove2: 0,
                sampledPixelCount: 0
            )
        }

        private static func averageRGB(red: Double, green: Double, blue: Double, count: Double) -> HDRProbeRGB {
            HDRProbeRGB(red: red / count, green: green / count, blue: blue / count)
        }

        private static func linearDisplayP3Luminance(_ pixel: Pixel) -> Double {
            0.228_974_564_1 * pixel.red
                + 0.691_738_521_8 * pixel.green
                + 0.079_286_914_1 * pixel.blue
        }

        private static func percentile(_ percentile: Double, in sortedValues: [Double]) -> Double {
            guard sortedValues.isEmpty == false else { return 0 }
            let rawIndex = Int(ceil(percentile * Double(sortedValues.count))) - 1
            let clampedIndex = min(max(rawIndex, 0), sortedValues.count - 1)
            return sortedValues[clampedIndex]
        }
    }
}
// swiftlint:enable nesting
