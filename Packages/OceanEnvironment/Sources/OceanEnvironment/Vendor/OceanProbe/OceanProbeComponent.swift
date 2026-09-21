import RealityKit

/// FFT 格点边长的单一真相源。
///
/// Metal 侧的 `FFT_SIZE` / `LOG_SIZE` 是编译期常量：蝶形运算的
/// threadgroup 缓冲按 `FFT_SIZE` 分配，每一趟 IFFT 用
/// `position + uint2(FFT_SIZE / 2, 0)` 读取上半区。若 Swift 侧
/// 单独下调纹理尺寸，这些读取全部越界返回零，位移与坡度塌成常数，
/// 海面变成一面平镜。`CascadeLayout` 的 k 网格截断
/// (`cutoffHigh = pi * N / L`) 与 `FoamParameters.metersPerTexel`
/// 同样按 N 标定，必须一并派生。
enum OceanSimulationGrid {
    static let resolution = 512
    static let logResolution = 9
}

public struct OceanProbeComponent: Component, Codable {
    public var isEnabled: Bool
    public var seed: Int
    public var amplitude: Float
    public var timeScale: Float
    public var windSpeed: Float
    public var windDirectionDegrees: Float
    public var fetch: Float
    public var windAlignment: Float
    public var crossSeaAmount: Float
    public var crossSeaAngleDegrees: Float
    public var swellDirectionDegrees: Float
    public var swellWavelength: Float
    public var swellHeight: Float
    public var swellSpread: Float
    public var swellBandwidth: Float
    public var waterDepth: Float
    public var choppiness: Float
    public var repeatTime: Float
    public var foamBias: Float
    public var foamPower: Float
    public var foamAmount: Float
    public var foamDecay: Float
    public var lengthScale0: Float
    public var lengthScale1: Float
    public var lengthScale2: Float
    public var lengthScale3: Float
    public var envelopeAmount: Float
    public var envelopeScaleMeters: Float
    public var iblIntensityExponent: Float

    public init(
        isEnabled: Bool = true,
        seed: Int = 28,
        amplitude: Float = 1,
        timeScale: Float = 0.5,
        windSpeed: Float = 5.5,
        windDirectionDegrees: Float = 130,
        fetch: Float = 50_000,
        windAlignment: Float = 0.75,
        crossSeaAmount: Float = 1,
        crossSeaAngleDegrees: Float = 37.242256,
        swellDirectionDegrees: Float = 75,
        swellWavelength: Float = 120,
        swellHeight: Float = 0.8,
        swellSpread: Float = 12,
        swellBandwidth: Float = 0.12,
        waterDepth: Float = 2,
        choppiness: Float = 1.2,
        repeatTime: Float = 200,
        foamBias: Float = 0.24,
        foamPower: Float = 1.5,
        foamAmount: Float = 0.82,
        foamDecay: Float = 3,
        lengthScale0: Float = 300,
        lengthScale1: Float = 97,
        lengthScale2: Float = 31,
        lengthScale3: Float = 10.5,
        envelopeAmount: Float = 0.35,
        envelopeScaleMeters: Float = 2500,
        iblIntensityExponent: Float = -0.5
    ) {
        self.isEnabled = isEnabled
        self.seed = seed
        self.amplitude = amplitude
        self.timeScale = timeScale
        self.windSpeed = windSpeed
        self.windDirectionDegrees = windDirectionDegrees
        self.fetch = fetch
        self.windAlignment = windAlignment
        self.crossSeaAmount = crossSeaAmount
        self.crossSeaAngleDegrees = crossSeaAngleDegrees
        self.swellDirectionDegrees = swellDirectionDegrees
        self.swellWavelength = swellWavelength
        self.swellHeight = swellHeight
        self.swellSpread = swellSpread
        self.swellBandwidth = swellBandwidth
        self.waterDepth = waterDepth
        self.choppiness = choppiness
        self.repeatTime = repeatTime
        self.foamBias = foamBias
        self.foamPower = foamPower
        self.foamAmount = foamAmount
        self.foamDecay = foamDecay
        self.lengthScale0 = lengthScale0
        self.lengthScale1 = lengthScale1
        self.lengthScale2 = lengthScale2
        self.lengthScale3 = lengthScale3
        self.envelopeAmount = envelopeAmount
        self.envelopeScaleMeters = envelopeScaleMeters
        self.iblIntensityExponent = iblIntensityExponent
    }
}

