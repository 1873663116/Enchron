import CoreGraphics
import Foundation
import ImageIO
import SwiftUI

public struct AsyncArtworkImage: View {
    private let url: URL?
    private let contentMode: ContentMode

    @State private var loadedImage: LoadedImage?

    public init(url: URL?, contentMode: ContentMode = .fill) {
        self.url = url
        self.contentMode = contentMode
    }

    public var body: some View {
        Group {
            if let loadedImage, loadedImage.url == url {
                Image(decorative: loadedImage.image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ArtworkPlaceholder()
            }
        }
        .animation(DesignTokens.AnimationToken.fadeIn, value: loadedImage?.url)
        .task(id: url) {
            loadedImage = nil
            guard let url else { return }

            do {
                let image = try await ArtworkImageLoader.image(at: url)
                try Task.checkCancellation()
                loadedImage = LoadedImage(url: url, image: image)
            } catch {
                guard !Task.isCancelled else { return }
                loadedImage = nil
            }
        }
    }
}

public enum ArtworkNetworkConfiguration {
    public typealias ImageProvider = @Sendable (URL) -> CGImage?
    public typealias ImageStorer = @Sendable (URL, CGImage) throws -> Void

    nonisolated(unsafe) private static var configuredSession: URLSession = makeDefaultSession()
    nonisolated(unsafe) private static var configuredImageProvider: ImageProvider?
    nonisolated(unsafe) private static var configuredImageStorer: ImageStorer?

    public static func use(
        session: URLSession,
        imageProvider: ImageProvider? = nil,
        imageStorer: ImageStorer? = nil
    ) {
        configuredSession = session
        configuredImageProvider = imageProvider
        configuredImageStorer = imageStorer
    }

    fileprivate static var session: URLSession { configuredSession }
    fileprivate static var imageProvider: ImageProvider? { configuredImageProvider }
    fileprivate static var imageStorer: ImageStorer? { configuredImageStorer }

    private static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache.shared
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }
}

private struct LoadedImage {
    let url: URL
    let image: CGImage
}

private enum ArtworkImageLoader {
    nonisolated(unsafe) private static let decoded: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL) async throws -> CGImage {
        if let persisted = ArtworkNetworkConfiguration.imageProvider?(url) { return persisted }
        if let cached = decoded.object(forKey: url as NSURL) { return cached }
        let request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy
        )
        let (data, response) = try await ArtworkNetworkConfiguration.session.data(for: request)
        try Task.checkCancellation()

        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw LoadError.invalidResponse
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.invalidImage
        }
        try ArtworkNetworkConfiguration.imageStorer?(url, image)
        decoded.setObject(image, forKey: url as NSURL, cost: image.bytesPerRow * image.height)
        return image
    }

    private enum LoadError: Error {
        case invalidResponse
        case invalidImage
    }
}

private struct ArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DesignTokens.Theme.accent.opacity(0.58),
                    DesignTokens.Surface.overlay,
                    DesignTokens.Theme.surfaceContainerHighest
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "film.stack.fill")
                .font(DesignTokens.SymbolSize.giant)
                .foregroundStyle(DesignTokens.Surface.accessoryText)
        }
        .accessibilityHidden(true)
    }
}

public enum ArtworkPrefetch {
    public static let budget = 60
    private static let concurrency = 4

    public static func warm(_ urls: [URL]) async {
        var seen = Set<URL>()
        let targets = urls.filter { seen.insert($0).inserted }.prefix(budget)
        await withTaskGroup(of: Void.self) { group in
            var running = 0
            for url in targets {
                if running == concurrency {
                    await group.next()
                    running -= 1
                }
                group.addTask { _ = try? await ArtworkImageLoader.image(at: url) }
                running += 1
            }
        }
    }
}
