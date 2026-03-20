import Foundation

public enum WebDAVError: LocalizedError {
    case invalidConnectionInfo
    case notConnected
    case invalidResponse
    case requestFailed(Int)
    case malformedResponse
    case emptyDirectoryListing

    public var errorDescription: String? {
        switch self {
        case .invalidConnectionInfo:
            return "Invalid WebDAV connection information."
        case .notConnected:
            return "WebDAV data source is not connected."
        case .invalidResponse:
            return "WebDAV server returned an invalid response."
        case .requestFailed(let statusCode):
            return "WebDAV request failed with HTTP status \(statusCode)."
        case .malformedResponse:
            return "WebDAV server returned malformed XML."
        case .emptyDirectoryListing:
            return "WebDAV server returned only the current directory entry. Directory listing could not be resolved."
        }
    }
}

public final class WebDAVDataSourceAdapter: DataSourceConnecting, FileProviding {
    /// Stable DataSource ID for folder identity pass-through.
    public var ownerDataSourceID: UUID = UUID()
    private var baseURL: URL?
    private var authHeader: String?
    private var connectionInfo: FileBrowsingDomain.ConnectionInfo?
    private(set) public var connectionStatus: FileBrowsingDomain.ConnectionStatus = .disconnected
    private let session: URLSession
    private let credentialStore: CredentialStoring?
    private let filter = FileBrowsingDomain.FileFilter.playable

    public init(credentialStore: CredentialStoring? = nil, session: URLSession? = nil) {
        self.credentialStore = credentialStore
        self.session = session ?? URLSession(configuration: .default)
    }

    public func connect(with info: FileBrowsingDomain.ConnectionInfo) async throws {
        connectionStatus = .connecting

        do {
            let rootURL = try buildBaseURL(from: info)
            authHeader = try buildAuthHeader(info: info)
            let validatedURL = try await validateConnection(startingAt: rootURL)

            baseURL = validatedURL
            connectionInfo = info

            connectionStatus = .connected
        } catch {
            connectionStatus = .failed(error.localizedDescription)
            throw error
        }
    }

    public func disconnect() {
        baseURL = nil
        authHeader = nil
        connectionInfo = nil
        connectionStatus = .disconnected
    }

    public func listContents(at path: String) async throws -> [FileBrowsingDomain.MediaFile] {
        guard let baseURL else {
            throw WebDAVError.notConnected
        }

        let targetURL = try buildRequestURL(baseURL: baseURL, path: path)
        let responses = try await performPROPFIND(url: targetURL)
        let normalizedTargetPath = normalizedComparablePath(targetURL.path)

        return responses.compactMap { responseItem in
            guard isDirectory(responseItem) == false else { return nil }
            guard let href = responseItem.href, let fileURL = resolveFileURL(from: href, requestURL: targetURL) else {
                return nil
            }

            if normalizedComparablePath(fileURL.path) == normalizedTargetPath {
                return nil
            }
            guard filter.matches(fileURL: fileURL) else {
                return nil
            }

            let modifiedAt = parseHTTPDate(responseItem.lastModified) ?? .distantPast
            let sizeInBytes = Int64(responseItem.contentLength ?? "") ?? 0
            let fileName = fileURL.lastPathComponent.removingPercentEncoding ?? fileURL.lastPathComponent

            return FileBrowsingDomain.MediaFile(
                name: fileName,
                sizeInBytes: sizeInBytes,
                modifiedAt: modifiedAt,
                fileExtension: fileURL.pathExtension,
                url: fileURL
            )
        }
    }

