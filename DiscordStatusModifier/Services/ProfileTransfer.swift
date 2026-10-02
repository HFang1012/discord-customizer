import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// A shareable activity card (`.dscard`), which is a JSON document.
    static let discordStatusCard = UTType(
        exportedAs: "com.discordstatus.modifier.card",
        conformingTo: .json
    )
}

enum ProfileTransferError: LocalizedError {
    case unreadable
    case notACard
    case newerVersion
    case destinationIsFile
    case emptyFolder

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "Couldn’t read that file."
        case .notACard:
            return "This file isn’t a Discord activity card."
        case .newerVersion:
            return "This card file is from a newer version of Discord Status Modifier."
        case .destinationIsFile:
            return "That name is already a file. Choose a folder name."
        case .emptyFolder:
            return "That folder doesn’t contain any activity cards."
        }
    }
}

/// Encodes one activity card as a `.dscard` file and rebuilds a new profile from one.
enum ProfileTransfer {
    static let format = "discord-status-card"
    static let version = 1

    static func exportFile(for profile: StatusProfile, store: ProfileStore) throws -> (data: Data, filename: String) {
        var shared = stripped(profile)
        let large = try embeddedImage(filename: profile.largeImageFilename, store: store)
        let small = try embeddedImage(filename: profile.smallImageFilename, store: store)
        if large != nil {
            shared.largeImageRemoteURL = ""
        }
        if small != nil {
            shared.smallImageRemoteURL = ""
        }
        let document = SharedCardFile(
            format: format,
            version: version,
            profile: shared,
            largeImage: large,
            smallImage: small
        )
        let data = try encoder().encode(document)
        return (data, suggestedFilename(for: profile))
    }

    static func importProfile(from data: Data, store: ProfileStore) throws -> StatusProfile {
        let header: CardHeader
        do {
            header = try decoder().decode(CardHeader.self, from: data)
        } catch {
            throw ProfileTransferError.notACard
        }
        guard header.format == format, header.version >= 1 else {
            throw ProfileTransferError.notACard
        }
        guard header.version <= version else {
            throw ProfileTransferError.newerVersion
        }

        let document: SharedCardFile
        do {
            document = try decoder().decode(SharedCardFile.self, from: data)
        } catch {
            throw ProfileTransferError.notACard
        }

        var profile = stripped(document.profile)
        let now = Date()
        profile.id = UUID()
        profile.partyID = UUID().uuidString.lowercased()
        profile.createdAt = now
        profile.updatedAt = now

        let partyEnabled = profile.partyCurrent != nil && profile.partyMax != nil
        let partyCurrent = profile.partyCurrent ?? 1
        let partyMax = max(profile.partyMax ?? partyCurrent, partyCurrent)
        switch profile.preparedForSave(
            partyEnabled: partyEnabled,
            partyCurrent: partyCurrent,
            partyMax: partyMax
        ) {
        case .failure(let error):
            throw error
        case .success(let prepared):
            profile = prepared
        }

        var written: [String] = []
        do {
            if let large = document.largeImage {
                let filename = try store.storeArtwork(
                    data: large.bytes,
                    fileExtension: large.fileExtension,
                    profileID: profile.id,
                    slot: .large
                )
                written.append(filename)
                profile.largeImageFilename = filename
                profile.largeImageRemoteURL = ""
            }
            if let small = document.smallImage {
                let filename = try store.storeArtwork(
                    data: small.bytes,
                    fileExtension: small.fileExtension,
                    profileID: profile.id,
                    slot: .small
                )
                written.append(filename)
                profile.smallImageFilename = filename
                profile.smallImageRemoteURL = ""
            }
        } catch {
            for filename in written {
                store.deleteArtwork(filename: filename)
            }
            throw error
        }
        return profile
    }

    /// `.dscard` and `.json` files in `folder`, plus the same files one folder down.
    static func cardFiles(in folder: URL) -> [URL] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        for entry in entries {
            let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDirectory {
                guard let nested = try? manager.contentsOfDirectory(
                    at: entry,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }
                files.append(contentsOf: nested.filter(isCardFile))
            } else if isCardFile(entry) {
                files.append(entry)
            }
        }
        return files.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
    }

    static func suggestedFilename(for profile: StatusProfile) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let scalars = profile.listTitle.unicodeScalars.map { scalar -> Character in
            if illegal.contains(scalar) || scalar.value < 32 {
                return "-"
            }
            return Character(scalar)
        }
        let trimmed = String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "profile" : trimmed
        return String(base.prefix(80)) + ".dscard"
    }

    private static func isCardFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory == true { return false }
        let ext = url.pathExtension.lowercased()
        return ext == "dscard" || ext == "json"
    }

    private static func embeddedImage(filename: String?, store: ProfileStore) throws -> EmbeddedImage? {
        guard let artwork = try store.readArtwork(filename: filename) else { return nil }
        return EmbeddedImage(fileExtension: artwork.fileExtension, bytes: artwork.data)
    }

    private static func stripped(_ profile: StatusProfile) -> StatusProfile {
        var copy = profile
        copy.largeImageFilename = nil
        copy.smallImageFilename = nil
        copy.largeFingerprint = nil
        copy.largePublicURL = nil
        copy.largeAssetKey = nil
        copy.smallFingerprint = nil
        copy.smallPublicURL = nil
        copy.smallAssetKey = nil
        return copy
    }

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

private struct CardHeader: Decodable {
    var format: String
    var version: Int
}

private struct SharedCardFile: Codable {
    var format: String
    var version: Int
    var profile: StatusProfile
    var largeImage: EmbeddedImage?
    var smallImage: EmbeddedImage?
}

private struct EmbeddedImage: Codable {
    var fileExtension: String
    var bytes: Data

    enum CodingKeys: String, CodingKey {
        case fileExtension = "extension"
        case bytes
    }
}
