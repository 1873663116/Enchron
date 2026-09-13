import Metal
import OSLog
import RealityKit

enum OceanProbeRendererError: Error {
    case metalDeviceUnavailable
    case commandQueueUnavailable
    case computeFunctionUnavailable(String)
    case textureAllocationFailed(String)
    case commandBufferUnavailable
    case computeEncoderUnavailable(String)
    case unsupportedFFTThreadgroup(Int)
    case nonFiniteSurface
    case flatSurface(ClosedRange<Float>)
    case commandBufferExecutionFailed(String)
    case shaderParametersMissing(required: [String], available: [String])
}

private struct OceanVertex {
    var position: SIMD3<Float>
    var normal: SIMD3<Float>
    var tangent: SIMD4<Float>
    var uv: SIMD2<Float>
    var baseXZ: SIMD2<Float>
    var stitch: SIMD4<Float>
}

private struct OceanUniforms {
    var resolution: UInt32
    var seed: UInt32
    var depth: Float
    var gravity: Float
    var frameTime: Float
    var deltaTime: Float
    var repeatTime: Float
    var inverseFFTScale: Float
    var lengthScales: SIMD4<Float>
    var cutoffLow: SIMD4<Float>
    var cutoffHigh: SIMD4<Float>
    var choppiness: Float
    var foamBias: Float
    var foamPower: Float
    var foamAdd: Float
    var foamDecay: Float
    var activeCascadeCount: UInt32
    var detailDeltaTime: Float
    var cascadeStart: UInt32
}

struct CascadeUpdatePlan: Equatable {
    let cascadeStart: UInt32
    let activeCascadeCount: UInt32
    let primaryFoamElapsed: Float
    let detailFoamElapsed: Float
    fileprivate let nextDetailUpdateIsDue: Bool
    fileprivate let detailUpdateTime: Float?

    var updatesDetail: Bool {
        activeCascadeCount == 4
    }
}

struct CascadeUpdateScheduler {
    private var detailUpdateIsDue = true
    private var lastDetailUpdateTime: Float?
    private var nextCascadePairStart: UInt32 = 0
    private var lastPairUpdateTimes: [Float?] = [nil, nil]

    mutating func requireFullUpdate() {
        detailUpdateIsDue = true
    }

    func plan(
        time: Float,
        frameDeltaTime: Float,
        forceFullUpdate: Bool,
        resetsFoam: Bool,
        updatesDetailEveryTick: Bool = false,
        rotatesCascadePairs: Bool = false
    ) -> CascadeUpdatePlan {
        let frameElapsed = Self.clampedFrameDelta(frameDeltaTime)
        if rotatesCascadePairs {
            return rotatingPlan(
                time: time,
                frameElapsed: frameElapsed,
                forceFullUpdate: forceFullUpdate,
                resetsFoam: resetsFoam
            )
        }
        let updatesDetail = forceFullUpdate
            || updatesDetailEveryTick
            || detailUpdateIsDue
        let detailElapsed: Float
        if !updatesDetail {
            detailElapsed = 0
        } else if resetsFoam || lastDetailUpdateTime == nil {
            detailElapsed = frameElapsed
        } else if let lastDetailUpdateTime {
            let elapsed = time - lastDetailUpdateTime
            detailElapsed = Self.clampedDetailElapsed(
                elapsed.isFinite && elapsed >= 0 ? elapsed : frameElapsed
            )
        } else {
            detailElapsed = frameElapsed
        }
        return CascadeUpdatePlan(
            cascadeStart: 0,
            activeCascadeCount: updatesDetail ? 4 : 2,
            primaryFoamElapsed: frameElapsed,
            detailFoamElapsed: detailElapsed,
            nextDetailUpdateIsDue: !updatesDetail,
            detailUpdateTime: updatesDetail ? time : nil
        )
    }

    private func rotatingPlan(
        time: Float,
        frameElapsed: Float,
        forceFullUpdate: Bool,
        resetsFoam: Bool
    ) -> CascadeUpdatePlan {
        let pairElapsed: (Int) -> Float = { pair in
            guard let last = lastPairUpdateTimes[pair] else {
                return frameElapsed
            }
            let elapsed = time - last
            return Self.clampedDetailElapsed(
                elapsed.isFinite && elapsed > 0 ? elapsed : frameElapsed
            )
        }
        if forceFullUpdate || resetsFoam || detailUpdateIsDue {
            return CascadeUpdatePlan(
                cascadeStart: 0,
                activeCascadeCount: 4,
                primaryFoamElapsed: pairElapsed(0),
                detailFoamElapsed: pairElapsed(1),
                nextDetailUpdateIsDue: false,
                detailUpdateTime: time
            )
        }
        let pair = nextCascadePairStart == 0 ? 0 : 1
        let elapsed = pairElapsed(pair)
        return CascadeUpdatePlan(
            cascadeStart: nextCascadePairStart,
            activeCascadeCount: 2,
            primaryFoamElapsed: pair == 0 ? elapsed : frameElapsed,
            detailFoamElapsed: pair == 1 ? elapsed : frameElapsed,
            nextDetailUpdateIsDue: false,
            detailUpdateTime: time
        )
    }

    mutating func commit(_ plan: CascadeUpdatePlan) {
        detailUpdateIsDue = plan.nextDetailUpdateIsDue
        if let detailUpdateTime = plan.detailUpdateTime {
            lastDetailUpdateTime = detailUpdateTime
            if plan.activeCascadeCount == 4 {
                lastPairUpdateTimes[0] = detailUpdateTime
                lastPairUpdateTimes[1] = detailUpdateTime
            } else {
                let pair = plan.cascadeStart == 0 ? 0 : 1
                lastPairUpdateTimes[pair] = detailUpdateTime
                nextCascadePairStart = plan.cascadeStart == 0 ? 2 : 0
            }
        }
    }

    static func clampedFrameDelta(_ deltaTime: Float) -> Float {
        min(max(deltaTime, 1 / 240), 1 / 15)
    }

    static func clampedDetailElapsed(_ elapsed: Float) -> Float {
        min(max(elapsed, 1 / 240), 0.25)
    }
}

private struct SurfaceUniforms {
    var vertexCount: UInt32
    var resolution: UInt32
    var amplitude: Float
    var padding: Float = 0
    var lengthScales: SIMD4<Float>
    var envelopeAmount: Float
    var envelopeScaleMeters: Float
    var blendFactor: Float = 0
}

private struct SurfacePublicationUniforms {
    var resolution: UInt32
    var amplitude: Float
    var cascadeStart: UInt32 = 0
    var padding: Float = 0
}

private struct InterpolatedSurfacePublicationUniforms {
    var resolution: UInt32
    var amplitude: Float
    var interpolationWeight: Float
    var padding: Float = 0
}

struct SnapshotLeaseLedger {
    struct SimulationLease: Equatable {
        fileprivate let id: UInt64
        let sourceSlot: Int?
        let destinationSlot: Int
    }

    struct PresentationLease: Equatable {
        fileprivate let id: UInt64
        let sourceSlots: [Int]
    }

    private struct SimulationRecord {
        let lease: SimulationLease
        var submitted: Bool
    }

    private struct PresentationRecord {
        let lease: PresentationLease
        var submitted: Bool
    }

    private let slotCount: Int
    private var readerCounts: [Int]
    private var writerIDs: [UInt64?]
    private var simulations: [UInt64: SimulationRecord] = [:]
    private var presentations: [UInt64: PresentationRecord] = [:]
    private var nextID: UInt64 = 0

    init(slotCount: Int) {
        precondition(slotCount > 0)
        self.slotCount = slotCount
        readerCounts = [Int](repeating: 0, count: slotCount)
        writerIDs = [UInt64?](repeating: nil, count: slotCount)
    }

    mutating func reserveSimulation(
        sourceSlot: Int?,
        preferredDestinations: [Int]
    ) -> SimulationLease? {
        if let sourceSlot {
            precondition(valid(sourceSlot))
            guard writerIDs[sourceSlot] == nil else {
                return nil
            }
        }
        guard let destination = preferredDestinations.first(where: {
            valid($0)
                && $0 != sourceSlot
                && readerCounts[$0] == 0
                && writerIDs[$0] == nil
        }) else {
            return nil
        }
        let lease = SimulationLease(
            id: issueID(),
            sourceSlot: sourceSlot,
            destinationSlot: destination
        )
        if let sourceSlot {
            readerCounts[sourceSlot] += 1
        }
        writerIDs[destination] = lease.id
        simulations[lease.id] = SimulationRecord(lease: lease, submitted: false)
        return lease
    }

    mutating func markSubmitted(_ lease: SimulationLease) {
        guard var record = simulations[lease.id], record.lease == lease else {
            preconditionFailure("unknown simulation lease")
        }
        precondition(!record.submitted)
        record.submitted = true
        simulations[lease.id] = record
    }

    mutating func cancelBeforeSubmission(_ lease: SimulationLease) {
        guard let record = simulations.removeValue(forKey: lease.id) else {
            preconditionFailure("unknown simulation lease")
        }
        precondition(!record.submitted && record.lease == lease)
        release(lease)
    }

    mutating func finish(_ lease: SimulationLease) {
        guard let record = simulations.removeValue(forKey: lease.id) else {
            preconditionFailure("unknown simulation lease")
        }
        precondition(record.submitted && record.lease == lease)
        release(lease)
    }

