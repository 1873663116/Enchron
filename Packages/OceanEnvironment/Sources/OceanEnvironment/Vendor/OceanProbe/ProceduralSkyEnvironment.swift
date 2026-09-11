import CoreGraphics
import Foundation
import RealityKit
import simd

/// Builds the ocean's image-based light from the sky the ocean is standing under.
///
/// The sky itself is an 8K equirectangular HDRI on the dome. Decoding that file
/// a second time here, only to average it down to a 128x64 irradiance probe,
/// would cost half a gigabyte of transient memory to produce a few kilobytes of
/// result. It is also unnecessary: the panorama is a closed eight-okta
/// overcast, and measurement of the file says it is very nearly azimuthally
/// uniform — the relative standard deviation around a ring of constant
/// elevation averages 0.10 over the whole upper hemisphere and never exceeds
/// 0.21. Practically all of its irradiance is therefore carried by a single
/// elevation profile.
///
/// So the environment is that profile, fitted to the file rather than invented:
/// a quadratic in sin(elevation), per channel, whose residual against the
/// azimuthal mean of the real panorama is 0.014 in linear radiance — about 2.5%
/// of the mean, and well under the azimuthal variation it is already averaging
/// over. The constants below are that fit and nothing else; if the HDRI is
/// replaced, re-measure them with `.scratch/…/exrdump.swift` and refit.
struct SkyAppearance: Equatable {
    /// Matches the material's `SkyGain`, so the probe tracks any re-levelling
    /// of the dome.
    var skyGain: Float = 1

    /// Linear Rec.709 radiance of the panorama, per channel, as
    /// `a + b·sin(elevation) + c·sin²(elevation)`. Rows are R, G, B.
    var profile: (
        SIMD3<Float>, SIMD3<Float>, SIMD3<Float>
    ) = (
        SIMD3<Float>(0.3121, 0.3161, 0.0635),
        SIMD3<Float>(0.3087, 0.3445, 0.0636),
        SIMD3<Float>(0.3304, 0.3986, 0.1100)
    )

    /// Below the horizon the panorama is the sea, not the sky, and the water
    /// should not be lit by a reflection of itself.
    var seaColor = SIMD3<Float>(0.055, 0.070, 0.086)

    static func == (a: SkyAppearance, b: SkyAppearance) -> Bool {
        a.skyGain == b.skyGain
            && a.profile.0 == b.profile.0
            && a.profile.1 == b.profile.1
            && a.profile.2 == b.profile.2
            && a.seaColor == b.seaColor
    }

    /// Reads whichever inputs the authored material publishes, leaving the rest
    /// at the values the material ships with.
    init(material: ShaderGraphMaterial? = nil) {
        guard let material else { return }
        if case let .float(value)? = material.getParameter(name: "SkyGain") {
            skyGain = value
        }
    }

    func color(towards direction: SIMD3<Float>) -> SIMD3<Float> {
        let sine = max(min(direction.y, 1), -1)
        let sky = SIMD3<Float>(
            profile.0.x + profile.0.y * sine + profile.0.z * sine * sine,
            profile.1.x + profile.1.y * sine + profile.1.z * sine * sine,
            profile.2.x + profile.2.y * sine + profile.2.z * sine * sine
        ) * skyGain
        // The profile is only fitted above the horizon; below it the probe sees
        // water. A few degrees of blend keeps the transition from ringing in
        // the low-order terms RealityKit fits to this image.
        return mix(seaColor, simd_max(sky, .zero), smoothstep(-0.05, 0.02, sine))
    }

    func makeEquirectangularImage(width: Int = 128, height: Int = 64) -> CGImage? {
        var pixels = [Float](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            let polar = (Float(row) + 0.5) / Float(height) * .pi
            let sinPolar = sin(polar)
            let cosPolar = cos(polar)
            for column in 0 ..< width {
                let azimuth = (Float(column) + 0.5) / Float(width) * 2 * .pi - .pi
                let direction = SIMD3<Float>(
                    sinPolar * sin(azimuth),
                    cosPolar,
                    -sinPolar * cos(azimuth)
                )
                let color = self.color(towards: direction)
                let base = (row * width + column) * 4
                pixels[base] = color.x
                pixels[base + 1] = color.y
                pixels[base + 2] = color.z
                pixels[base + 3] = 1
            }
        }
        let bytes = pixels.withUnsafeBufferPointer { Data(buffer: $0) }
        guard let provider = CGDataProvider(data: bytes as CFData),
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        else {
            return nil
        }
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 32,
            bitsPerPixel: 128,
            bytesPerRow: width * 16,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.floatComponents.rawValue
                | CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

private func smoothstep(_ low: Float, _ high: Float, _ value: Float) -> Float {
    guard high > low else { return value < low ? 0 : 1 }
    let t = min(max((value - low) / (high - low), 0), 1)
    return t * t * (3 - 2 * t)
}

private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
    a + (b - a) * t
}