enum CascadeLayoutError: Error {
    case invalidResolution(Int)
    case invalidLengthScales(SIMD4<Float>)
}

struct CascadeLayout: Hashable, Sendable {
    let resolution: Int
    let lengthScales: SIMD4<Float>
    let inverseLengthScales: SIMD4<Float>
    let cutoffLow: SIMD4<Float>
    let cutoffHigh: SIMD4<Float>

    init(lengthScales: SIMD4<Float>, resolution: Int) throws {
        guard resolution > 0 else {
            throw CascadeLayoutError.invalidResolution(resolution)
        }
        guard lengthScales.x.isFinite,
              lengthScales.y.isFinite,
              lengthScales.z.isFinite,
              lengthScales.w.isFinite,
              lengthScales.x > lengthScales.y,
              lengthScales.y > lengthScales.z,
              lengthScales.z > lengthScales.w,
              lengthScales.w > 0
        else {
            throw CascadeLayoutError.invalidLengthScales(lengthScales)
        }

        self.resolution = resolution
        self.lengthScales = lengthScales
        inverseLengthScales = 1 / lengthScales
        cutoffHigh = Float.pi * Float(resolution) / lengthScales
        cutoffLow = SIMD4<Float>(
            0.0001,
            cutoffHigh.x,
            cutoffHigh.y,
            cutoffHigh.z
        )
    }

    func owners(of waveNumber: Float) -> [Int] {
        (0 ..< 4).filter {
            cutoffLow[$0] <= waveNumber && waveNumber < cutoffHigh[$0]
        }
    }
}

struct FoamParameters: Equatable, Sendable {
    static let resolution = OceanSimulationGrid.resolution

    let bias: Float
    let power: Float
    let amount: Float
    let decay: Float

    var sourceFreeRetentionPerSecond: Float {
        exp(-decay)
    }

    var maximumSourceEquilibrium: Float {
        amount * 60 * bias / decay
    }

    static func metersPerTexel(
        for cascades: CascadeLayout
    ) -> SIMD4<Float> {
        cascades.lengthScales / Float(resolution)
    }
}

struct SwellSpectrumCalibration: Equatable, Sendable {
    struct Input: Hashable, Sendable {
        let cascades: CascadeLayout
        let swellWavelength: Float
        let swellHeight: Float
        let swellBandwidth: Float
        let swellSpreadRadians: Float
        let swellDirectionRadians: Float
        let waterDepth: Float

        init(_ parameters: OceanProbeParameters) {
            cascades = parameters.cascades
            swellWavelength = parameters.swellWavelength
            swellHeight = parameters.swellHeight
            swellBandwidth = parameters.swellBandwidth
            swellSpreadRadians = parameters.swellSpreadRadians
            swellDirectionRadians = parameters.swellDirectionRadians
            waterDepth = parameters.waterDepth
        }
    }

    let peakWaveNumber: Float
    let cascade: Int?
    let peakAngularFrequency: Float
    let effectiveAngularFrequencySigma: Float
    let effectiveDirectionalSigma: Float
    let energyScale: Float
    let discreteVariance: Float
    let centroidDirectionRadians: Float
    let centroidWavelength: Float

    private static let gravity: Float = 9.81