    mutating func reservePresentation(
        sourceSlots: [Int]
    ) -> PresentationLease? {
        let uniqueSlots = Array(Set(sourceSlots)).sorted()
        precondition(!uniqueSlots.isEmpty)
        precondition(uniqueSlots.allSatisfy(valid))
        guard uniqueSlots.allSatisfy({ writerIDs[$0] == nil }) else {
            return nil
        }
        let lease = PresentationLease(id: issueID(), sourceSlots: uniqueSlots)
        for slot in uniqueSlots {
            readerCounts[slot] += 1
        }
        presentations[lease.id] = PresentationRecord(
            lease: lease,
            submitted: false
        )
        return lease
    }

    mutating func markSubmitted(_ lease: PresentationLease) {
        guard var record = presentations[lease.id], record.lease == lease else {
            preconditionFailure("unknown presentation lease")
        }
        precondition(!record.submitted)
        record.submitted = true
        presentations[lease.id] = record
    }

    mutating func cancelBeforeSubmission(_ lease: PresentationLease) {
        guard let record = presentations.removeValue(forKey: lease.id) else {
            preconditionFailure("unknown presentation lease")
        }
        precondition(!record.submitted && record.lease == lease)
        release(lease)
    }

    mutating func finish(_ lease: PresentationLease) {
        guard let record = presentations.removeValue(forKey: lease.id) else {
            preconditionFailure("unknown presentation lease")
        }
        precondition(record.submitted && record.lease == lease)
        release(lease)
    }

    func readerCount(for slot: Int) -> Int {
        precondition(valid(slot))
        return readerCounts[slot]
    }

    func hasWriter(for slot: Int) -> Bool {
        precondition(valid(slot))
        return writerIDs[slot] != nil
    }

    private func valid(_ slot: Int) -> Bool {
        (0 ..< slotCount).contains(slot)
    }

    private mutating func issueID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    private mutating func release(_ lease: SimulationLease) {
        if let sourceSlot = lease.sourceSlot {
            precondition(readerCounts[sourceSlot] > 0)
            readerCounts[sourceSlot] -= 1
        }
        precondition(writerIDs[lease.destinationSlot] == lease.id)
        writerIDs[lease.destinationSlot] = nil
    }

    private mutating func release(_ lease: PresentationLease) {
        for slot in lease.sourceSlots {
            precondition(readerCounts[slot] > 0)
            readerCounts[slot] -= 1
        }
    }
}

private struct WindSpectrumParameters {
    var scale: Float
    var angle: Float
    var spreadBlend: Float
    var alignment: Float
    var alpha: Float
    var peakOmega: Float
    var gamma: Float
    var shortWavesFade: Float
}

private struct SwellSpectrumParameters {
    var height: Float
    var angle: Float
    var peakWaveNumber: Float
    var angularFrequencySigma: Float
    var directionalSigma: Float
    var energyScale: Float
    var padding0: Float = 0
    var padding1: Float = 0
}

private struct SpectrumSignature: Equatable {
    let seed: UInt32
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
    let repeatTime: Float
    let cascades: CascadeLayout
}

struct FirstFrameEvidence {
    let heightRange: ClosedRange<Float>
    let innerPatchHeightRange: ClosedRange<Float>
    let innerPatchSignificantWaveHeight: Float

    var peakToTrough: Float {
        heightRange.upperBound - heightRange.lowerBound
    }

    var innerPatchPeakToTrough: Float {
        innerPatchHeightRange.upperBound - innerPatchHeightRange.lowerBound
    }
}

struct CascadeFoamEvidence {
    let range: ClosedRange<Float>
    let mean: Float
    let coverageAboveFivePercent: Float
    let coverageAboveTwentyPercent: Float
}

struct FoamFieldEvidence {
    let frame: Int
    let cascades: [CascadeFoamEvidence]
    let combinedRange: ClosedRange<Float>
    let combinedMean: Float
    let combinedCoverageAboveFivePercent: Float
    let combinedCoverageAboveTwentyPercent: Float
}

struct RenderEvidence {
    let firstFrame: FirstFrameEvidence?
    let foam: FoamFieldEvidence?
}

@MainActor
private struct PublishedSurfaceFields {
    // 512 rather than 1024: a full four-cascade update measured 4.97 ms median
    // on an M4 at 1024 and 1.40 ms at 512, which is 45% of a 90 Hz frame
    // against 13%. The cost tracks texel count; mip depth does not move it.
    static let resolution = OceanSimulationGrid.resolution
    static let resolutions = [Int](repeating: resolution, count: 4)
    static let mipLevelCounts = [Int](
        repeating: OceanSimulationGrid.logResolution + 1,
        count: 4
    )
    static let textureNames = [
        "Cascade0Field",
        "Cascade1Field",
        "Cascade2Field",
        "Cascade3Field",
    ]
    static let inverseLengthNames = [
        "InvLength0",
        "InvLength1",
        "InvLength2",
        "InvLength3",
    ]
    let textures: [LowLevelTexture]
    let resources: [TextureResource]

    init() throws {
        textures = try zip(Self.resolutions, Self.mipLevelCounts).map {
            resolution, mipLevelCount in
            let descriptor = LowLevelTexture.Descriptor(
                textureType: .type2D,
                pixelFormat: .rgba16Float,
                width: resolution,
                height: resolution,
                mipmapLevelCount: mipLevelCount,
                textureUsage: [.shaderRead, .shaderWrite]
            )
            return try LowLevelTexture(descriptor: descriptor)
        }
        resources = try textures.map { try TextureResource(from: $0) }
    }

    func replace(
        cascadeStart: Int,
        cascadeCount: Int,
        using commandBuffer: any MTLCommandBuffer
    ) -> PublishedTargets {
        precondition(cascadeCount == 2 || cascadeCount == 4)
        precondition(cascadeStart >= 0 && cascadeStart + cascadeCount <= 4)
        var active: [any MTLTexture] = []
        var all: [any MTLTexture] = []
        for (index, texture) in textures.enumerated() {
            if index >= cascadeStart && index < cascadeStart + cascadeCount {
                let replaced = texture.replace(using: commandBuffer)
                active.append(replaced)
                all.append(replaced)
            } else {
                all.append(texture.read())
            }
        }
        return PublishedTargets(active: active, all: all)
    }
}

private struct PublishedTargets {
    let active: [any MTLTexture]
    let all: [any MTLTexture]
}

struct SurfacePresentationSignature: Equatable {
    let amplitude: Float
    let lengthScales: SIMD4<Float>
    let envelopeAmount: Float
    let envelopeScaleMeters: Float

    init(
        amplitude: Float,
        lengthScales: SIMD4<Float>,
        envelopeAmount: Float,
        envelopeScaleMeters: Float
    ) {
        self.amplitude = amplitude
        self.lengthScales = lengthScales
        self.envelopeAmount = envelopeAmount
        self.envelopeScaleMeters = envelopeScaleMeters
    }

    init(_ parameters: OceanProbeParameters) {
        self.init(
            amplitude: parameters.amplitude,
            lengthScales: parameters.cascades.lengthScales,
            envelopeAmount: parameters.envelopeAmount,
            envelopeScaleMeters: parameters.envelopeScaleMeters
        )
    }
}

private struct CompletedSimulation {
    let slot: Int
    let sequence: UInt64
    let sampleTime: Float
    let generation: UInt64
    let signature: SpectrumSignature
    let cascadePlan: CascadeUpdatePlan
    let parameters: OceanProbeParameters
    let frame: Int
    var completedSceneTime: Float = 0
}

private struct InFlightSimulation {
    let commandBuffer: any MTLCommandBuffer
    let result: CompletedSimulation
    let lease: SnapshotLeaseLedger.SimulationLease
}

private struct PresentationRequest {
    let source: CompletedSimulation

    var sourceSlots: [Int] { [source.slot] }
}

private struct InFlightPresentation {
    let commandBuffer: any MTLCommandBuffer
    let request: PresentationRequest
    let lease: SnapshotLeaseLedger.PresentationLease
    let publishesResult: Bool
    let presentationSignature: SurfacePresentationSignature
    let foamReadback: (any MTLBuffer)?
    let verifiesFirstFrame: Bool
}

private struct InFlightInterpolation {
    let commandBuffer: any MTLCommandBuffer
    let lease: SnapshotLeaseLedger.PresentationLease
}

struct FrameAdvanceResult {
    let acceptedOfferedTick: Bool
    let evidence: [RenderEvidence]
    let completedSimulationGPUTimeMilliseconds: Double?
    let completedPresentationGPUTimeMilliseconds: Double?
    var completedInterpolationGPUTimeMilliseconds: Double?
}

private struct CompletedCommandEvidence {
    var renderEvidence: [RenderEvidence] = []
    var simulationGPUTimeMilliseconds: Double?
    var presentationGPUTimeMilliseconds: Double?
    var interpolationGPUTimeMilliseconds: Double?
}

@MainActor
final class OceanProbeRenderer {
    private static let logger = Logger(
        subsystem: "dev.enchron.ocean-probe",
        category: "renderer"
    )
    private static let resolution = OceanSimulationGrid.resolution
    private static let ifftThreadsPerThreadgroup = resolution / 2
    private static let publishedFieldResolution = PublishedSurfaceFields.resolution
    private static let ringCellsPerSide = 64
    private static let ringCount = 10
    private static let innerPatchSize: Float = 24

