import AppKit
import Foundation

enum ArtworkError: LocalizedError {
    case missingFile
    case unreadable
    case tooLarge
    case host(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The artwork file is missing. Edit the profile and choose the image again."
        case .unreadable:
            return "Couldn’t read that image."
        case .tooLarge:
            return "That image is larger than 50 MB. Choose a smaller file."
        case .host(let detail):
            return "Couldn’t upload artwork. \(detail)"
        }
    }
}

struct PublishedArtwork: Equatable {
    var fingerprint: String
    var publicURL: String
    var assetKey: String
}

enum ArtworkSource {
    case file(URL)
    case remote(URL)

    var byteCount: Int? {
        switch self {
        case .file(let url):
            return (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        case .remote:
            return nil
        }
    }

    var fingerprint: String {
        switch self {
        case .file(let url):
            return ArtworkPublisher.fileFingerprint(url: url) ?? url.path
        case .remote(let url):
            return "url:\(url.absoluteString)"
        }
    }
}

/// Uploads local images to a public host, then registers the public URL with Discord external assets.
///
/// Hosts sometimes accept an upload and still serve nothing (catbox has returned links to empty files),
/// so every new link is fetched back before Discord gets it, and cached links are checked again on apply.
struct ArtworkPublisher {
    private static let userAgent = "DiscordStatusModifier/1.0 (Macintosh)"
    private static let maxBytes = 50 * 1024 * 1024

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func publish(
        source: ArtworkSource,
        cache: PublishedArtwork?
    ) async throws -> PublishedArtwork {
        let applicationID = DiscordClientConfiguration.applicationID
        let fingerprint = source.fingerprint
        if let cache, cache.fingerprint == fingerprint, cache.assetKey.hasPrefix("mp:") {
            return cache
        }

        let publicURL: String
        if let cache, cache.fingerprint == fingerprint, cache.publicURL.hasPrefix("https://"),
           await check(cache.publicURL, expectedBytes: source.byteCount) != .broken {
            publicURL = cache.publicURL
        } else {
            switch source {
            case .file(let url):
                publicURL = try await uploadPublicImage(file: url)
            case .remote(let url):
                publicURL = url.absoluteString
            }
        }

        // discord-rpc accepts direct https URLs as large_image / small_image keys.
        let assetKey: String
        if publicURL.hasPrefix("https://") || publicURL.hasPrefix("http://") {
            assetKey = publicURL
        } else {
            assetKey = await registerExternalAsset(applicationID: applicationID, url: publicURL) ?? publicURL
        }
        return PublishedArtwork(fingerprint: fingerprint, publicURL: publicURL, assetKey: assetKey)
    }

    static func fileFingerprint(url: URL) -> String? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        guard let size = values?.fileSize else { return nil }
        let modified = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        return "file:\(size):\(modified)"
    }

