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
        // Artwork arrives whenever the decode finishes, which is a different moment for every image
        // on a page. Fading each one in turns that scatter into an entrance.
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

private struct LoadedImage {
    let url: URL
    let image: CGImage
}

private enum ArtworkImageLoader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache.shared
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    /// Decoded bitmaps, keyed by URL. `URLCache` already keeps the compressed bytes on disk; what
    /// repeats on every reappearance is the decode, and its result can only live in memory. Emby
    /// puts the image's content tag in the URL, so a changed artwork is a different key.
    /// `NSCache` is thread-safe, so the shared instance needs no further isolation.
    nonisolated(unsafe) private static let decoded: NSCache<NSURL, CGImage> = {
        let cache = NSCache<NSURL, CGImage>()
        cache.totalCostLimit = 64 * 1024 * 1024
        return cache
    }()

    static func image(at url: URL) async throws -> CGImage {
        if let cached = decoded.object(forKey: url as NSURL) { return cached }
        let request = URLRequest(
            url: url,
            cachePolicy: .useProtocolCachePolicy
        )
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        guard let response = response as? HTTPURLResponse,
              (200...299).contains(response.statusCode) else {
            throw LoadError.invalidResponse
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LoadError.invalidImage
        }
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
                    DesignTokens.Theme.surfaceContainerHighest,
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

/// Decodes artwork ahead of the screen that shows it, so a page opens with its images already in
/// memory instead of decoding a screenful at once while the user waits.
public enum ArtworkPrefetch {
    /// How many images one warm-up pass will decode. The decoded cache is bounded too, so a larger
    /// budget would only evict what it just loaded.
    public static let budget = 60
    /// Decodes running at once. Enough to keep the network busy without competing with the frames
    /// of whatever is on screen while this runs.
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
