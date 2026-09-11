import OSLog
import RealityKit

struct SimulationTickOffer: Equatable {
    let sequence: UInt64
    let sampleTime: Float
}

struct SimulationClock {
    private var pending: SimulationTickOffer?
    private var nextSequence: UInt64 = 0

    mutating func offer(sceneTime: Float) -> SimulationTickOffer? {
        pending = SimulationTickOffer(
            sequence: nextSequence,
            sampleTime: sceneTime
        )
        return pending
    }

    mutating func commit(_ offer: SimulationTickOffer) {
        precondition(pending == offer)
        pending = nil
        nextSequence &+= 1
    }

    mutating func suspend() {
        pending = nil
    }
}

private struct SpectrumControlSnapshot: Equatable {
    let windSpeed: Float
    let windDirectionDegrees: Float
    let windAlignment: Float
    let crossSeaAmount: Float
    let crossSeaAngleDegrees: Float
    let swellDirectionDegrees: Float
    let swellWavelength: Float
    let swellHeight: Float
    let swellSpread: Float
    let swellBandwidth: Float

    init(component: OceanProbeComponent, parameters: OceanProbeParameters) {
        windSpeed = parameters.windSpeed
        windDirectionDegrees = component.windDirectionDegrees
        windAlignment = parameters.windAlignment
        crossSeaAmount = parameters.crossSeaAmount
        crossSeaAngleDegrees = component.crossSeaAngleDegrees
        swellDirectionDegrees = component.swellDirectionDegrees
        swellWavelength = parameters.swellWavelength
        swellHeight = parameters.swellHeight
        swellSpread = component.swellSpread
        swellBandwidth = parameters.swellBandwidth
    }
}

private struct FoamControlSnapshot: Equatable {
    let bias: Float
    let power: Float
    let amount: Float
    let decay: Float
    let sourceFreeRetentionPerSecond: Float

    init(parameters: OceanProbeParameters) {
        bias = parameters.foam.bias
        power = parameters.foam.power
        amount = parameters.foam.amount
        decay = parameters.foam.decay
        sourceFreeRetentionPerSecond = parameters.foam.sourceFreeRetentionPerSecond
    }
}

struct RuntimeDiagnosticsSummary: Equatable {
    let windowSeconds: Double
    let renderFramesPerSecond: Double
    let acceptedSimulationTicks: Int
    let acceptedTicksPerSecond: Double
    let simulationGPUMedianMilliseconds: Double?
    let presentationGPUMedianMilliseconds: Double?
}

struct RuntimeDiagnostics {
    static let windowSeconds: Double = 5

    private var isActive = false
    private var elapsedSeconds: Double = 0
    private var renderFrames = 0
    private var simulationGPUTimeMilliseconds: [Double] = []
    private var presentationGPUTimeMilliseconds: [Double] = []
    private var acceptedSimulationTicks = 0

    mutating func record(
        frameDeltaTime: Double,
        acceptedSimulationTick: Bool,
        completedSimulationGPUMilliseconds: Double?,
        completedPresentationGPUMilliseconds: Double?
    ) -> RuntimeDiagnosticsSummary? {
        isActive = true
        if frameDeltaTime.isFinite, frameDeltaTime > 0 {
            elapsedSeconds += frameDeltaTime
        }
        renderFrames += 1
        acceptedSimulationTicks += acceptedSimulationTick ? 1 : 0
        if let milliseconds = completedSimulationGPUMilliseconds,
           milliseconds.isFinite,
           milliseconds >= 0
        {
            simulationGPUTimeMilliseconds.append(milliseconds)
        }
        if let milliseconds = completedPresentationGPUMilliseconds,
           milliseconds.isFinite,
           milliseconds >= 0
        {
            presentationGPUTimeMilliseconds.append(milliseconds)
        }
        guard elapsedSeconds + 1e-9 >= Self.windowSeconds else {
            return nil
        }
        let summary = RuntimeDiagnosticsSummary(
            windowSeconds: elapsedSeconds,
            renderFramesPerSecond: Double(renderFrames) / elapsedSeconds,
            acceptedSimulationTicks: acceptedSimulationTicks,
            acceptedTicksPerSecond: Double(acceptedSimulationTicks)
                / elapsedSeconds,
            simulationGPUMedianMilliseconds: Self.optionalMedian(
                simulationGPUTimeMilliseconds
            ),
            presentationGPUMedianMilliseconds: Self.optionalMedian(
                presentationGPUTimeMilliseconds
            )
        )
        resetMeasurements()
        return summary
    }

    mutating func suspend() {
        isActive = false
        resetMeasurements()
    }