    private let simulationQueue: any MTLCommandQueue
    private let presentationQueue: any MTLCommandQueue
    private let pipelines: Pipelines
    private let textures: Textures
    private let lowLevelMesh: LowLevelMesh
    private let meshResource: MeshResource
    /// Immutable per-vertex grid data (baseXZ, stitch) the projection kernels
    /// read from. `LowLevelMesh.replace(bufferIndex:using:)` hands back an
    /// uninitialized buffer, so the kernels must never read the mesh itself.
    private let gridVertexBuffer: any MTLBuffer
    private let publishedFields: PublishedSurfaceFields
    private var surfaceMaterial: ShaderGraphMaterial
    private var authoredAppearance: [String: MaterialParameters.Value]

    private var installedSpectrum: SpectrumSignature?
    private var desiredSpectrum: SpectrumSignature?
    private var desiredSpectrumGeneration: UInt64 = 0
    private var installedMaterialLayout: CascadeLayout?
    private var installedFoamParameters: FoamParameters?
    private var didVerifyFirstFrame = false
    private var submittedSimulationCount = 0
    private var foamEvidenceFrames: Set<Int> = [1, 120, 240]
    private var cascadeUpdateScheduler = CascadeUpdateScheduler()
    private var latestCompletedSimulation: CompletedSimulation?
    private var completedSimulations: [CompletedSimulation] = []
    private var snapshotLedger = SnapshotLeaseLedger(slotCount: 2)
    private var inFlightSimulation: InFlightSimulation?
    private var inFlightPresentation: InFlightPresentation?
    private var inFlightInterpolation: InFlightInterpolation?
    private var lastPresentedSequence: UInt64?
    private var lastPresentedSignature: SurfacePresentationSignature?
    private var pendingForcedSimulation = true
    private var nextInternalSequence: UInt64 = 0
    private(set) var hasPresentedFrame = false
    private weak var surfaceEntity: ModelEntity?

