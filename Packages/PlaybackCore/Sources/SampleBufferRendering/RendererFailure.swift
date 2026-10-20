public enum RendererFailureKind: String, Sendable {
    case video
    case audio
}

public struct RendererFailureFact: Equatable, Sendable {
    public var rendererKind: RendererFailureKind
    public var errorType: String
    public var message: String
    public var requiresFlushToResumeDecoding: Bool?

    public init(
        rendererKind: RendererFailureKind,
        errorType: String,
        message: String,
        requiresFlushToResumeDecoding: Bool?
    ) {
        self.rendererKind = rendererKind
        self.errorType = errorType
        self.message = message
        self.requiresFlushToResumeDecoding = requiresFlushToResumeDecoding
    }
}