    init(parameters: Input) {
        let cascades = parameters.cascades
        let peakWaveNumber = 2 * Float.pi / parameters.swellWavelength
        let cascade = cascades.owners(of: peakWaveNumber).first
        let peakAngularFrequency = Self.dispersion(
            peakWaveNumber,
            depth: parameters.waterDepth
        )
        let peakDerivative = Self.dispersionDerivative(
            peakWaveNumber,
            depth: parameters.waterDepth
        )
        let ownerDeltaK = cascade.map {
            2 * Float.pi / cascades.lengthScales[$0]
        } ?? 0
        let effectiveAngularFrequencySigma = max(
            parameters.swellBandwidth * peakAngularFrequency,
            0.5 * peakDerivative * ownerDeltaK
        )
        let effectiveDirectionalSigma = max(
            parameters.swellSpreadRadians,
            0.5 * atan2(ownerDeltaK, peakWaveNumber)
        )

        let rootTwoPi = sqrt(2 * Float.pi)
        var unitIntegral: Double = 0
        var centroidX: Double = 0
        var centroidY: Double = 0
        var waveNumberMoment: Double = 0
        let halfResolution = Float(cascades.resolution) * 0.5

        for cascadeIndex in 0 ..< 4 {
            let deltaK = 2 * Float.pi / cascades.lengthScales[cascadeIndex]
            for y in 0 ..< cascades.resolution {
                let ky = (Float(y) - halfResolution) * deltaK
                for x in 0 ..< cascades.resolution {
                    let kx = (Float(x) - halfResolution) * deltaK
                    let waveNumber = hypot(kx, ky)
                    guard cascades.cutoffLow[cascadeIndex] <= waveNumber,
                          waveNumber < cascades.cutoffHigh[cascadeIndex]
                    else {
                        continue
                    }
                    let omega = Self.dispersion(
                        waveNumber,
                        depth: parameters.waterDepth
                    )
                    let normalizedOmega = (
                        omega - peakAngularFrequency
                    ) / effectiveAngularFrequencySigma
                    let angle = atan2(ky, kx)
                    let angleDelta = atan2(
                        sin(angle - parameters.swellDirectionRadians),
                        cos(angle - parameters.swellDirectionRadians)
                    )
                    let frequencyDensity = exp(
                        -0.5 * normalizedOmega * normalizedOmega
                    ) / (rootTwoPi * effectiveAngularFrequencySigma)
                    let normalizedAngle = angleDelta / effectiveDirectionalSigma
                    let directionDensity = exp(
                        -0.5 * normalizedAngle * normalizedAngle
                    ) / (rootTwoPi * effectiveDirectionalSigma)
                    let measure = abs(
                        Self.dispersionDerivative(
                            waveNumber,
                            depth: parameters.waterDepth
                        )
                    ) / max(waveNumber, 1e-6) * deltaK * deltaK
                    let weight = Double(frequencyDensity * directionDensity * measure)
                    unitIntegral += weight
                    centroidX += weight * Double(cos(angle))
                    centroidY += weight * Double(sin(angle))
                    waveNumberMoment += weight * Double(waveNumber)
                }
            }
        }

        let targetVariance = parameters.swellHeight * parameters.swellHeight / 16
        let energyScale = unitIntegral > 0
            ? targetVariance / Float(unitIntegral)
            : 0
        let meanWaveNumber = unitIntegral > 0
            ? Float(waveNumberMoment / unitIntegral)
            : peakWaveNumber

        self.peakWaveNumber = peakWaveNumber
        self.cascade = cascade
        self.peakAngularFrequency = peakAngularFrequency
        self.effectiveAngularFrequencySigma = effectiveAngularFrequencySigma
        self.effectiveDirectionalSigma = effectiveDirectionalSigma
        self.energyScale = energyScale
        discreteVariance = energyScale * Float(unitIntegral)
        centroidDirectionRadians = Float(atan2(centroidY, centroidX))
        centroidWavelength = 2 * .pi / max(meanWaveNumber, 1e-6)
    }

    private static func dispersion(_ waveNumber: Float, depth: Float) -> Float {
        sqrt(gravity * waveNumber * tanh(min(waveNumber * depth, 20)))
    }

    private static func dispersionDerivative(
        _ waveNumber: Float,
        depth: Float
    ) -> Float {
        let kh = min(waveNumber * depth, 20)
        let tanhKH = tanh(kh)
        let coshKH = cosh(kh)
        let derivative = depth * waveNumber / (coshKH * coshKH) + tanhKH
        return gravity * derivative
            / max(2 * dispersion(waveNumber, depth: depth), 1e-6)
    }
}

struct SwellSpectrumDiagnostic: Equatable, Sendable {
    let calibration: SwellSpectrumCalibration
    let quantizedAngularFrequency: Float
    let loopHarmonic: Int

    init(parameters: OceanProbeParameters, calibration: SwellSpectrumCalibration) {
        self.calibration = calibration
        let baseFrequency = 2 * Float.pi / parameters.repeatTime
        loopHarmonic = Int(floor(calibration.peakAngularFrequency / baseFrequency))
        quantizedAngularFrequency = Float(loopHarmonic) * baseFrequency
    }
}