    init(material authoredMaterial: ShaderGraphMaterial) throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw OceanProbeRendererError.metalDeviceUnavailable
        }
        guard let simulationQueue = device.makeCommandQueue(),
              let presentationQueue = device.makeCommandQueue()
        else {
            throw OceanProbeRendererError.commandQueueUnavailable
        }

        let library = try device.makeLibrary(
            source: OceanFFTMetalSource.source,
            options: nil
        )
        let pipelines = try Pipelines(device: device, library: library)
        guard pipelines.horizontalIFFT.maxTotalThreadsPerThreadgroup
                >= Self.ifftThreadsPerThreadgroup
        else {
            throw OceanProbeRendererError.unsupportedFFTThreadgroup(
                pipelines.horizontalIFFT.maxTotalThreadsPerThreadgroup
            )
        }

        self.simulationQueue = simulationQueue
        self.presentationQueue = presentationQueue
        self.pipelines = pipelines
        textures = try Textures(
            device: device,
            resolution: Self.resolution
        )

        let mesh = try Self.makeGridMesh()
        lowLevelMesh = mesh.lowLevelMesh
        meshResource = mesh.meshResource
        gridVertexBuffer = try mesh.gridVertices.withUnsafeBytes { grid in
            guard let buffer = device.makeBuffer(
                bytes: grid.baseAddress!,
                length: grid.count,
                options: .storageModeShared
            ) else {
                throw OceanProbeRendererError.commandBufferUnavailable
            }
            buffer.label = "Ocean Grid Vertices"
            return buffer
        }
        publishedFields = try PublishedSurfaceFields()

        let requiredNames = PublishedSurfaceFields.textureNames
            + PublishedSurfaceFields.inverseLengthNames
        let missingNames = requiredNames.filter {
            !authoredMaterial.parameterNames.contains($0)
        }
        guard missingNames.isEmpty else {
            throw OceanProbeRendererError.shaderParametersMissing(
                required: missingNames,
                available: authoredMaterial.parameterNames
            )
        }
        var boundMaterial = authoredMaterial
        for (name, resource) in zip(
            PublishedSurfaceFields.textureNames,
            publishedFields.resources
        ) {
            try boundMaterial.setParameter(
                name: name,
                value: .textureResource(resource)
            )
        }
        surfaceMaterial = boundMaterial
        authoredAppearance = Self.appearanceParameters(from: authoredMaterial)

        precondition(MemoryLayout<OceanUniforms>.stride == 112)
        precondition(MemoryLayout<SurfaceUniforms>.stride == 48)
        precondition(MemoryLayout<SurfacePublicationUniforms>.stride == 16)
        precondition(MemoryLayout<WindSpectrumParameters>.stride == 32)
        precondition(MemoryLayout<SwellSpectrumParameters>.stride == 32)
        precondition(MemoryLayout<OceanVertex>.stride == 80)
    }

    func makeSurfaceEntity() -> ModelEntity {
        let entity = ModelEntity(mesh: meshResource, materials: [surfaceMaterial])
        entity.name = OceanProbeSystem.surfaceName
        entity.position = .zero
        surfaceEntity = entity
        return entity
    }

    func requireFullCascadeUpdate() {
        pendingForcedSimulation = true
        cascadeUpdateScheduler.requireFullUpdate()
    }

    struct AppearanceSynchronization {
        var applied: [String] = []
        var rejected: [String] = []
    }

    func synchronizeAppearance(
        from authoredMaterial: ShaderGraphMaterial
    ) -> AppearanceSynchronization {
        let nextAppearance = Self.appearanceParameters(from: authoredMaterial)
        let changedNames = nextAppearance.keys.filter {
            authoredAppearance[$0] != nextAppearance[$0]
        }.sorted()
        authoredAppearance = nextAppearance
        var synchronization = AppearanceSynchronization()
        guard !changedNames.isEmpty else {
            return synchronization
        }

        var updatedMaterial = surfaceMaterial
        for name in changedNames {
            guard let value = nextAppearance[name] else {
                continue
            }
            do {
                try updatedMaterial.setParameter(name: name, value: value)
                synchronization.applied.append(name)
            } catch {
                synchronization.rejected.append(name)
            }
        }
        surfaceMaterial = updatedMaterial
        surfaceEntity?.model?.materials = [updatedMaterial]
        return synchronization
    }

    func advanceFrame(
        sceneTime: Float,
        frameDeltaTime: Float,
        offeredTick: SimulationTickOffer?,
        parameters: OceanProbeParameters,
        simulationMode: OceanSimulationMode = .throttled
    ) throws -> FrameAdvanceResult {
        let completed = try reapCompletedCommands(sceneTime: sceneTime)
        if let installedFoamParameters,
           installedFoamParameters != parameters.foam
        {
            foamEvidenceFrames.insert(submittedSimulationCount + 120)
        }
        installedFoamParameters = parameters.foam
        let signature = SpectrumSignature(
            seed: parameters.seed,
            windSpeed: parameters.windSpeed,
            windDirectionRadians: parameters.windDirectionRadians,
            fetch: parameters.fetch,
            windAlignment: parameters.windAlignment,
            crossSeaAmount: parameters.crossSeaAmount,
            crossSeaAngleRadians: parameters.crossSeaAngleRadians,
            swellDirectionRadians: parameters.swellDirectionRadians,
            swellWavelength: parameters.swellWavelength,
            swellHeight: parameters.swellHeight,
            swellSpreadRadians: parameters.swellSpreadRadians,
            swellBandwidth: parameters.swellBandwidth,
            waterDepth: parameters.waterDepth,
            repeatTime: parameters.repeatTime,
            cascades: parameters.cascades
        )
        if desiredSpectrum != signature {
            desiredSpectrum = signature
            desiredSpectrumGeneration &+= 1
            pendingForcedSimulation = true
            cascadeUpdateScheduler.requireFullUpdate()
        }

        if inFlightPresentation == nil {
            let presentationSignature = SurfacePresentationSignature(parameters)
            if let request = makePresentationRequest(
                presentationSignature: presentationSignature
            ), let lease = snapshotLedger.reservePresentation(
                sourceSlots: request.sourceSlots
            ) {
                try submitPresentation(
                    request: request,
                    lease: lease,
                    parameters: parameters,
                    presentationSignature: presentationSignature
                )
            }
        }

        var acceptedOfferedTick = false
        if inFlightSimulation == nil,
           pendingForcedSimulation || offeredTick != nil
        {
            let rebuildsSpectrum = installedSpectrum != signature
            let source = rebuildsSpectrum ? nil : latestCompletedSimulation
            let preferredDestinations = [source?.slot == 0 ? 1 : 0]
            if let lease = snapshotLedger.reserveSimulation(
                sourceSlot: source?.slot,
                preferredDestinations: preferredDestinations
            ) {
                let acceptedOffer = offeredTick
                let sampleTime = pendingForcedSimulation
                    ? sceneTime
                    : offeredTick!.sampleTime
                try submitSimulation(
                    sampleTime: sampleTime,
                    frameDeltaTime: frameDeltaTime,
                    lease: lease,
                    signature: signature,
                    generation: desiredSpectrumGeneration,
                    parameters: parameters,
                    simulationMode: simulationMode
                )
                acceptedOfferedTick = acceptedOffer != nil
            }
        }

        if simulationMode == .throttled,
           inFlightInterpolation == nil,
           let pair = interpolationPair(),
           let blendFactor = interpolationFactor(
               sceneTime: sceneTime,
               pair: pair
           ),
           let lease = snapshotLedger.reservePresentation(
               sourceSlots: [pair.previous.slot, pair.latest.slot]
           )
        {
            try submitInterpolatedProjection(
                previous: pair.previous,
                latest: pair.latest,
                blendFactor: blendFactor,
                lease: lease,
                parameters: parameters
            )
        }

        return FrameAdvanceResult(
            acceptedOfferedTick: acceptedOfferedTick,
            evidence: completed.renderEvidence,
            completedSimulationGPUTimeMilliseconds:
                completed.simulationGPUTimeMilliseconds,
            completedPresentationGPUTimeMilliseconds:
                completed.presentationGPUTimeMilliseconds,
            completedInterpolationGPUTimeMilliseconds:
                completed.interpolationGPUTimeMilliseconds
        )
    }

    func suspend(at _: Float) {
        pendingForcedSimulation = true
        cascadeUpdateScheduler.requireFullUpdate()
    }

    private func submitSimulation(
        sampleTime: Float,
        frameDeltaTime: Float,
        lease: SnapshotLeaseLedger.SimulationLease,
        signature: SpectrumSignature,
        generation: UInt64,
        parameters: OceanProbeParameters,
        simulationMode: OceanSimulationMode
    ) throws {
        guard let commandBuffer = simulationQueue.makeCommandBuffer() else {
            snapshotLedger.cancelBeforeSubmission(lease)
            throw OceanProbeRendererError.commandBufferUnavailable
        }
        commandBuffer.label = "FFT Ocean Simulation"

        let rebuildsSpectrum = installedSpectrum != signature
        let source = rebuildsSpectrum ? nil : latestCompletedSimulation
        precondition(source?.slot == lease.sourceSlot)
        let destination = lease.destinationSlot
        let elapsedSinceSource = source.map { sampleTime - $0.sampleTime }
        let simulationElapsed = elapsedSinceSource.map {
            $0.isFinite && $0 > 0 ? $0 : frameDeltaTime
        } ?? frameDeltaTime
        let cascadePlan = cascadeUpdateScheduler.plan(
            time: sampleTime,
            frameDeltaTime: simulationElapsed,
            forceFullUpdate: rebuildsSpectrum || pendingForcedSimulation,
            resetsFoam: rebuildsSpectrum,
            updatesDetailEveryTick: false,
            rotatesCascadePairs: simulationMode == .fullRate
        )
        var uniforms = makeUniforms(
            time: sampleTime,
            deltaTime: simulationElapsed,
            parameters: parameters,
            cascadePlan: cascadePlan
        )

        do {
            if rebuildsSpectrum {
                var windSpectra = makeWindSpectrumParameters(parameters)
                var swellSpectrum = makeSwellSpectrumParameters(parameters)
                try encodeClearOutputs(
                    into: commandBuffer,
                    field: textures.fields[destination],
                    uniforms: &uniforms
                )
                try encodeSpectrumInitialization(
                    into: commandBuffer,
                    uniforms: &uniforms,
                    windSpectra: &windSpectra,
                    swellSpectrum: &swellSpectrum
                )
                try encodeSpectrumConjugates(
                    into: commandBuffer,
                    uniforms: &uniforms
                )
            }

            try encodeSpectrumEvolution(
                into: commandBuffer,
                uniforms: &uniforms
            )
            try encodeIFFT(
                pipeline: pipelines.horizontalIFFT,
                label: "Horizontal IFFT",
                into: commandBuffer,
                uniforms: &uniforms
            )
            let previousField = source.map { textures.fields[$0.slot] }
                ?? textures.fields[destination]
            try encodeIFFT(
                pipeline: pipelines.verticalIFFT,
                label: "Vertical IFFT",
                into: commandBuffer,
                uniforms: &uniforms
            )
            try encodeTextureAssembly(
                into: commandBuffer,
                previous: previousField,
                output: textures.fields[destination],
                resetsFoam: rebuildsSpectrum,
                uniforms: &uniforms
            )
        } catch {
            snapshotLedger.cancelBeforeSubmission(lease)
            throw error
        }
        completedSimulations.removeAll { $0.slot == destination }
        commandBuffer.commit()
        snapshotLedger.markSubmitted(lease)
        cascadeUpdateScheduler.commit(cascadePlan)
        pendingForcedSimulation = false
        submittedSimulationCount += 1
        let sequence = nextInternalSequence
        nextInternalSequence &+= 1
        let pendingResult = CompletedSimulation(
            slot: destination,
            sequence: sequence,
            sampleTime: sampleTime,
            generation: generation,
            signature: signature,
            cascadePlan: cascadePlan,
            parameters: parameters,
            frame: submittedSimulationCount
        )
        inFlightSimulation = InFlightSimulation(
            commandBuffer: commandBuffer,
            result: pendingResult,
            lease: lease
        )
    }

    private func makePresentationRequest(
        presentationSignature: SurfacePresentationSignature
    ) -> PresentationRequest? {
        guard let source = latestCompletedSimulation,
              source.generation == desiredSpectrumGeneration,
              lastPresentedSequence != source.sequence
                || lastPresentedSignature != presentationSignature
        else {
            return nil
        }
        return PresentationRequest(source: source)
    }

    private func submitPresentation(
        request: PresentationRequest,
        lease: SnapshotLeaseLedger.PresentationLease,
        parameters: OceanProbeParameters,
        presentationSignature: SurfacePresentationSignature
    ) throws {
        do {
            try installMaterialLayoutIfNeeded(parameters.cascades)
        } catch {
            snapshotLedger.cancelBeforeSubmission(lease)
            throw error
        }
        guard let commandBuffer = presentationQueue.makeCommandBuffer() else {
            snapshotLedger.cancelBeforeSubmission(lease)
            throw OceanProbeRendererError.commandBufferUnavailable
        }
        commandBuffer.label = "FFT Ocean Presentation"
        let republishesExistingField = lastPresentedSequence
            == request.source.sequence
        let cascadeStart = republishesExistingField
            ? 0
            : Int(request.source.cascadePlan.cascadeStart)
        let activeCascadeCount = republishesExistingField
            ? 4
            : Int(request.source.cascadePlan.activeCascadeCount)
        let vertexBuffer = lowLevelMesh.replace(
            bufferIndex: 0,
            using: commandBuffer
        )
        let publishedTargets = publishedFields.replace(
            cascadeStart: cascadeStart,
            cascadeCount: activeCascadeCount,
            using: commandBuffer
        )
        do {
            var surfaceUniforms = SurfaceUniforms(
                vertexCount: UInt32(lowLevelMesh.vertexCapacity),
                resolution: UInt32(Self.resolution),
                amplitude: parameters.amplitude,
                lengthScales: parameters.cascades.lengthScales,
                envelopeAmount: parameters.envelopeAmount,
                envelopeScaleMeters: parameters.envelopeScaleMeters
            )
            var publicationUniforms = SurfacePublicationUniforms(
                resolution: UInt32(Self.publishedFieldResolution),
                amplitude: parameters.amplitude,
                cascadeStart: UInt32(cascadeStart)
            )
            try encodeSurfaceProjection(
                into: commandBuffer,
                field: textures.fields[request.source.slot],
                vertexBuffer: vertexBuffer,
                uniforms: &surfaceUniforms,
                publishedTargets: publishedTargets.active,
                cascadeCount: activeCascadeCount,
                publicationUniforms: &publicationUniforms
            )
            try encodePublishedFieldMipmaps(
                into: commandBuffer,
                textures: publishedTargets.active
            )

            let verifiesFirstFrame = !didVerifyFirstFrame
            let verifiesFoam = foamEvidenceFrames.remove(request.source.frame) != nil
            let foamReadback = verifiesFoam
                ? try encodeFoamReadback(
                    from: publishedTargets.all,
                    into: commandBuffer
                )
                : nil
            commandBuffer.commit()
            snapshotLedger.markSubmitted(lease)
            inFlightPresentation = InFlightPresentation(
                commandBuffer: commandBuffer,
                request: request,
                lease: lease,
                publishesResult: true,
                presentationSignature: presentationSignature,
                foamReadback: foamReadback,
                verifiesFirstFrame: verifiesFirstFrame
            )
        } catch {
            commandBuffer.commit()
            snapshotLedger.markSubmitted(lease)
            inFlightPresentation = InFlightPresentation(
                commandBuffer: commandBuffer,
                request: request,
                lease: lease,
                publishesResult: false,
                presentationSignature: presentationSignature,
                foamReadback: nil,
                verifiesFirstFrame: false
            )
            throw error
        }
    }

    private func reapCompletedCommands(
        sceneTime: Float
    ) throws -> CompletedCommandEvidence {
        var completed = CompletedCommandEvidence()
        if let inFlightSimulation {
            switch inFlightSimulation.commandBuffer.status {
            case .completed:
                self.inFlightSimulation = nil
                snapshotLedger.finish(inFlightSimulation.lease)
                if inFlightSimulation.result.generation == desiredSpectrumGeneration {
                    let commandBuffer = inFlightSimulation.commandBuffer
                    var result = inFlightSimulation.result
                    result.completedSceneTime = sceneTime
                    latestCompletedSimulation = result
                    completedSimulations.removeAll { $0.slot == result.slot }
                    completedSimulations.append(result)
                    completedSimulations.sort { $0.sequence < $1.sequence }
                    completed.simulationGPUTimeMilliseconds = (
                        commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
                    ) * 1_000
                    installedSpectrum = result.signature
                }
            case .error:
                self.inFlightSimulation = nil
                snapshotLedger.finish(inFlightSimulation.lease)
                pendingForcedSimulation = true
                cascadeUpdateScheduler.requireFullUpdate()
                throw OceanProbeRendererError.commandBufferExecutionFailed(
                    inFlightSimulation.commandBuffer.error?.localizedDescription
                        ?? "unknown simulation command error"
                )
            default:
                break
            }
        }

        if let inFlightPresentation {
            switch inFlightPresentation.commandBuffer.status {
            case .completed:
                self.inFlightPresentation = nil
                snapshotLedger.finish(inFlightPresentation.lease)
                completed.presentationGPUTimeMilliseconds = (
                    inFlightPresentation.commandBuffer.gpuEndTime
                        - inFlightPresentation.commandBuffer.gpuStartTime
                ) * 1_000
                guard inFlightPresentation.publishesResult else {
                    break
                }
                hasPresentedFrame = true
                lastPresentedSequence = inFlightPresentation.request.source.sequence
                lastPresentedSignature = inFlightPresentation.presentationSignature
                var firstFrame: FirstFrameEvidence?
                if inFlightPresentation.verifiesFirstFrame {
                    let verified = try verifiedSurfaceEvidence()
                    guard verified.peakToTrough > 0.0001 else {
                        throw OceanProbeRendererError.flatSurface(
                            verified.heightRange
                        )
                    }
                    didVerifyFirstFrame = true
                    firstFrame = verified
                }
                let foam = inFlightPresentation.foamReadback.map {
                    verifiedFoamEvidence(
                        from: $0,
                        lengthScales: inFlightPresentation
                            .request.source.parameters.cascades.lengthScales,
                        frame: inFlightPresentation.request.source.frame
                    )
                }
                if firstFrame != nil || foam != nil {
                    completed.renderEvidence.append(
                        RenderEvidence(firstFrame: firstFrame, foam: foam)
                    )
                }
            case .error:
                self.inFlightPresentation = nil
                snapshotLedger.finish(inFlightPresentation.lease)
                throw OceanProbeRendererError.commandBufferExecutionFailed(
                    inFlightPresentation.commandBuffer.error?.localizedDescription
                        ?? "unknown presentation command error"
                )
            default:
                break
            }
        }

        if let inFlightInterpolation {
            switch inFlightInterpolation.commandBuffer.status {
            case .completed:
                self.inFlightInterpolation = nil
                snapshotLedger.finish(inFlightInterpolation.lease)
                completed.interpolationGPUTimeMilliseconds = (
                    inFlightInterpolation.commandBuffer.gpuEndTime
                        - inFlightInterpolation.commandBuffer.gpuStartTime
                ) * 1_000
            case .error:
                self.inFlightInterpolation = nil
                snapshotLedger.finish(inFlightInterpolation.lease)
                Self.logger.error(
                    "Interpolated projection command buffer failed: \(inFlightInterpolation.commandBuffer.error?.localizedDescription ?? "unknown", privacy: .public)"
                )
            default:
                break
            }
        }
        return completed
    }

    private func interpolationPair(
    ) -> (previous: CompletedSimulation, latest: CompletedSimulation)? {
        let usable = completedSimulations.filter {
            $0.generation == desiredSpectrumGeneration
        }
        guard usable.count >= 2 else { return nil }
        return (usable[usable.count - 2], usable[usable.count - 1])
    }

    private func interpolationFactor(
        sceneTime: Float,
        pair: (previous: CompletedSimulation, latest: CompletedSimulation)
    ) -> Float? {
        let interval = pair.latest.sampleTime - pair.previous.sampleTime
        guard interval > 0 else { return nil }
        let blend = (sceneTime - pair.latest.completedSceneTime) / interval
        guard blend < 1 else { return nil }
        return max(0, blend)
    }

    private func submitInterpolatedProjection(
        previous: CompletedSimulation,
        latest: CompletedSimulation,
        blendFactor: Float,
        lease: SnapshotLeaseLedger.PresentationLease,
        parameters: OceanProbeParameters
    ) throws {
        guard let commandBuffer = presentationQueue.makeCommandBuffer() else {
            snapshotLedger.cancelBeforeSubmission(lease)
            throw OceanProbeRendererError.commandBufferUnavailable
        }
        commandBuffer.label = "FFT Ocean Interpolated Projection"
        do {
            let vertexBuffer = lowLevelMesh.replace(
                bufferIndex: 0,
                using: commandBuffer
            )
            var surfaceUniforms = SurfaceUniforms(
                vertexCount: UInt32(lowLevelMesh.vertexCapacity),
                resolution: UInt32(Self.resolution),
                amplitude: parameters.amplitude,
                lengthScales: parameters.cascades.lengthScales,
                envelopeAmount: parameters.envelopeAmount,
                envelopeScaleMeters: parameters.envelopeScaleMeters,
                blendFactor: blendFactor
            )
            let encoder = try makeEncoder(
                commandBuffer,
                label: "Project Blended FFT to LowLevelMesh"
            )
            encoder.setComputePipelineState(pipelines.projectSurfaceBlended)
            encoder.setTexture(
                textures.fields[previous.slot].displacement,
                index: 0
            )
            encoder.setTexture(
                textures.fields[latest.slot].displacement,
                index: 1
            )
            encoder.setBuffer(vertexBuffer, offset: 0, index: 0)
            encoder.setBytes(
                &surfaceUniforms,
                length: MemoryLayout<SurfaceUniforms>.stride,
                index: 1
            )
            encoder.setBuffer(gridVertexBuffer, offset: 0, index: 2)
            dispatchLinear(
                encoder,
                pipeline: pipelines.projectSurfaceBlended,
                count: lowLevelMesh.vertexCapacity
            )
            encoder.endEncoding()

            let publishedTargets = publishedFields.replace(
                cascadeStart: 0,
                cascadeCount: 4,
                using: commandBuffer
            )
            var publicationUniforms = InterpolatedSurfacePublicationUniforms(
                resolution: UInt32(Self.publishedFieldResolution),
                amplitude: parameters.amplitude,
                interpolationWeight: blendFactor
            )
            let publicationEncoder = try makeEncoder(
                commandBuffer,
                label: "Publish Blended Ocean Surface Fields"
            )
            publicationEncoder.setComputePipelineState(
                pipelines.publishSurfaceFieldsBlended
            )
            publicationEncoder.setTexture(
                textures.fields[previous.slot].slope,
                index: 0
            )
            publicationEncoder.setTexture(
                textures.fields[previous.slot].displacement,
                index: 1
            )
            publicationEncoder.setTexture(
                textures.fields[latest.slot].slope,
                index: 2
            )
            publicationEncoder.setTexture(
                textures.fields[latest.slot].displacement,
                index: 3
            )
            for cascade in publishedTargets.active.indices {
                publicationEncoder.setTexture(
                    publishedTargets.active[cascade],
                    index: cascade + 4
                )
            }
            publicationEncoder.setBytes(
                &publicationUniforms,
                length: MemoryLayout<InterpolatedSurfacePublicationUniforms>.stride,
                index: 0
            )
            dispatchTexture(
                publicationEncoder,
                pipeline: pipelines.publishSurfaceFieldsBlended,
                resolution: Self.publishedFieldResolution
            )
            publicationEncoder.endEncoding()
            try encodePublishedFieldMipmaps(
                into: commandBuffer,
                textures: publishedTargets.active
            )
            commandBuffer.commit()
            snapshotLedger.markSubmitted(lease)
            inFlightInterpolation = InFlightInterpolation(
                commandBuffer: commandBuffer,
                lease: lease
            )
        } catch {
            commandBuffer.commit()
            snapshotLedger.markSubmitted(lease)
            inFlightInterpolation = InFlightInterpolation(
                commandBuffer: commandBuffer,
                lease: lease
            )
            throw error
        }
    }

    private func encodeFoamReadback(
        from publishedTargets: [any MTLTexture],
        into commandBuffer: any MTLCommandBuffer
    ) throws -> any MTLBuffer {
        let bytesPerPixel = MemoryLayout<UInt16>.stride * 4
        let bytesPerRow = Self.publishedFieldResolution * bytesPerPixel
        let bytesPerImage = Self.publishedFieldResolution * bytesPerRow
        guard let buffer = textures.fields[0].displacement.device.makeBuffer(
            length: bytesPerImage * 4,
            options: .storageModeShared
        ) else {
            throw OceanProbeRendererError.textureAllocationFailed(
                "Foam evidence readback"
            )
        }
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw OceanProbeRendererError.computeEncoderUnavailable(
                "Foam evidence readback"
            )
        }
        encoder.label = "Read Back Foam Evidence"
        for cascade in 0 ..< 4 {
            encoder.copy(
                from: publishedTargets[cascade],
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: .init(x: 0, y: 0, z: 0),
                sourceSize: .init(
                    width: Self.publishedFieldResolution,
                    height: Self.publishedFieldResolution,
                    depth: 1
                ),
                to: buffer,
                destinationOffset: cascade * bytesPerImage,
                destinationBytesPerRow: bytesPerRow,
                destinationBytesPerImage: bytesPerImage
            )
        }
        encoder.endEncoding()
        return buffer
    }

    private func verifiedFoamEvidence(
        from buffer: any MTLBuffer,
        lengthScales: SIMD4<Float>,
        frame: Int
    ) -> FoamFieldEvidence {
        let channelCount = Self.publishedFieldResolution
            * Self.publishedFieldResolution * 4
        let words = buffer.contents().bindMemory(
            to: UInt16.self,
            capacity: channelCount * 4
        )
        let pixelCount = Self.publishedFieldResolution
            * Self.publishedFieldResolution
        let fields = (0 ..< 4).map { cascade in
            let cascadeOffset = cascade * channelCount
            return (0 ..< pixelCount).map { pixel in
                Float(
                    Float16(bitPattern: words[cascadeOffset + pixel * 4 + 2])
                )
            }
        }

        let summarize: ([Float]) -> CascadeFoamEvidence = { values in
            var minimum = Float.greatestFiniteMagnitude
            var maximum = -Float.greatestFiniteMagnitude
            var sum: Double = 0
            var aboveFivePercent = 0
            var aboveTwentyPercent = 0
            for value in values {
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                sum += Double(value)
                aboveFivePercent += value > 0.05 ? 1 : 0
                aboveTwentyPercent += value > 0.2 ? 1 : 0
            }
            return CascadeFoamEvidence(
                range: minimum ... maximum,
                mean: Float(sum / Double(values.count)),
                coverageAboveFivePercent: Float(aboveFivePercent)
                    / Float(values.count),
                coverageAboveTwentyPercent: Float(aboveTwentyPercent)
                    / Float(values.count)
            )
        }

        let sampleField: ([Float], Float, Float) -> Float = { values, u, v in
            let x = (u - floor(u)) * Float(Self.publishedFieldResolution) - 0.5
            let textureV = 1 - (v - floor(v))
            let y = textureV * Float(Self.publishedFieldResolution) - 0.5
            let x0 = Int(floor(x))
            let y0 = Int(floor(y))
            let tx = x - Float(x0)
            let ty = y - Float(y0)
            let wrap: (Int) -> Int = { value in
                (value % Self.publishedFieldResolution
                    + Self.publishedFieldResolution)
                    % Self.publishedFieldResolution
            }
            let x1 = wrap(x0 + 1)
            let y1 = wrap(y0 + 1)
            let wrappedX0 = wrap(x0)
            let wrappedY0 = wrap(y0)
            let topLeft = values[
                wrappedY0 * Self.publishedFieldResolution + wrappedX0
            ]
            let topRight = values[
                wrappedY0 * Self.publishedFieldResolution + x1
            ]
            let bottomLeft = values[
                y1 * Self.publishedFieldResolution + wrappedX0
            ]
            let bottomRight = values[
                y1 * Self.publishedFieldResolution + x1
            ]
            let top = topLeft + (topRight - topLeft) * tx
            let bottom = bottomLeft + (bottomRight - bottomLeft) * tx
            return top + (bottom - top) * ty
        }

        let worldSampleResolution = Self.publishedFieldResolution
        let worldSize = lengthScales.x
        var combined = [Float]()
        combined.reserveCapacity(worldSampleResolution * worldSampleResolution)
        for y in 0 ..< worldSampleResolution {
            let worldY = (Float(y) + 0.5) / Float(worldSampleResolution) * worldSize
            for x in 0 ..< worldSampleResolution {
                let worldX = (Float(x) + 0.5) / Float(worldSampleResolution) * worldSize
                var foam: Float = 0
                for cascade in 0 ..< 4 {
                    foam += sampleField(
                        fields[cascade],
                        worldX / lengthScales[cascade],
                        worldY / lengthScales[cascade]
                    )
                }
                combined.append(min(foam, 1))
            }
        }
        let combinedEvidence = summarize(combined)
        return FoamFieldEvidence(
            frame: frame,
            cascades: fields.map(summarize),
            combinedRange: combinedEvidence.range,
            combinedMean: combinedEvidence.mean,
            combinedCoverageAboveFivePercent:
                combinedEvidence.coverageAboveFivePercent,
            combinedCoverageAboveTwentyPercent:
                combinedEvidence.coverageAboveTwentyPercent
        )
    }

    private func verifiedSurfaceEvidence() throws -> FirstFrameEvidence {
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        var innerMinimum = Float.greatestFiniteMagnitude
        var innerMaximum = -Float.greatestFiniteMagnitude
        var innerHeightSum: Double = 0
        var innerHeightSquareSum: Double = 0
        var foundNonFiniteValue = false
        let innerPatchVertexCount = (Self.ringCellsPerSide + 1)
            * (Self.ringCellsPerSide + 1)

        lowLevelMesh.withUnsafeBytes(bufferIndex: 0) { rawBuffer in
            let vertices = rawBuffer.bindMemory(to: OceanVertex.self)
            for (index, vertex) in vertices.enumerated() {
                guard vertex.position.y.isFinite else {
                    foundNonFiniteValue = true
                    continue
                }
                minimum = min(minimum, vertex.position.y)
                maximum = max(maximum, vertex.position.y)
                if index < innerPatchVertexCount {
                    innerMinimum = min(innerMinimum, vertex.position.y)
                    innerMaximum = max(innerMaximum, vertex.position.y)
                    innerHeightSum += Double(vertex.position.y)
                    innerHeightSquareSum += Double(vertex.position.y)
                        * Double(vertex.position.y)
                }
            }
        }

        guard !foundNonFiniteValue,
              minimum != Float.greatestFiniteMagnitude,
              maximum != -Float.greatestFiniteMagnitude,
              innerMinimum != Float.greatestFiniteMagnitude,
              innerMaximum != -Float.greatestFiniteMagnitude
        else {
            throw OceanProbeRendererError.nonFiniteSurface
        }
        let sampleCount = Double(innerPatchVertexCount)
        let mean = innerHeightSum / sampleCount
        let variance = max(
            0,
            innerHeightSquareSum / sampleCount - mean * mean
        )
        return FirstFrameEvidence(
            heightRange: minimum ... maximum,
            innerPatchHeightRange: innerMinimum ... innerMaximum,
            innerPatchSignificantWaveHeight: Float(4 * variance.squareRoot())
        )
    }

    private func makeUniforms(
        time: Float,
        deltaTime: Float,
        parameters: OceanProbeParameters,
        cascadePlan: CascadeUpdatePlan
    ) -> OceanUniforms {
        OceanUniforms(
            resolution: UInt32(Self.resolution),
            seed: parameters.seed,
            depth: parameters.waterDepth,
            gravity: 9.81,
            frameTime: time * parameters.timeScale,
            deltaTime: cascadePlan.primaryFoamElapsed,
            repeatTime: parameters.repeatTime,
            inverseFFTScale: 1,
            lengthScales: parameters.cascades.lengthScales,
            cutoffLow: parameters.cascades.cutoffLow,
            cutoffHigh: parameters.cascades.cutoffHigh,
            choppiness: parameters.choppiness,
            foamBias: parameters.foam.bias,
            foamPower: parameters.foam.power,
            foamAdd: parameters.foam.amount,
            foamDecay: parameters.foam.decay,
            activeCascadeCount: cascadePlan.activeCascadeCount,
            detailDeltaTime: cascadePlan.detailFoamElapsed,
            cascadeStart: cascadePlan.cascadeStart
        )
    }

    private func installMaterialLayoutIfNeeded(
        _ layout: CascadeLayout
    ) throws {
        guard installedMaterialLayout != layout else {
            return
        }
        var updatedMaterial = surfaceMaterial
        for index in 0 ..< 4 {
            try updatedMaterial.setParameter(
                name: PublishedSurfaceFields.inverseLengthNames[index],
                value: .float(layout.inverseLengthScales[index])
            )
        }
        surfaceMaterial = updatedMaterial
        surfaceEntity?.model?.materials = [updatedMaterial]
        installedMaterialLayout = layout
    }

    private static func appearanceParameters(
        from material: ShaderGraphMaterial
    ) -> [String: MaterialParameters.Value] {
        let runtimeNames = Set(
            PublishedSurfaceFields.textureNames
                + PublishedSurfaceFields.inverseLengthNames
        )
        return Dictionary(uniqueKeysWithValues: material.parameterNames.compactMap {
            name in
            guard !runtimeNames.contains(name),
                  let value = material.getParameter(name: name)
            else {
                return nil
            }
            return (name, value)
        })
    }

    private func makeWindSpectrumParameters(
        _ parameters: OceanProbeParameters
    ) -> [WindSpectrumParameters] {
        let scalePairs: [(Float, Float)] = [
            (0.45, 0.16),
            (0.24, 0.10),
            (0.12, 0.05),
            (0.06, 0.025),
        ]
        let windFactors: [Float] = [1, 0.82, 0.58, 0.36]
        let fetchFactors: [Float] = [1, 0.72, 0.42, 0.22]
        var result: [WindSpectrumParameters] = []
        result.reserveCapacity(8)

        for cascade in 0 ..< 4 {
            let primaryWind = parameters.windSpeed * windFactors[cascade]
            let primaryFetch = parameters.fetch * fetchFactors[cascade]
            result.append(
                makeWindSpectrum(
                    scale: scalePairs[cascade].0,
                    windSpeed: primaryWind,
                    direction: parameters.windDirectionRadians,
                    fetch: primaryFetch,
                    alignment: parameters.windAlignment,
                    gamma: cascade < 2 ? 4 : 2.5,
                    shortWaveFade: cascade < 2 ? 0.75 : 0.3
                )
            )
            result.append(
                makeWindSpectrum(
                    scale: scalePairs[cascade].1 * parameters.crossSeaAmount,
                    windSpeed: primaryWind * 0.86,
                    direction: parameters.windDirectionRadians
                        + parameters.crossSeaAngleRadians,
                    fetch: primaryFetch * 0.8,
                    alignment: parameters.windAlignment * 0.82,
                    gamma: cascade < 2 ? 3.5 : 2,
                    shortWaveFade: cascade < 2 ? 0.7 : 0.25
                )
            )
        }
        return result
    }

    private func makeWindSpectrum(
        scale: Float,
        windSpeed: Float,
        direction: Float,
        fetch: Float,
        alignment: Float,
        gamma: Float,
        shortWaveFade: Float
    ) -> WindSpectrumParameters {
        let gravity: Float = 9.81
        let alpha = 0.076 * pow(gravity * fetch / (windSpeed * windSpeed), -0.22)
        let peakOmega = 22 * pow(windSpeed * fetch / (gravity * gravity), -0.33)
        return WindSpectrumParameters(
            scale: scale,
            angle: direction,
            spreadBlend: 0.75 + 0.25 * alignment,
            alignment: alignment,
            alpha: alpha,
            peakOmega: peakOmega,
            gamma: gamma,
            shortWavesFade: shortWaveFade
        )
    }

    private func makeSwellSpectrumParameters(
        _ parameters: OceanProbeParameters
    ) -> SwellSpectrumParameters {
        let calibration = SwellSpectrumCalibration(parameters: parameters)
        return SwellSpectrumParameters(
            height: parameters.swellHeight,
            angle: parameters.swellDirectionRadians,
            peakWaveNumber: calibration.peakWaveNumber,
            angularFrequencySigma: calibration.effectiveAngularFrequencySigma,
            directionalSigma: calibration.effectiveDirectionalSigma,
            energyScale: calibration.energyScale
        )
    }

    private func encodeClearOutputs(
        into commandBuffer: any MTLCommandBuffer,
        field: Textures.Field,
        uniforms: inout OceanUniforms
    ) throws {
        let encoder = try makeEncoder(
            commandBuffer,
            label: "Clear FFT Outputs"
        )
        encoder.setComputePipelineState(pipelines.clearOutputs)
        encoder.setTexture(field.displacement, index: 0)
        encoder.setTexture(field.slope, index: 1)
        dispatchTexture(encoder, pipeline: pipelines.clearOutputs)
        encoder.endEncoding()
    }

    private func encodeSpectrumInitialization(
        into commandBuffer: any MTLCommandBuffer,
        uniforms: inout OceanUniforms,
        windSpectra: inout [WindSpectrumParameters],
        swellSpectrum: inout SwellSpectrumParameters
    ) throws {
        let encoder = try makeEncoder(
            commandBuffer,
            label: "Initialize JONSWAP Spectrum"
        )
        encoder.setComputePipelineState(pipelines.initializeSpectrum)
        encoder.setTexture(textures.initialSpectrum, index: 0)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<OceanUniforms>.stride,
            index: 0
        )
        windSpectra.withUnsafeBufferPointer { buffer in
            encoder.setBytes(
                buffer.baseAddress!,
                length: MemoryLayout<WindSpectrumParameters>.stride * buffer.count,
                index: 1
            )
        }
        encoder.setBytes(
            &swellSpectrum,
            length: MemoryLayout<SwellSpectrumParameters>.stride,
            index: 2
        )
        dispatchTexture(encoder, pipeline: pipelines.initializeSpectrum)
        encoder.endEncoding()
    }

    private func encodeSpectrumConjugates(
        into commandBuffer: any MTLCommandBuffer,
        uniforms: inout OceanUniforms
    ) throws {
        let encoder = try makeEncoder(
            commandBuffer,
            label: "Pack Spectrum Conjugates"
        )
        encoder.setComputePipelineState(pipelines.packSpectrumConjugate)
        encoder.setTexture(textures.initialSpectrum, index: 0)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<OceanUniforms>.stride,
            index: 0
        )
        dispatchTexture(encoder, pipeline: pipelines.packSpectrumConjugate)
        encoder.endEncoding()
    }

    private func encodeSpectrumEvolution(
        into commandBuffer: any MTLCommandBuffer,
        uniforms: inout OceanUniforms
    ) throws {
        let encoder = try makeEncoder(
            commandBuffer,
            label: "Evolve Ocean Spectrum"
        )
        encoder.setComputePipelineState(pipelines.updateSpectrum)
        encoder.setTexture(textures.initialSpectrum, index: 0)
        encoder.setTexture(textures.spectrum, index: 1)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<OceanUniforms>.stride,
            index: 0
        )
        dispatchTexture(encoder, pipeline: pipelines.updateSpectrum)
        encoder.endEncoding()
    }

    private func encodeIFFT(
        pipeline: any MTLComputePipelineState,
        label: String,
        into commandBuffer: any MTLCommandBuffer,
        uniforms: inout OceanUniforms
    ) throws {
        let encoder = try makeEncoder(commandBuffer, label: label)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(textures.spectrum, index: 0)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<OceanUniforms>.stride,
            index: 0
        )
        encoder.dispatchThreadgroups(
            MTLSize(width: 1, height: Self.resolution, depth: 1),
            threadsPerThreadgroup: MTLSize(
                width: Self.ifftThreadsPerThreadgroup,
                height: 1,
                depth: 1
            )
        )
        encoder.endEncoding()
    }

    private func encodeTextureAssembly(
        into commandBuffer: any MTLCommandBuffer,
        previous: Textures.Field,
        output: Textures.Field,
        resetsFoam: Bool,
        uniforms: inout OceanUniforms
    ) throws {
        let encoder = try makeEncoder(
            commandBuffer,
            label: "Assemble Ocean Fields"
        )
        encoder.setComputePipelineState(pipelines.assembleTextures)
        encoder.setTexture(textures.spectrum, index: 0)
        encoder.setTexture(previous.displacement, index: 1)
        encoder.setTexture(previous.slope, index: 2)
        encoder.setTexture(output.displacement, index: 3)
        encoder.setTexture(output.slope, index: 4)
        encoder.setBytes(
            &uniforms,
            length: MemoryLayout<OceanUniforms>.stride,
            index: 0
        )
        var resetFlag: UInt32 = resetsFoam ? 1 : 0
        encoder.setBytes(
            &resetFlag,
            length: MemoryLayout<UInt32>.stride,
            index: 1
        )
        dispatchTexture(encoder, pipeline: pipelines.assembleTextures)
        encoder.endEncoding()
    }

    private func encodeSurfaceProjection(
        into commandBuffer: any MTLCommandBuffer,
        field: Textures.Field,
        vertexBuffer: any MTLBuffer,
        uniforms: inout SurfaceUniforms,
        publishedTargets: [any MTLTexture],
        cascadeCount: Int,
        publicationUniforms: inout SurfacePublicationUniforms
    ) throws {
        let meshEncoder = try makeEncoder(
            commandBuffer,
            label: "Project FFT to LowLevelMesh"
        )
        meshEncoder.setComputePipelineState(pipelines.projectSurface)
        meshEncoder.setTexture(field.displacement, index: 0)
        meshEncoder.setBuffer(vertexBuffer, offset: 0, index: 0)
        meshEncoder.setBytes(
            &uniforms,
            length: MemoryLayout<SurfaceUniforms>.stride,
            index: 1
        )
        meshEncoder.setBuffer(gridVertexBuffer, offset: 0, index: 2)
        dispatchLinear(
            meshEncoder,
            pipeline: pipelines.projectSurface,
            count: lowLevelMesh.vertexCapacity
        )
        meshEncoder.endEncoding()

        let publicationEncoder = try makeEncoder(
            commandBuffer,
            label: "Publish Ocean Surface Fields"
        )
        let publicationPipeline = cascadeCount == 4
            ? pipelines.publishSurfaceFields
            : pipelines.publishPrimarySurfaceFields
        publicationEncoder.setComputePipelineState(publicationPipeline)
        publicationEncoder.setTexture(field.slope, index: 0)
        publicationEncoder.setTexture(field.displacement, index: 1)
        for cascade in publishedTargets.indices {
            publicationEncoder.setTexture(
                publishedTargets[cascade],
                index: cascade + 2
            )
        }
        publicationEncoder.setBytes(
            &publicationUniforms,
            length: MemoryLayout<SurfacePublicationUniforms>.stride,
            index: 0
        )
        dispatchTexture(
            publicationEncoder,
            pipeline: publicationPipeline,
            resolution: Self.publishedFieldResolution
        )
        publicationEncoder.endEncoding()
    }

    private func encodePublishedFieldMipmaps(
        into commandBuffer: any MTLCommandBuffer,
        textures: [any MTLTexture]
    ) throws {
        guard let encoder = commandBuffer.makeBlitCommandEncoder() else {
            throw OceanProbeRendererError.computeEncoderUnavailable(
                "Generate Published Field Mipmaps"
            )
        }
        encoder.label = "Generate Published Field Mipmaps"
        for (index, texture) in textures.enumerated() {
            precondition(
                texture.mipmapLevelCount
                    == PublishedSurfaceFields.mipLevelCounts[index]
            )
            encoder.generateMipmaps(for: texture)
        }
        encoder.endEncoding()
    }

    private func makeEncoder(
        _ commandBuffer: any MTLCommandBuffer,
        label: String
    ) throws -> any MTLComputeCommandEncoder {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw OceanProbeRendererError.computeEncoderUnavailable(label)
        }
        encoder.label = label
        return encoder
    }

    private func dispatchTexture(
        _ encoder: any MTLComputeCommandEncoder,
        pipeline: any MTLComputePipelineState,
        resolution: Int = OceanProbeRenderer.resolution
    ) {
        let width = pipeline.threadExecutionWidth
        let height = max(pipeline.maxTotalThreadsPerThreadgroup / width, 1)
        encoder.dispatchThreads(
            MTLSize(width: resolution, height: resolution, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
        )
    }

    private func dispatchLinear(
        _ encoder: any MTLComputeCommandEncoder,
        pipeline: any MTLComputePipelineState,
        count: Int
    ) {
        let width = pipeline.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: count, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1)
        )
    }

    private static func makeGridMesh() throws -> (
        lowLevelMesh: LowLevelMesh,
        meshResource: MeshResource,
        gridVertices: [OceanVertex]
    ) {
        let side = ringCellsPerSide + 1
        var sourceVertices: [OceanVertex] = []
        var sourceIndices: [UInt32] = []
        sourceVertices.reserveCapacity(side * side * ringCount)

        for level in 0 ..< ringCount {
            let levelStart = UInt32(sourceVertices.count)
            let outerHalfExtent = innerPatchSize * 0.5
                * pow(2, Float(level))
            let innerHalfExtent = level == 0
                ? 0
                : outerHalfExtent * 0.5
            let cellSize = outerHalfExtent * 2
                / Float(ringCellsPerSide)

            for row in 0 ..< side {
                for column in 0 ..< side {
                    let uv = SIMD2<Float>(
                        Float(column) / Float(ringCellsPerSide),
                        Float(row) / Float(ringCellsPerSide)
                    )
                    let baseXZ = (uv - 0.5) * (outerHalfExtent * 2)
                    let stitch: SIMD4<Float>
                    if level < ringCount - 1,
                       (row == 0 || row == ringCellsPerSide),
                       column.isMultiple(of: 2) == false
                    {
                        stitch = SIMD4<Float>(cellSize, 0, 1, 0)
                    } else if level < ringCount - 1,
                              (column == 0 || column == ringCellsPerSide),
                              row.isMultiple(of: 2) == false
                    {
                        stitch = SIMD4<Float>(0, cellSize, 1, 0)
                    } else {
                        stitch = .zero
                    }
                    sourceVertices.append(
                        OceanVertex(
                            position: SIMD3<Float>(baseXZ.x, 0, baseXZ.y),
                            normal: SIMD3<Float>(0, 1, 0),
                            tangent: SIMD4<Float>(1, 0, 0, 1),
                            uv: baseXZ,
                            baseXZ: baseXZ,
                            stitch: stitch
                        )
                    )
                }
            }

            for row in 0 ..< ringCellsPerSide {
                for column in 0 ..< ringCellsPerSide {
                    let cellCenter = SIMD2<Float>(
                        (Float(column) + 0.5) / Float(ringCellsPerSide),
                        (Float(row) + 0.5) / Float(ringCellsPerSide)
                    )
                    let centerXZ = (cellCenter - 0.5)
                        * (outerHalfExtent * 2)
                    if level > 0,
                       max(abs(centerXZ.x), abs(centerXZ.y))
                        < innerHalfExtent
                    {
                        continue
                    }

                    let upperLeft = levelStart
                        + UInt32(row * side + column)
                    let upperRight = upperLeft + 1
                    let lowerLeft = upperLeft + UInt32(side)
                    let lowerRight = lowerLeft + 1
                    sourceIndices.append(contentsOf: [
                        upperLeft,
                        lowerLeft,
                        upperRight,
                        upperRight,
                        lowerLeft,
                        lowerRight,
                    ])
                }
            }
        }

        let descriptor = LowLevelMesh.Descriptor(
            vertexCapacity: sourceVertices.count,
            vertexAttributes: [
                .init(
                    semantic: .position,
                    format: .float3,
                    offset: MemoryLayout<OceanVertex>.offset(of: \.position)!
                ),
                .init(
                    semantic: .normal,
                    format: .float3,
                    offset: MemoryLayout<OceanVertex>.offset(of: \.normal)!
                ),
                .init(
                    semantic: .tangent,
                    format: .float4,
                    offset: MemoryLayout<OceanVertex>.offset(of: \.tangent)!
                ),
                .init(
                    semantic: .uv0,
                    format: .float2,
                    offset: MemoryLayout<OceanVertex>.offset(of: \.uv)!
                ),
                .init(
                    semantic: .uv1,
                    format: .float2,
                    offset: MemoryLayout<OceanVertex>.offset(of: \.baseXZ)!
                ),
            ],
            vertexLayouts: [
                .init(
                    bufferIndex: 0,
                    bufferStride: MemoryLayout<OceanVertex>.stride
                ),
            ],
            indexCapacity: sourceIndices.count,
            indexType: .uint32
        )
        let mesh = try LowLevelMesh(descriptor: descriptor)

        mesh.replaceUnsafeMutableBytes(bufferIndex: 0) { rawBuffer in
            let vertices = rawBuffer.bindMemory(to: OceanVertex.self)
            for index in sourceVertices.indices {
                vertices[index] = sourceVertices[index]
            }
        }

        mesh.replaceUnsafeMutableIndices { rawBuffer in
            let indices = rawBuffer.bindMemory(to: UInt32.self)
            for index in sourceIndices.indices {
                indices[index] = sourceIndices[index]
            }
        }

        let halfExtent = innerPatchSize * 0.5
            * pow(2, Float(ringCount - 1))
            + 8
        mesh.parts.replaceAll([
            LowLevelMesh.Part(
                indexCount: sourceIndices.count,
                topology: .triangle,
                materialIndex: 0,
                bounds: BoundingBox(
                    min: SIMD3<Float>(-halfExtent, -8, -halfExtent),
                    max: SIMD3<Float>(halfExtent, 8, halfExtent)
                )
            ),
        ])
        return (mesh, try MeshResource(from: mesh), sourceVertices)
    }
}