    private mutating func resetMeasurements() {
        elapsedSeconds = 0
        renderFrames = 0
        simulationGPUTimeMilliseconds.removeAll(keepingCapacity: true)
        presentationGPUTimeMilliseconds.removeAll(keepingCapacity: true)
        acceptedSimulationTicks = 0
    }

    private static func optionalMedian(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : median(values)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) * 0.5
            : sorted[middle]
    }
}

@MainActor
public struct OceanProbeSystem: System {
    static let surfaceName = "OceanProbeSurface"
    static let materialSourceName = "OceanMaterialSource"
    static let skyDomeName = "OceanSkyDome"

    private static let query = EntityQuery(
        where: .has(OceanProbeComponent.self)
    )
    private static let logger = Logger(
        subsystem: "dev.enchron.ocean-probe",
        category: "simulation"
    )

    private var elapsedTime: Float = 0
    private var simulationClock = SimulationClock()
    private var renderer: OceanProbeRenderer?
    private var rendererCreationFailed = false
    private var parameterFailureReported = false
    private var environmentLightingFailureReported = false
    private var lastSpectrumControls: SpectrumControlSnapshot?
    private var lastFoamControls: FoamControlSnapshot?
    private var runtimeDiagnostics = RuntimeDiagnostics()

    public init(scene: Scene) {
        Self.logger.info("OceanProbeSystem initialized in application runtime")
    }

