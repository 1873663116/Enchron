import CoreGraphics
import DesignSystem
import Foundation
import ImageIO
import SwiftUI

public struct EmbyAsyncPosterImage: View {
    private let url: URL?

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        EmbyAsyncImage(url: url, contentMode: .fill)
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
    }
}

public struct EmbyAsyncImage: View {
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
                EmbyPosterPlaceholder()
            }
        }
        .task(id: url) {
            loadedImage = nil
            guard let url else { return }

            do {
                let image = try await EmbyPosterImageLoader.image(at: url)
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

private enum EmbyPosterImageLoader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache.shared
        configuration.requestCachePolicy = .useProtocolCachePolicy
        return URLSession(configuration: configuration)
    }()

    static func image(at url: URL) async throws -> CGImage {
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
        return image
    }

    private enum LoadError: Error {
        case invalidResponse
        case invalidImage
    }
}