private extension OceanProbeRenderer {
    struct Pipelines {
        let initializeSpectrum: any MTLComputePipelineState
        let packSpectrumConjugate: any MTLComputePipelineState
        let updateSpectrum: any MTLComputePipelineState
        let horizontalIFFT: any MTLComputePipelineState
        let verticalIFFT: any MTLComputePipelineState
        let assembleTextures: any MTLComputePipelineState
        let clearOutputs: any MTLComputePipelineState
        let projectSurface: any MTLComputePipelineState
        let projectSurfaceBlended: any MTLComputePipelineState
        let publishSurfaceFields: any MTLComputePipelineState
        let publishPrimarySurfaceFields: any MTLComputePipelineState
        let publishSurfaceFieldsBlended: any MTLComputePipelineState

        init(device: any MTLDevice, library: any MTLLibrary) throws {
            func make(_ name: String) throws -> any MTLComputePipelineState {
                guard let function = library.makeFunction(name: name) else {
                    throw OceanProbeRendererError.computeFunctionUnavailable(name)
                }
                return try device.makeComputePipelineState(function: function)
            }

            initializeSpectrum = try make("initializeSpectrum")
            packSpectrumConjugate = try make("packSpectrumConjugate")
            updateSpectrum = try make("updateSpectrum")
            horizontalIFFT = try make("horizontalIFFT")
            verticalIFFT = try make("verticalIFFT")
            assembleTextures = try make("assembleTextures")
            clearOutputs = try make("clearOutputs")
            projectSurface = try make("projectSurface")
            projectSurfaceBlended = try make("projectSurfaceBlended")
            publishSurfaceFields = try make("publishSurfaceFields")
            publishPrimarySurfaceFields = try make("publishPrimarySurfaceFields")
            publishSurfaceFieldsBlended = try make("publishSurfaceFieldsBlended")
        }
    }

