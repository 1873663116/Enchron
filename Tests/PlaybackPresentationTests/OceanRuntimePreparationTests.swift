@testable import OceanEnvironment
import Testing

@MainActor
struct OceanRuntimePreparationTests {
    @Test("concurrent opens share a calibration that is ready for subsequent opens")
    func repeatedOpens() async throws {
        let cache = SwellSpectrumCalibrationCache()
        let parameters = try OceanProbeParameters(OceanEnvironmentScene.authoredSimulation)
        #expect(cache.readyValue(for: parameters) == nil)
        async let first = cache.value(for: parameters)
        async let second = cache.value(for: parameters)
        for value in await [first, second] {
            #expect(abs(value.peakWaveNumber - 0.05235988) < 0.0000001)
            #expect(abs(value.discreteVariance - 0.01) < 0.0000001)
        }
        let cached = try #require(cache.readyValue(for: parameters))
        #expect(abs(cached.energyScale - 0.010000065) < 0.0000001)
    }

    @Test("wind, foam and presentation changes reuse the swell calibration")
    func unrelatedChanges() async throws {
        let cache = SwellSpectrumCalibrationCache()
        var component = OceanEnvironmentScene.authoredSimulation
        _ = await cache.value(for: try OceanProbeParameters(component))
        component.windSpeed = 20
        component.foamAmount = 0.5
        component.amplitude = 2
        component.iblIntensityExponent = -2
        let cached = try #require(cache.readyValue(for: try OceanProbeParameters(component)))
        #expect(abs(cached.energyScale - 0.010000065) < 0.0000001)
    }

    @Test("all swell and grid inputs invalidate calibration", arguments: [
        "wavelength", "height", "bandwidth", "spread", "direction", "depth", "lengthScales", "resolution"
    ])
    func changedInputs(input: String) async throws {
        let cache = SwellSpectrumCalibrationCache()
        var component = OceanEnvironmentScene.authoredSimulation
        _ = await cache.value(for: try OceanProbeParameters(component))
        var resolution = 512
        switch input {
        case "wavelength": component.swellWavelength = 100
        case "height": component.swellHeight = 0.8
        case "bandwidth": component.swellBandwidth = 0.3
        case "spread": component.swellSpread = 30
        case "direction": component.swellDirectionDegrees = 90
        case "depth": component.waterDepth = 20
        case "lengthScales": component.lengthScale0 = 800
        case "resolution": resolution = 256
        default: Issue.record("Unknown calibration input"); return
        }
        let parameters = try OceanProbeParameters(component, resolution: resolution)
        #expect(cache.readyValue(for: parameters) == nil)
        let calibrated = await cache.value(for: parameters)
        let variance: Float = input == "height" ? 0.04 : 0.01
        let peakWaveNumber: Float = input == "wavelength" ? 0.06283185 : 0.05235988
        #expect(abs(calibrated.discreteVariance - variance) < 0.0000001)
        #expect(abs(calibrated.peakWaveNumber - peakWaveNumber) < 0.0000001)
    }

    @Test("normal playback never requests foam readback, including after a parameter change")
    func foamDiagnosticsDisabled() {
        var schedule = FoamEvidenceSchedule(environment: [:])
        schedule.parametersDidChange(after: 240)
        let captured = (1...500).filter { schedule.take(frame: $0) }
        #expect(captured == [])
    }

    @Test("explicit diagnostics capture startup and changed foam once")
    func foamDiagnosticsEnabled() {
        var schedule = FoamEvidenceSchedule(environment: ["ENCHRON_OCEAN_FOAM_DIAGNOSTICS": "1"])
        schedule.parametersDidChange(after: 240)
        let captured = (1...500).filter { schedule.take(frame: $0) }
        #expect(captured == [1, 120, 240, 360])
        #expect(schedule.take(frame: 120) == false)
    }
}