    public func listFolders(at path: String) async throws -> [FileBrowsingDomain.MediaFolder] {
        guard let baseURL else {
            throw WebDAVError.notConnected
        }

        let targetURL = try buildRequestURL(baseURL: baseURL, path: path)
        let responses = try await performPROPFIND(url: targetURL)
        let normalizedTargetPath = normalizedComparablePath(targetURL.path)

        return responses.compactMap { responseItem in
            guard isDirectory(responseItem) else { return nil }
            guard let href = responseItem.href,
                  let folderURL = resolveFileURL(from: href, requestURL: targetURL) else {
                return nil
            }

            if normalizedComparablePath(folderURL.path) == normalizedTargetPath {
                return nil
            }

            let folderName = folderURL.lastPathComponent.removingPercentEncoding
                ?? folderURL.lastPathComponent

            return FileBrowsingDomain.MediaFolder(
                name: folderName,
                dataSourceID: ownerDataSourceID,
                path: folderURL.path,
                url: folderURL
            )
        }
    }

    public func listFiles(
        in folder: FileBrowsingDomain.MediaFolder,
        sortBy: FileBrowsingDomain.SortCriteria
    ) async throws -> [FileBrowsingDomain.MediaFile] {
        let files = try await listContents(at: folder.path)
        return sortBy.sorted(files)
    }

    public func resolveURL(for item: FileBrowsingDomain.MediaFile) async throws -> URL {
        item.url
    }

    public func resolvePlayableURL(for file: FileBrowsingDomain.MediaFile) async throws -> URL {
        guard let info = connectionInfo else {
            return file.url
        }

        // Try loading credentials from keychain to embed in URL for mpv playback
        let sourceID = info.credentialSourceID
        if let credentialStore,
           let credential = try? credentialStore.loadCredential(for: sourceID),
           !credential.username.isEmpty {
            return embedCredentials(
                in: file.url,
                username: credential.username,
                password: credential.password
            )
        }

        // Fallback: use username from ConnectionInfo
        if let username = info.username, !username.isEmpty {
            return embedCredentials(in: file.url, username: username, password: "")
        }

        return file.url
    }