    struct Textures {
        struct Field {
            let displacement: any MTLTexture
            let slope: any MTLTexture
        }

        let initialSpectrum: any MTLTexture
        let spectrum: any MTLTexture
        let fields: [Field]

        init(
            device: any MTLDevice,
            resolution: Int
        ) throws {
            initialSpectrum = try Self.makeTexture(
                device: device,
                name: "Initial Spectrum",
                format: .rgba16Float,
                resolution: resolution,
                arrayLength: 4,
                mipmapped: true
            )
            spectrum = try Self.makeTexture(
                device: device,
                name: "Evolved Spectrum",
                format: .rgba16Float,
                resolution: resolution,
                arrayLength: 8,
                mipmapped: true
            )
            fields = try (0 ..< 2).map { slot in
                Field(
                    displacement: try Self.makeTexture(
                        device: device,
                        name: "Ocean Displacement and Foam \(slot)",
                        format: .rgba16Float,
                        resolution: resolution,
                        arrayLength: 4
                    ),
                    slope: try Self.makeTexture(
                        device: device,
                        name: "Ocean Slope \(slot)",
                        format: .rg16Float,
                        resolution: resolution,
                        arrayLength: 4
                    )
                )
            }
        }

        private static func makeTexture(
            device: any MTLDevice,
            name: String,
            format: MTLPixelFormat,
            resolution: Int,
            arrayLength: Int,
            mipmapped: Bool = false
        ) throws -> any MTLTexture {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = arrayLength == 1 ? .type2D : .type2DArray
            descriptor.pixelFormat = format
            descriptor.width = resolution
            descriptor.height = resolution
            descriptor.depth = 1
            descriptor.mipmapLevelCount = mipmapped
                ? Int(log2(Float(resolution))) + 1
                : 1
            descriptor.arrayLength = arrayLength
            descriptor.sampleCount = 1
            descriptor.storageMode = .private
            descriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw OceanProbeRendererError.textureAllocationFailed(name)
            }
            texture.label = name
            return texture
        }
    }
}