    public mutating func update(context: SceneUpdateContext) {
        elapsedTime += Float(context.deltaTime)

        for entity in context.entities(
            matching: Self.query,
            updatingSystemWhen: .rendering
        ) {
            guard let component = entity.components[OceanProbeComponent.self] else {
                continue
            }

            guard component.isEnabled else {
                simulationClock.suspend()
                runtimeDiagnostics.suspend()
                renderer?.suspend(at: elapsedTime)
                entity.findEntity(named: Self.surfaceName)?.isEnabled = false
                continue
            }

            let parameters: OceanProbeParameters
            do {
                parameters = try OceanProbeParameters(
                    component,
                    resolution: OceanSimulationGrid.resolution
                )
            } catch {
                simulationClock.suspend()
                runtimeDiagnostics.suspend()
                renderer?.suspend(at: elapsedTime)
                if !parameterFailureReported {
                    parameterFailureReported = true
                    Self.logger.error(
                        "Invalid ocean simulation parameters: \(error); length scales \(component.lengthScale0, privacy: .public), \(component.lengthScale1, privacy: .public), \(component.lengthScale2, privacy: .public), \(component.lengthScale3, privacy: .public)"
                    )
                }
                entity.findEntity(named: Self.surfaceName)?.isEnabled = false
                continue
            }
            parameterFailureReported = false

            let activeRenderer: OceanProbeRenderer
            if let renderer {
                activeRenderer = renderer
            } else {
                guard let material = shaderGraphMaterial(from: entity) else {
                    Self.logger.error(
                        "Missing ShaderGraph material on \(Self.materialSourceName, privacy: .public)"
                    )
                    continue
                }
                guard let newRenderer = makeRenderer(material: material) else {
                    continue
                }
                renderer = newRenderer
                activeRenderer = newRenderer
            }

            let surface = entity.findEntity(named: Self.surfaceName)
                ?? attachSurface(to: entity, renderer: activeRenderer)
            surface.isEnabled = activeRenderer.hasPresentedFrame
            if let material = shaderGraphMaterial(from: entity) {
                do {
                    let changedNames = try activeRenderer.synchronizeAppearance(
                        from: material
                    )
                    if !changedNames.isEmpty {
                        Self.logger.notice(
                            "Hot-updated OceanWater parameters: \(changedNames.joined(separator: ", "), privacy: .public)"
                        )
                    }
                } catch {
                    Self.logger.error(
                        "OceanWater parameter synchronization failed: \(error)"
                    )
                }
            }

            do {
                let lighting = try RuntimeEnvironmentLighting.synchronize(
                    surface: surface,
                    to: entity,
                    sky: SkyAppearance(material: skyMaterial(near: entity)),
                    intensityExponent: parameters.iblIntensityExponent
                )
                if lighting.createdLight {
                    Self.logger.notice(
                        "Runtime IBL attached from the procedural sky; intensity exponent \(parameters.iblIntensityExponent, privacy: .public)"
                    )
                } else if lighting.rebuiltEnvironment {
                    Self.logger.notice("Rebuilt the procedural sky environment")
                } else if lighting.changedIntensity {
                    Self.logger.notice(
                        "Hot-updated IBL intensity exponent to \(parameters.iblIntensityExponent, privacy: .public)"
                    )
                }
                environmentLightingFailureReported = false
            } catch {
                if !environmentLightingFailureReported {
                    environmentLightingFailureReported = true
                    Self.logger.error(
                        "Runtime IBL initialization failed: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }

            let spectrumControls = SpectrumControlSnapshot(
                component: component,
                parameters: parameters
            )
            if let lastSpectrumControls,
               lastSpectrumControls != spectrumControls
            {
                Self.logger.notice(
                    "Hot-updated spectrum controls; wind speed \(spectrumControls.windSpeed, privacy: .public) m/s; wind direction \(spectrumControls.windDirectionDegrees, privacy: .public) degrees; wind alignment \(spectrumControls.windAlignment, privacy: .public); cross-sea amount \(spectrumControls.crossSeaAmount, privacy: .public); cross-sea angle \(spectrumControls.crossSeaAngleDegrees, privacy: .public) degrees; swell direction \(spectrumControls.swellDirectionDegrees, privacy: .public) degrees; swell wavelength \(spectrumControls.swellWavelength, privacy: .public) m; swell height \(spectrumControls.swellHeight, privacy: .public) m; swell spread \(spectrumControls.swellSpread, privacy: .public) degrees; swell bandwidth \(spectrumControls.swellBandwidth, privacy: .public); rebuilding spectrum"
                )
            } else if lastSpectrumControls == nil {
                Self.logger.notice(
                    "Ocean parameters active; wind speed \(parameters.windSpeed, privacy: .public) m/s; wind direction \(spectrumControls.windDirectionDegrees, privacy: .public) degrees; wind alignment \(spectrumControls.windAlignment, privacy: .public); cross-sea amount \(spectrumControls.crossSeaAmount, privacy: .public); cross-sea angle \(spectrumControls.crossSeaAngleDegrees, privacy: .public) degrees; swell direction \(spectrumControls.swellDirectionDegrees, privacy: .public) degrees; swell wavelength \(spectrumControls.swellWavelength, privacy: .public) m; swell height \(spectrumControls.swellHeight, privacy: .public) m; swell spread \(spectrumControls.swellSpread, privacy: .public) degrees; swell bandwidth \(spectrumControls.swellBandwidth, privacy: .public); IBL intensity exponent \(parameters.iblIntensityExponent, privacy: .public)"
                )
            }
            if lastSpectrumControls != spectrumControls {
                let diagnostic = SwellSpectrumDiagnostic(parameters: parameters)
                let calibration = diagnostic.calibration
                Self.logger.notice(
                    "Swell spectrum diagnostic; requested direction \(spectrumControls.swellDirectionDegrees, privacy: .public) degrees; requested wavelength \(spectrumControls.swellWavelength, privacy: .public) m; peak wave number \(calibration.peakWaveNumber, privacy: .public) rad/m; cascade \(calibration.cascade ?? -1, privacy: .public); effective direction sigma \(calibration.effectiveDirectionalSigma * 180 / .pi, privacy: .public) degrees; effective angular-frequency sigma \(calibration.effectiveAngularFrequencySigma, privacy: .public) rad/s; centroid direction \(calibration.centroidDirectionRadians * 180 / .pi, privacy: .public) degrees; centroid wavelength \(calibration.centroidWavelength, privacy: .public) m; discrete variance \(calibration.discreteVariance, privacy: .public); dispersion angular frequency \(calibration.peakAngularFrequency, privacy: .public) rad/s; loop-quantized angular frequency \(diagnostic.quantizedAngularFrequency, privacy: .public) rad/s; repeat-time harmonic \(diagnostic.loopHarmonic, privacy: .public)"
                )
            }
            lastSpectrumControls = spectrumControls

            let foamControls = FoamControlSnapshot(parameters: parameters)
            if let lastFoamControls, lastFoamControls != foamControls {
                Self.logger.notice(
                    "Hot-updated physical foam controls; bias \(foamControls.bias, privacy: .public); power \(foamControls.power, privacy: .public); add per nominal 60 Hz step \(foamControls.amount, privacy: .public); decay \(foamControls.decay, privacy: .public) per second; source-free one-second retention \(foamControls.sourceFreeRetentionPerSecond, privacy: .public)"
                )
            } else if lastFoamControls == nil {
                Self.logger.notice(
                    "Physical foam controls active; bias \(foamControls.bias, privacy: .public); power \(foamControls.power, privacy: .public); add per nominal 60 Hz step \(foamControls.amount, privacy: .public); decay \(foamControls.decay, privacy: .public) per second; source-free one-second retention \(foamControls.sourceFreeRetentionPerSecond, privacy: .public)"
                )
            }
            lastFoamControls = foamControls

            do {
                let offeredTick = simulationClock.offer(sceneTime: elapsedTime)
                let advance = try activeRenderer.advanceFrame(
                    sceneTime: elapsedTime,
                    frameDeltaTime: Float(context.deltaTime),
                    offeredTick: offeredTick,
                    parameters: parameters
                )
                if advance.acceptedOfferedTick, let offeredTick {
                    simulationClock.commit(offeredTick)
                }
                if let timing = runtimeDiagnostics.record(
                    frameDeltaTime: context.deltaTime,
                    acceptedSimulationTick: advance.acceptedOfferedTick,
                    completedSimulationGPUMilliseconds:
                        advance.completedSimulationGPUTimeMilliseconds,
                    completedPresentationGPUMilliseconds:
                        advance.completedPresentationGPUTimeMilliseconds
                ) {
                    Self.logger.notice(
                        "Runtime diagnostic; render \(timing.renderFramesPerSecond, privacy: .public) fps; simulation \(timing.acceptedTicksPerSecond, privacy: .public) ticks/s (\(timing.acceptedSimulationTicks, privacy: .public) ticks / \(timing.windowSeconds, privacy: .public) s); simulation GPU median \(timing.simulationGPUMedianMilliseconds ?? -1, privacy: .public) ms; presentation GPU median \(timing.presentationGPUMedianMilliseconds ?? -1, privacy: .public) ms"
                    )
                }
                surface.isEnabled = activeRenderer.hasPresentedFrame
                for evidence in advance.evidence {
                    if let firstFrame = evidence.firstFrame {
                        Self.logger.notice(
                            "First FFT ocean frame completed; global height range \(firstFrame.heightRange.lowerBound, privacy: .public) ... \(firstFrame.heightRange.upperBound, privacy: .public); peak-to-trough \(firstFrame.peakToTrough, privacy: .public); inner 24 m peak-to-trough \(firstFrame.innerPatchPeakToTrough, privacy: .public); significant wave height \(firstFrame.innerPatchSignificantWaveHeight, privacy: .public)"
                        )
                    }
                    if let foam = evidence.foam {
                        for (cascade, values) in foam.cascades.enumerated() {
                            Self.logger.notice(
                                "Published foam frame \(foam.frame, privacy: .public) cascade \(cascade, privacy: .public): range \(values.range.lowerBound, privacy: .public) ... \(values.range.upperBound, privacy: .public); mean \(values.mean, privacy: .public); coverage > 0.05 \(values.coverageAboveFivePercent, privacy: .public); coverage > 0.20 \(values.coverageAboveTwentyPercent, privacy: .public)"
                            )
                        }
                        Self.logger.notice(
                            "Published foam frame \(foam.frame, privacy: .public) independent-cascade material sum: range \(foam.combinedRange.lowerBound, privacy: .public) ... \(foam.combinedRange.upperBound, privacy: .public); mean \(foam.combinedMean, privacy: .public); total coverage > 0.05 \(foam.combinedCoverageAboveFivePercent, privacy: .public); total coverage > 0.20 \(foam.combinedCoverageAboveTwentyPercent, privacy: .public)"
                        )
                    }
                }
            } catch {
                Self.logger.error("Metal probe update failed: \(error)")
            }
        }
    }

    private mutating func makeRenderer(
        material: ShaderGraphMaterial
    ) -> OceanProbeRenderer? {
        guard !rendererCreationFailed else {
            return nil
        }

        do {
            let renderer = try OceanProbeRenderer(material: material)
            Self.logger.notice(
                "FFT ocean renderer initialized; four cascade fields bound through ShaderGraphMaterial"
            )
            return renderer
        } catch {
            rendererCreationFailed = true
            Self.logger.error("Metal probe renderer initialization failed: \(error)")
            return nil
        }
    }

    private func shaderGraphMaterial(from entity: Entity) -> ShaderGraphMaterial? {
        guard let source = entity.findEntity(named: Self.materialSourceName),
              let model = source.components[ModelComponent.self]
        else {
            return nil
        }
        return model.materials.first as? ShaderGraphMaterial
    }

    /// The sky dome carries the same authored material the environment is built
    /// from, so the water is lit by the sky the viewer is actually under.
    private func skyMaterial(near entity: Entity) -> ShaderGraphMaterial? {
        var root = entity
        while let parent = root.parent {
            root = parent
        }
        guard let dome = root.findEntity(named: Self.skyDomeName),
              let model = dome.components[ModelComponent.self]
        else {
            return nil
        }
        return model.materials.first as? ShaderGraphMaterial
    }

    private func attachSurface(
        to entity: Entity,
        renderer: OceanProbeRenderer
    ) -> Entity {
        let surface = renderer.makeSurfaceEntity()
        entity.addChild(surface)
        Self.logger.info("Attached OceanProbeSurface")
        return surface
    }
}