    private func embedCredentials(in url: URL, username: String, password: String) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.user = username
        if !password.isEmpty {
            components.password = password
        }
        return components.url ?? url
    }

    private func performPROPFIND(url: URL) async throws -> [PROPFINDParserDelegate.ResponseItem] {
        let primaryResult = try await performPROPFINDRequest(url: url)
        logPROPFINDResult(url: url, result: primaryResult)

        if isSelfOnlyResponse(primaryResult.responses, requestURL: url) {
            let retryURL = directoryURL(for: url)
            if retryURL != url {
                let retryResult = try await performPROPFINDRequest(url: retryURL)
                logPROPFINDResult(url: retryURL, result: retryResult)

                if isSelfOnlyResponse(retryResult.responses, requestURL: retryURL) == false {
                    return retryResult.responses
                }
            }

            throw WebDAVError.emptyDirectoryListing
        }

        return primaryResult.responses
    }

    private func performPROPFINDRequest(
        url: URL
    ) async throws -> (responses: [PROPFINDParserDelegate.ResponseItem], xml: String) {
        var request = URLRequest(url: url)
        request.httpMethod = "PROPFIND"
        request.setValue("1", forHTTPHeaderField: "Depth")
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = Self.propfindBody.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WebDAVError.invalidResponse
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw WebDAVError.requestFailed(httpResponse.statusCode)
        }

        let parser = XMLParser(data: data)
        let delegate = PROPFINDParserDelegate()
        parser.delegate = delegate

        guard parser.parse() else {
            throw WebDAVError.malformedResponse
        }

        return (delegate.responses, String(decoding: data, as: UTF8.self))
    }

    private func validateConnection(startingAt rootURL: URL) async throws -> URL {
        var lastError: Error = WebDAVError.invalidConnectionInfo

        for candidateURL in candidateBaseURLs(startingAt: rootURL) {
            do {
                let result = try await performPROPFINDRequest(url: candidateURL)
                logPROPFINDResult(url: candidateURL, result: result)
                return candidateURL
            } catch {
                lastError = error
            }
        }

        throw lastError
    }

    private func candidateBaseURLs(startingAt rootURL: URL) -> [URL] {
        let preferredURL = directoryURL(for: rootURL)
        if preferredURL == rootURL {
            return [rootURL]
        }
        return [preferredURL, rootURL]
    }

    private func buildBaseURL(from info: FileBrowsingDomain.ConnectionInfo) throws -> URL {
        guard let host = info.host?.trimmingCharacters(in: .whitespacesAndNewlines), host.isEmpty == false else {
            throw WebDAVError.invalidConnectionInfo
        }

        var components = URLComponents()
        components.scheme = info.scheme ?? (info.port == 443 ? "https" : "http")
        components.host = host
        if let port = info.port {
            components.port = port
        }
        components.path = normalizedPath(info.rootPath)

        guard let url = components.url else {
            throw WebDAVError.invalidConnectionInfo
        }
        return url
    }

    private func buildAuthHeader(
        info: FileBrowsingDomain.ConnectionInfo
    ) throws -> String? {
        let sourceID = info.credentialSourceID

        if let credentialStore,
           let credential = try credentialStore.loadCredential(for: sourceID),
           !credential.username.isEmpty {
            let token = Data("\(credential.username):\(credential.password)".utf8).base64EncodedString()
            return "Basic \(token)"
        }

        // Fallback: use username from ConnectionInfo without password (anonymous)
        guard let username = info.username, !username.isEmpty else {
            return nil
        }
        let token = Data("\(username):".utf8).base64EncodedString()
        return "Basic \(token)"
    }

    private func buildRequestURL(baseURL: URL, path: String) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let requestedPath = normalizedPath(path)
        let baseComparablePath = normalizedComparablePath(baseURL.path)
        let requestedComparablePath = normalizedComparablePath(requestedPath)

        if requestedPath == "/" {
            components?.path = normalizedPath(baseURL.path)
        } else if requestedComparablePath == baseComparablePath {
            components?.path = requestedPath
        } else if baseComparablePath == "/" || requestedComparablePath.hasPrefix(baseComparablePath + "/") {
            components?.path = requestedPath
        } else {
            components?.path = joinPath(base: baseComparablePath, relativePath: requestedPath)
        }

        guard let resolved = components?.url else {
            throw WebDAVError.invalidConnectionInfo
        }
        return resolved
    }

    private func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "/" }
        if trimmed.hasPrefix("/") {
            return trimmed
        }
        return "/" + trimmed
    }

    private func joinPath(base: String, relativePath: String) -> String {
        let normalizedBase = normalizedComparablePath(base)
        let normalizedRelative = normalizedPath(relativePath)

        if normalizedBase == "/" {
            return normalizedRelative
        }

        return normalizedBase + normalizedRelative
    }

    private func resolveFileURL(from href: String, requestURL: URL) -> URL? {
        if let absolute = URL(string: href), absolute.scheme != nil {
            return absolute
        }
        return URL(string: href, relativeTo: requestURL)?.absoluteURL
    }

    private func parseHTTPDate(_ value: String?) -> Date? {
        guard let value, value.isEmpty == false else { return nil }
        return Self.httpDateFormatter.date(from: value)
    }

    private func normalizedComparablePath(_ path: String) -> String {
        let normalized = normalizedPath(path)
        if normalized.count > 1 && normalized.hasSuffix("/") {
            return String(normalized.dropLast())
        }
        return normalized
    }

    private func isDirectory(_ responseItem: PROPFINDParserDelegate.ResponseItem) -> Bool {
        if responseItem.isCollection {
            return true
        }

        guard let href = responseItem.href?.trimmingCharacters(in: .whitespacesAndNewlines),
              href.isEmpty == false else {
            return false
        }

        return href.hasSuffix("/")
    }

    private func isSelfOnlyResponse(
        _ responses: [PROPFINDParserDelegate.ResponseItem],
        requestURL: URL
    ) -> Bool {
        guard responses.count == 1,
              let href = responses.first?.href,
              let resolvedURL = resolveFileURL(from: href, requestURL: requestURL) else {
            return false
        }

        return normalizedComparablePath(resolvedURL.path) == normalizedComparablePath(requestURL.path)
    }

    private func directoryURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        let path = normalizedPath(components.path)
        guard path.hasSuffix("/") == false else {
            return url
        }

        components.path = path + "/"
        return components.url ?? url
    }

    private func logPROPFINDResult(
        url: URL,
        result: (responses: [PROPFINDParserDelegate.ResponseItem], xml: String)
    ) {
        let hrefs = result.responses.compactMap(\.href).joined(separator: ", ")
        print("[WebDAV] PROPFIND url=\(url.absoluteString)")
        print("[WebDAV] PROPFIND responses=\(result.responses.count) hrefs=[\(hrefs)]")
        if result.responses.count <= 1 {
            print("[WebDAV] PROPFIND xml=\(result.xml)")
        }
    }

    private static let propfindBody = """
    <?xml version="1.0"?>
    <d:propfind xmlns:d="DAV:">
      <d:prop>
        <d:href/>
        <d:getcontentlength/>
        <d:getlastmodified/>
        <d:resourcetype/>
      </d:prop>
    </d:propfind>
    """

    private static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return formatter
    }()
}

