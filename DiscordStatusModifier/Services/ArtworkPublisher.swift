import Foundation

enum ArtworkError: LocalizedError {
    case missingFile
    case unreadable
    case tooLarge
    case catbox(String)

    var errorDescription: String? {
        switch self {
        case .missingFile:
            return "The artwork file is missing. Edit the profile and choose the image again."
        case .unreadable:
            return "Couldn’t read that image."
        case .tooLarge:
            return "That image is larger than 50 MB. Choose a smaller file."
        case .catbox(let detail):
            return "Couldn’t upload artwork to catbox.moe. \(detail)"
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

    var fingerprint: String {
        switch self {
        case .file(let url):
            return ArtworkPublisher.fileFingerprint(url: url) ?? url.path
        case .remote(let url):
            return "url:\(url.absoluteString)"
        }
    }
}

/// Uploads local images to catbox.moe, then registers the public URL with Discord external assets.
struct ArtworkPublisher {
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
        if let cache, cache.fingerprint == fingerprint, cache.publicURL.hasPrefix("https://") {
            publicURL = cache.publicURL
        } else {
            switch source {
            case .file(let url):
                publicURL = try await uploadToCatbox(file: url)
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

    private func uploadToCatbox(file: URL) async throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            throw ArtworkError.unreadable
        }
        if data.count > 50 * 1024 * 1024 {
            throw ArtworkError.tooLarge
        }
        if data.isEmpty {
            throw ArtworkError.unreadable
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: URL(string: "https://catbox.moe/user/api.php")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("DiscordStatusModifier/1.0 (Macintosh)", forHTTPHeaderField: "User-Agent")

        let filename = file.lastPathComponent.isEmpty ? "artwork" : file.lastPathComponent
        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"reqtype\"\r\n\r\n")
        append("fileupload\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"fileToUpload\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType(for: file))\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body

        let responseData: Data
        let response: URLResponse
        do {
            (responseData, response) = try await session.data(for: request)
        } catch {
            throw ArtworkError.catbox(error.localizedDescription)
        }

        let text = String(data: responseData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status),
              let url = URL(string: text),
              url.scheme?.lowercased() == "https" else {
            throw ArtworkError.catbox(catboxDetail(status: status, body: text))
        }
        return text
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
        request.setValue("DiscordStatusModifier/1.0 (Macintosh)", forHTTPHeaderField: "User-Agent")
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

    private func mimeType(for file: URL) -> String {
        switch file.pathExtension.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "gif": return "image/gif"
        default: return "application/octet-stream"
        }
    }

    private func catboxDetail(status: Int, body: String) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.count > 180 || trimmed.lowercased().contains("<html") {
            return "The host returned status \(status)."
        }
        return trimmed
    }
}