    private func uploadPublicImage(file: URL) async throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw ArtworkError.unreadable
        }
        if data.count > Self.maxBytes {
            throw ArtworkError.tooLarge
        }
        if data.isEmpty {
            throw ArtworkError.unreadable
        }

        let filename = sanitizedFilename(for: file)
        let mime = mimeType(for: file)
        var lastDetail = "Every image host refused the file."

        for host in ImageHost.allCases {
            guard data.count <= host.maxBytes else { continue }
            let status: Int
            let body: String
            do {
                (status, body) = try await postFile(to: host, filename: filename, mime: mime, data: data)
            } catch {
                lastDetail = error.localizedDescription
                continue
            }
            guard let url = host.parse(body) else {
                lastDetail = hostDetail(status: status, body: body)
                continue
            }
            if await check(url, expectedBytes: data.count) == .broken {
                lastDetail = "The host accepted the file but served an empty or different file."
                continue
            }
            return url
        }
        throw ArtworkError.host(lastDetail)
    }

    enum LinkCheck: Equatable {
        case ok
        /// The host answered, and the file is missing, empty, or a different size.
        case broken
        /// No clear answer, such as a timeout. The link is kept rather than uploading again.
        case unknown
    }

    /// Fetches one byte. HEAD is not used because some hosts answer it with 404 for files that exist.
    func check(_ link: String, expectedBytes: Int?) async -> LinkCheck {
        guard let url = URL(string: link) else { return .broken }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            return .unknown
        }
        switch http.statusCode {
        case 206:
            let range = http.value(forHTTPHeaderField: "Content-Range") ?? ""
            guard let total = range.split(separator: "/").last.flatMap({ Int($0) }) else {
                return data.isEmpty ? .broken : .ok
            }
            if total == 0 { return .broken }
            if let expectedBytes, total != expectedBytes { return .broken }
            return .ok
        case 200..<300:
            // The host ignored the range and sent the whole file.
            if data.isEmpty { return .broken }
            if let expectedBytes, data.count != expectedBytes { return .broken }
            return .ok
        case 404, 410:
            return .broken
        default:
            return .unknown
        }
    }

    private func postFile(
        to host: ImageHost,
        filename: String,
        mime: String,
        data: Data
    ) async throws -> (Int, String) {
        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: host.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = multipartBody(
            boundary: boundary,
            fields: host.fields,
            fileField: host.fileField,
            filename: filename,
            mime: mime,
            data: data
        )

        let (responseData, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (status, body)
    }

    private func multipartBody(
        boundary: String,
        fields: [(String, String)],
        fileField: String,
        filename: String,
        mime: String,
        data: Data
    ) -> Data {
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        for (name, value) in fields {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mime)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// Returns Discord's `mp:external/...` path, or nil so the caller can send the https URL itself.
    private func registerExternalAsset(applicationID: String, url: String) async -> String? {
        guard let endpoint = URL(string: "https://discord.com/api/v9/applications/\(applicationID)/external-assets") else {
            return nil
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["urls": [url]])

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            return nil
        }
        return Self.externalAssetPath(in: data)
    }

    static func externalAssetPath(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let array = json as? [[String: Any]], let path = string(array.first?["external_asset_path"]) {
            return path
        }
        if let object = json as? [String: Any] {
            if let path = string(object["external_asset_path"]) {
                return path
            }
            if let array = object["assets"] as? [[String: Any]], let path = string(array.first?["external_asset_path"]) {
                return path
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String, !value.isEmpty else { return nil }
        return value
    }

    private static func httpsURL(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https" else {
            return nil
        }
        return trimmed
    }

    private static func piximgURL(in text: String) -> String? {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return httpsURL(in: text)
        }
        if let url = string(json["direct_url"]), URL(string: url)?.scheme?.lowercased() == "https" {
            return url
        }
        if let images = json["images"] as? [[String: Any]],
           let url = string(images.first?["direct_url"]),
           URL(string: url)?.scheme?.lowercased() == "https" {
            return url
        }
        return nil
    }

    private func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    private func sanitizedFilename(for file: URL) -> String {
        let ext = file.pathExtension.lowercased()
        let safeExt = ["png", "jpg", "jpeg", "webp", "gif"].contains(ext) ? ext : "png"
        let raw = file.lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        let filtered = raw.unicodeScalars.map { allowed.contains($0) ? Character($0) : Character("_") }
        let name = String(filtered)
        if name.isEmpty || name == "." || name.hasPrefix(".") {
            return "artwork.\(safeExt)"
        }
        return name
    }

    private func hostDetail(status: Int, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 180 || trimmed.lowercased().contains("<html") {
            return "The host returned status \(status)."
        }
        return trimmed
    }

    /// Public image hosts Discord can fetch, fastest and most reliable first.
    /// Litterbox is last because its links expire after 72 hours.
    private enum ImageHost: CaseIterable {
        case piximg
        case catbox
        case x0
        case litterbox

        var endpoint: URL {
            switch self {
            case .catbox:
                return URL(string: "https://catbox.moe/user/api.php")!
            case .litterbox:
                return URL(string: "https://litterbox.catbox.moe/resources/internals/api.php")!
            case .x0:
                return URL(string: "https://x0.at")!
            case .piximg:
                return URL(string: "https://pixi.mg/api")!
            }
        }

        var fields: [(String, String)] {
            switch self {
            case .catbox:
                return [("reqtype", "fileupload")]
            case .litterbox:
                return [("reqtype", "fileupload"), ("time", "72h")]
            case .x0, .piximg:
                return []
            }
        }

        var fileField: String {
            switch self {
            case .catbox, .litterbox:
                return "fileToUpload"
            case .x0, .piximg:
                return "file"
            }
        }

        var maxBytes: Int {
            switch self {
            case .piximg:
                return 2 * 1024 * 1024
            default:
                return ArtworkPublisher.maxBytes
            }
        }

        func parse(_ body: String) -> String? {
            switch self {
            case .catbox, .litterbox, .x0:
                return ArtworkPublisher.httpsURL(in: body)
            case .piximg:
                return ArtworkPublisher.piximgURL(in: body)
            }
        }
    }
}

/// Transparent artwork sent when a profile has no large image.
///
/// Discord otherwise draws the application icon in that slot.
enum BlankImage {
    static func pngData() -> Data {
        let side = 512
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: side,
            pixelsHigh: side,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: side * 4,
            bitsPerPixel: 32
        ) else {
            return Data()
        }
        if let pixels = rep.bitmapData {
            pixels.initialize(repeating: 0, count: side * side * 4)
        }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}