private final class PROPFINDParserDelegate: NSObject, XMLParserDelegate {
    struct ResponseItem {
        var href: String?
        var contentLength: String?
        var lastModified: String?
        var isCollection: Bool = false
    }

    private struct Propstat {
        var statusCode: Int?
        var contentLength: String?
        var lastModified: String?
        var isCollection: Bool = false
    }

    private(set) var responses: [ResponseItem] = []
    private var elementStack: [String] = []
    private var currentResponse: ResponseItem?
    private var currentPropstat: Propstat?
    private var buffer: String = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = normalized(elementName)
        elementStack.append(name)

        if name == "response" {
            currentResponse = ResponseItem()
        }

        if name == "propstat" {
            currentPropstat = Propstat()
        }

        if name == "collection", currentPropstat != nil, elementStack.contains("resourcetype") {
            currentPropstat?.isCollection = true
        }

        if name == "href" || name == "getcontentlength" || name == "getlastmodified" || name == "status" {
            buffer = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard currentResponse != nil,
              let currentElement = elementStack.last,
              currentElement == "href"
                || currentElement == "getcontentlength"
                || currentElement == "getlastmodified"
                || currentElement == "status"
        else {
            return
        }
        buffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = normalized(elementName)

        if var response = currentResponse {
            switch name {
            case "href":
                if currentPropstat == nil {
                    response.href = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    currentResponse = response
                }
            case "getcontentlength":
                if var propstat = currentPropstat {
                    propstat.contentLength = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    currentPropstat = propstat
                }
            case "getlastmodified":
                if var propstat = currentPropstat {
                    propstat.lastModified = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    currentPropstat = propstat
                }
            case "status":
                if var propstat = currentPropstat {
                    propstat.statusCode = parseStatusCode(buffer)
                    currentPropstat = propstat
                }
            case "propstat":
                if let propstat = currentPropstat, let statusCode = propstat.statusCode, (200 ... 299).contains(statusCode) {
                    if let contentLength = propstat.contentLength {
                        response.contentLength = contentLength
                    }
                    if let lastModified = propstat.lastModified {
                        response.lastModified = lastModified
                    }
                    if propstat.isCollection {
                        response.isCollection = true
                    }
                    currentResponse = response
                }
                currentPropstat = nil
            case "response":
                responses.append(response)
                currentResponse = nil
            default:
                break
            }
        }

        if elementStack.isEmpty == false {
            elementStack.removeLast()
        }
        buffer = ""
    }

    private func normalized(_ raw: String) -> String {
        raw.split(separator: ":").last?.lowercased() ?? raw.lowercased()
    }

    private func parseStatusCode(_ value: String) -> Int? {
        let components = value.split(separator: " ")
        guard components.count >= 2 else {
            return nil
        }
        return Int(components[1])
    }
}