struct OceanProbeParameters: Equatable, Sendable {
    let seed: UInt32
    let amplitude: Float
    let timeScale: Float
    let windSpeed: Float
    let windDirectionRadians: Float
    let fetch: Float
    let windAlignment: Float
    let crossSeaAmount: Float
    let crossSeaAngleRadians: Float
    let swellDirectionRadians: Float
    let swellWavelength: Float
    let swellHeight: Float
    let swellSpreadRadians: Float
    let swellBandwidth: Float
    let waterDepth: Float
    let choppiness: Float
    let repeatTime: Float
    let foam: FoamParameters
    let cascades: CascadeLayout
    let envelopeAmount: Float
    let envelopeScaleMeters: Float
    let iblIntensityExponent: Float

    init(
        _ component: OceanProbeComponent,
        resolution: Int = OceanSimulationGrid.resolution
    ) throws {
        seed = UInt32(clamping: component.seed)
        amplitude = component.amplitude.finiteOr(1).clamped(to: 0 ... 3)
        timeScale = component.timeScale.finiteOr(0.5).clamped(to: 0 ... 4)
        windSpeed = component.windSpeed.finiteOr(5.5).clamped(to: 1 ... 80)
        windDirectionRadians = (
            component.windDirectionDegrees.finiteOr(130) * .pi / 180
        ).truncatingRemainder(dividingBy: 2 * .pi)
        fetch = component.fetch.finiteOr(50_000).clamped(to: 100 ... 1_000_000)
        windAlignment = component.windAlignment.finiteOr(0.75).clamped(to: 0 ... 1)
        crossSeaAmount = component.crossSeaAmount.finiteOr(1).clamped(to: 0 ... 1)
        crossSeaAngleRadians = (
            component.crossSeaAngleDegrees.finiteOr(37.242256) * .pi / 180
        ).clamped(to: -Float.pi ... Float.pi)
        swellDirectionRadians = (
            component.swellDirectionDegrees.finiteOr(75) * .pi / 180
        ).truncatingRemainder(dividingBy: 2 * .pi)
        swellWavelength = component.swellWavelength.finiteOr(120)
            .clamped(to: 60 ... 200)
        swellHeight = component.swellHeight.finiteOr(0.8).clamped(to: 0 ... 5)
        swellSpreadRadians = component.swellSpread.finiteOr(12)
            .clamped(to: 0 ... 90) * .pi / 180
        swellBandwidth = component.swellBandwidth.finiteOr(0.12)
            .clamped(to: 0 ... 1)
        waterDepth = component.waterDepth.finiteOr(2).clamped(to: 0.25 ... 1_000)
        choppiness = component.choppiness.finiteOr(1.2).clamped(to: 0 ... 3)
        repeatTime = component.repeatTime.finiteOr(200).clamped(to: 1 ... 14_400)
        foam = FoamParameters(
            bias: component.foamBias.finiteOr(0.24).clamped(to: 0 ... 1),
            power: component.foamPower.finiteOr(1.5).clamped(to: 0.1 ... 8),
            amount: component.foamAmount.finiteOr(0.82).clamped(to: 0 ... 2),
            decay: component.foamDecay.finiteOr(3).clamped(to: 0.01 ... 10)
        )
        cascades = try CascadeLayout(
            lengthScales: SIMD4<Float>(
                component.lengthScale0,
                component.lengthScale1,
                component.lengthScale2,
                component.lengthScale3
            ),
            resolution: resolution
        )
        envelopeAmount = component.envelopeAmount.finiteOr(0.35)
            .clamped(to: 0 ... 1)
        envelopeScaleMeters = component.envelopeScaleMeters.finiteOr(2500)
            .clamped(to: 500 ... 8000)
        iblIntensityExponent = component.iblIntensityExponent.finiteOr(-0.5)
            .clamped(to: -8 ... 8)
    }
}

private extension Float {
    func clamped(to range: ClosedRange<Float>) -> Float {
        min(max(self, range.lowerBound), range.upperBound)
    }

    func finiteOr(_ fallback: Float) -> Float {
        isFinite ? self : fallback
    }
}
