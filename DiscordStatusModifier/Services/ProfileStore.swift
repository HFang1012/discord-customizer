import Foundation

enum ArtworkSlot: String {
    case large
    case small
}

enum StoreError: LocalizedError {
    case writeFailed(String)
    case unreadableImage
    case unsupportedImage

    var errorDescription: String? {
        switch self {
        case .writeFailed(let detail):
            return "Couldn’t save profiles on this Mac. \(detail)"
        case .unreadableImage:
            return "Couldn’t read that image."
        case .unsupportedImage:
            return "Use a PNG, JPEG, WebP, or GIF."
        }
    }
}

/// Profiles and copied artwork live in Application Support as JSON plus image files.
final class ProfileStore {
    let root: URL
    private let profilesURL: URL
    private let artworkDirectory: URL
    private let stagingDirectory: URL
    private let previewDirectory: URL
    private(set) var loadWarning: String?

    init() {
        let fileManager = FileManager.default
        let base = (try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        root = base.appendingPathComponent("DiscordStatusModifier", isDirectory: true)
        profilesURL = root.appendingPathComponent("profiles.json")
        artworkDirectory = root.appendingPathComponent("artwork", isDirectory: true)
        stagingDirectory = root.appendingPathComponent("staging", isDirectory: true)
        previewDirectory = root.appendingPathComponent("previews", isDirectory: true)
        for directory in [root, artworkDirectory, stagingDirectory, previewDirectory] {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        cleanStaging()
    }

    func load() -> [StatusProfile] {
        guard FileManager.default.fileExists(atPath: profilesURL.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: profilesURL)
            return try Self.decoder().decode(ProfileDocument.self, from: data).profiles
        } catch {
            let backup = root.appendingPathComponent("profiles.json.bad")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: profilesURL, to: backup)
            loadWarning = "The saved profile library couldn’t be read, so it was set aside as profiles.json.bad. You can start fresh."
            return []
        }
    }

    func save(_ profiles: [StatusProfile]) throws {
        let document = ProfileDocument(version: 1, profiles: profiles)
        let data = try Self.encoder().encode(document)
        do {
            try data.write(to: profilesURL, options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
    }

    /// Stable transparent PNG used when a profile has no large image.
    func blankArtworkURL() throws -> URL {
        let url = artworkDirectory.appendingPathComponent("blank.png")
        if FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let data = BlankImage.pngData()
        guard !data.isEmpty else {
            throw StoreError.writeFailed("Couldn’t build the blank image.")
        }
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
        return url
    }

    func artworkURL(filename: String?) -> URL? {
        guard let filename, !filename.isEmpty else { return nil }
        let url = artworkDirectory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func stageCopy(of source: URL) throws -> URL {
        let ext = try validatedExtension(for: source)
        let destination = stagingDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    func commitArtwork(from staged: URL, profileID: UUID, slot: ArtworkSlot) throws -> String {
        let ext = try validatedExtension(for: staged)
        let filename = "\(profileID.uuidString)-\(slot.rawValue).\(ext)"
        let destination = artworkDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: staged, to: destination)
        return filename
    }

    func duplicateArtwork(named filename: String, profileID: UUID, slot: ArtworkSlot) -> String? {
        let source = artworkDirectory.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: source.path) else { return nil }
        let ext = source.pathExtension.isEmpty ? "img" : source.pathExtension
        let copyName = "\(profileID.uuidString)-\(slot.rawValue).\(ext)"
        let destination = artworkDirectory.appendingPathComponent(copyName)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
            return copyName
        } catch {
            return nil
        }
    }

    func deleteArtwork(filename: String?) {
        guard let url = artworkURL(filename: filename) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Reads a stored artwork file for a shareable card. A missing filename means this slot has no local image.
    func readArtwork(filename: String?) throws -> (data: Data, fileExtension: String)? {
        guard let filename, !filename.isEmpty else { return nil }
        guard let url = artworkURL(filename: filename) else {
            throw ArtworkError.missingFile
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw ArtworkError.unreadable
        }
        try validateArtworkData(data)
        return (data, try normalizedExtension(url.pathExtension))
    }

    /// Copies imported artwork into this Mac’s artwork folder and returns the stored filename.
    func storeArtwork(data: Data, fileExtension: String, profileID: UUID, slot: ArtworkSlot) throws -> String {
        try validateArtworkData(data)
        let ext = try normalizedExtension(fileExtension)
        let filename = "\(profileID.uuidString)-\(slot.rawValue).\(ext)"
        let destination = artworkDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        do {
            try data.write(to: destination, options: .atomic)
        } catch {
            throw StoreError.writeFailed(error.localizedDescription)
        }
        return filename
    }

    func discard(_ url: URL?) {
        guard let url else { return }
        let standard = url.standardizedFileURL
        let staging = stagingDirectory.standardizedFileURL
        guard standard.path.hasPrefix(staging.path) else { return }
        try? FileManager.default.removeItem(at: standard)
    }

    func previewFile(forRemoteURL remote: String) -> URL? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let url = previewDirectory.appendingPathComponent(previewFilename(for: trimmed))
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func storePreview(data: Data, forRemoteURL remote: String) -> URL? {
        let url = previewDirectory.appendingPathComponent(previewFilename(for: remote))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    private func previewFilename(for remote: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in remote.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let ext = URL(string: remote)?.pathExtension.lowercased() ?? ""
        let safe = Self.allowedExtensions.contains(ext) ? ext : "img"
        return "\(String(hash, radix: 16)).\(safe)"
    }

    private func cleanStaging() {
        let fileManager = FileManager.default
        guard let urls = try? fileManager.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return
        }
        let cutoff = Date().addingTimeInterval(-86_400)
        for url in urls {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func validatedExtension(for url: URL) throws -> String {
        try normalizedExtension(url.pathExtension)
    }

    private func normalizedExtension(_ raw: String) throws -> String {
        let ext = raw.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            throw StoreError.unsupportedImage
        }
        return ext == "jpeg" ? "jpg" : ext
    }

    private func validateArtworkData(_ data: Data) throws {
        if data.isEmpty {
            throw StoreError.unreadableImage
        }
        if data.count > Self.maxArtworkBytes {
            throw ArtworkError.tooLarge
        }
    }

    private static let maxArtworkBytes = 50 * 1024 * 1024
    private static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif"]

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct ProfileDocument: Codable {
    var version: Int
    var profiles: [StatusProfile]
}
