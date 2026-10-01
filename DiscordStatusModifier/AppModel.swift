import Combine
import Foundation

enum ConnectionPhase: Equatable {
    case searching
    case connected(DiscordUser)
    case waiting(String)
}

enum ApplySource {
    case user
    case reconnect
}

final class EditorSession: ObservableObject, Identifiable {
    let id = UUID()
    let isNew: Bool
    let openedAt = Date()
    let originalLargeFilename: String?
    let originalSmallFilename: String?

    @Published var draft: StatusProfile
    @Published var largeStaged: URL?
    @Published var smallStaged: URL?
    @Published var largeCleared: Bool
    @Published var smallCleared: Bool
    @Published var partyEnabled: Bool
    @Published var partyCurrent: Int
    @Published var partyMax: Int
    @Published var validation: String?

    init(profile: StatusProfile, isNew: Bool) {
        var copy = profile
        while copy.buttons.count < 2 {
            copy.buttons.append(ProfileButton(id: UUID(), label: "", url: ""))
        }
        if copy.buttons.count > 2 {
            copy.buttons = Array(copy.buttons.prefix(2))
        }
        self.draft = copy
        self.isNew = isNew
        self.originalLargeFilename = profile.largeImageFilename
        self.originalSmallFilename = profile.smallImageFilename
        self.largeCleared = false
        self.smallCleared = false
        let current = profile.partyCurrent
        let maxSize = profile.partyMax
        self.partyEnabled = current != nil && maxSize != nil
        let resolvedCurrent = current ?? 1
        self.partyCurrent = resolvedCurrent
        self.partyMax = Swift.max(maxSize ?? 5, resolvedCurrent)
    }

    func applyStaged(_ url: URL, slot: ArtworkSlot) {
        switch slot {
        case .large:
            largeStaged = url
            largeCleared = false
            draft.largeImageRemoteURL = ""
        case .small:
            smallStaged = url
            smallCleared = false
            draft.smallImageRemoteURL = ""
        }
        validation = nil
    }

    func clearImage(_ slot: ArtworkSlot) {
        switch slot {
        case .large:
            largeStaged = nil
            largeCleared = true
            draft.largeImageRemoteURL = ""
            draft.largeImageFilename = nil
            draft.largeImageText = ""
            draft.largeImageURL = ""
        case .small:
            smallStaged = nil
            smallCleared = true
            draft.smallImageRemoteURL = ""
            draft.smallImageFilename = nil
            draft.smallImageText = ""
            draft.smallImageURL = ""
        }
    }
}

struct StatusBanner: Equatable {
    var message: String
    var isSuccess: Bool

    static func error(_ message: String) -> StatusBanner {
        StatusBanner(message: message, isSuccess: false)
    }

    static func success(_ message: String) -> StatusBanner {
        StatusBanner(message: message, isSuccess: true)
    }
}

@MainActor
final class AppModel: ObservableObject {
    static var shared: AppModel?

    @Published var profiles: [StatusProfile] = []
    @Published var activeProfileID: UUID?
    @Published var connection: ConnectionPhase = .searching
    @Published var banner: StatusBanner?
    @Published var publishingProfileID: UUID?
    @Published var publishingLabel = "Setting status…"
    @Published var editor: EditorSession?
    @Published var pendingDelete: StatusProfile?
    @Published private(set) var previewRevision = 0

    let store: ProfileStore
    let ipc: DiscordIPCClient
    private let publisher = ArtworkPublisher()
    private let defaults = UserDefaults.standard
    private var anchorProfileID: UUID?
    private var countUpAnchor: Date?
    private var countDownAnchor: Date?
    private var didApplyThisConnection = false
    private var sendTask: Task<Void, Never>?
    private var sendGeneration = 0
    private var idleClearTask: Task<Void, Never>?
    private var previewTasks = Set<String>()

    private enum Keys {
        static let activeProfileID = "activeProfileID"
        static let legacyApplicationID = "discordApplicationID"
        static let blankFingerprint = "blankImageFingerprint"
        static let blankPublicURL = "blankImagePublicURL"
        static let blankAssetKey = "blankImageAssetKey"
    }

    init() {
        store = ProfileStore()
        ipc = DiscordIPCClient()
        profiles = store.load()
        if let warning = store.loadWarning {
            banner = .error(warning)
        }
        defaults.removeObject(forKey: Keys.legacyApplicationID)
        if let raw = defaults.string(forKey: Keys.activeProfileID),
           let id = UUID(uuidString: raw),
           profiles.contains(where: { $0.id == id }) {
            activeProfileID = id
        }
        AppModel.shared = self
        let client = ipc
        ipc.eventHandler = { event in
            Task { @MainActor in
                AppModel.shared?.handle(event)
            }
        }
        AppDelegate.onWillTerminate = {
            client.shutdownClearingActivity()
        }
        ipc.setClientID(DiscordClientConfiguration.applicationID)
        startIdleActivityClear()
        Task { @MainActor [weak self] in
            self?.refreshRemotePreviews()
        }
    }

    var connectionTitle: String {
        switch connection {
        case .searching:
            return "Looking for Discord…"
        case .connected(let user):
            return "Connected as \(user.displayName)"
        case .waiting:
            return "Open Discord and sign in"
        }
    }

    var connectionSubtitle: String {
        switch connection {
        case .searching:
            return "Rich Presence only works while the Discord desktop app is running."
        case .connected:
            return "Rich Presence is connected."
        case .waiting(let detail):
            if detail.localizedCaseInsensitiveContains("application id") {
                return "Discord rejected the connection. Try restarting Discord."
            }
            return "Rich Presence only works while the Discord desktop app is running."
        }
    }

    var connectedUser: DiscordUser? {
        if case .connected(let user) = connection { return user }
        return nil
    }

    func statusNote(for profile: StatusProfile) -> String? {
        guard activeProfileID == profile.id, publishingProfileID != profile.id else { return nil }
        if case .connected = connection { return nil }
        return "Waiting for Discord"
    }

    func artwork(for profile: StatusProfile) -> CardArtwork {
        let large = resolvedArtwork(
            filename: profile.largeImageFilename,
            remote: profile.largeImageRemoteURL,
            staged: nil,
            cleared: false
        )
        let small = resolvedArtwork(
            filename: profile.smallImageFilename,
            remote: profile.smallImageRemoteURL,
            staged: nil,
            cleared: false
        )
        return CardArtwork(
            largeLocal: large.local,
            smallLocal: small.local,
            largeRemote: large.remote,
            smallRemote: small.remote
        )
    }

    func editorArtwork(for session: EditorSession) -> CardArtwork {
        let large = resolvedArtwork(
            filename: session.draft.largeImageFilename,
            remote: session.draft.largeImageRemoteURL,
            staged: session.largeStaged,
            cleared: session.largeCleared
        )
        let small = resolvedArtwork(
            filename: session.draft.smallImageFilename,
            remote: session.draft.smallImageRemoteURL,
            staged: session.smallStaged,
            cleared: session.smallCleared
        )
        return CardArtwork(
            largeLocal: large.local,
            smallLocal: small.local,
            largeRemote: large.remote,
            smallRemote: small.remote
        )
    }

    func timerDisplay(for profile: StatusProfile, previewAnchor: Date?) -> TimerDisplay {
        switch profile.timerMode {
        case .off:
            return .hidden
        case .countUpFromApply:
            if profile.id == activeProfileID, anchorProfileID == profile.id, let start = countUpAnchor {
                return .countUp(from: start)
            }
            if let previewAnchor {
                return .countUp(from: previewAnchor)
            }
            return .fixed(0)
        case .countUpFromStart:
            guard let start = profile.timerStart else { return .hidden }
            return .countUp(from: start)
        case .countDownDuration:
            if profile.id == activeProfileID, anchorProfileID == profile.id, let end = countDownAnchor {
                return .countDown(to: end)
            }
            if let previewAnchor {
                return .countDown(to: previewAnchor.addingTimeInterval(profile.countdownDuration))
            }
            return .fixed(profile.countdownDuration)
        case .countDownUntil:
            guard let end = profile.timerEnd else { return .hidden }
            return .countDown(to: end)
        case .custom:
            if profile.id == activeProfileID, anchorProfileID == profile.id, let end = countDownAnchor {
                return .countDown(to: end)
            }
            return .fixed(profile.customDuration)
        }
    }

    func setCustomTimer(profileID: UUID, hours: Int, minutes: Int, seconds: Int) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        let hours = min(999, max(0, hours))
        let minutes = min(59, max(0, minutes))
        let seconds = min(59, max(0, seconds))
        guard profiles[index].customHours != hours
            || profiles[index].customMinutes != minutes
            || profiles[index].customSeconds != seconds else { return }
        profiles[index].customHours = hours
        profiles[index].customMinutes = minutes
        profiles[index].customSeconds = seconds
        profiles[index].updatedAt = Date()
        persistProfiles()
        guard activeProfileID == profileID else { return }
        resetAnchors(for: profiles[index])
        didApplyThisConnection = false
        startSend(source: .user, replaceExisting: false)
    }

    func beginNewProfile() {
        editor = EditorSession(profile: .makeNew(), isNew: true)
    }

    func beginEdit(_ profile: StatusProfile) {
        editor = EditorSession(profile: profile, isNew: false)
        schedulePreview(profile.largeImageRemoteURL)
        schedulePreview(profile.smallImageRemoteURL)
    }

    func stageImage(from url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        return try store.stageCopy(of: url)
    }

    func discardStaged(_ url: URL?) {
        store.discard(url)
    }

    func save(session: EditorSession) {
        session.validation = nil
        switch session.draft.preparedForSave(
            partyEnabled: session.partyEnabled,
            partyCurrent: session.partyCurrent,
            partyMax: session.partyMax
        ) {
        case .failure(let error):
            session.validation = error.localizedDescription
        case .success(var profile):
            do {
                try applyArtworkSlot(
                    staged: session.largeStaged,
                    cleared: session.largeCleared,
                    originalFilename: session.originalLargeFilename,
                    filename: &profile.largeImageFilename,
                    remote: &profile.largeImageRemoteURL,
                    fingerprint: &profile.largeFingerprint,
                    publicURL: &profile.largePublicURL,
                    assetKey: &profile.largeAssetKey,
                    profileID: profile.id,
                    slot: .large
                )
                try applyArtworkSlot(
                    staged: session.smallStaged,
                    cleared: session.smallCleared,
                    originalFilename: session.originalSmallFilename,
                    filename: &profile.smallImageFilename,
                    remote: &profile.smallImageRemoteURL,
                    fingerprint: &profile.smallFingerprint,
                    publicURL: &profile.smallPublicURL,
                    assetKey: &profile.smallAssetKey,
                    profileID: profile.id,
                    slot: .small
                )
                upsert(profile)
                store.discard(session.largeStaged)
                store.discard(session.smallStaged)
                session.largeStaged = nil
                session.smallStaged = nil
                editor = nil
                schedulePreview(profile.largeImageRemoteURL)
                schedulePreview(profile.smallImageRemoteURL)
                if activeProfileID == profile.id {
                    resetAnchors(for: profile)
                    didApplyThisConnection = false
                    startSend(source: .user, replaceExisting: true)
                }
            } catch {
                session.validation = error.localizedDescription
            }
        }
    }

    func select(_ profile: StatusProfile) {
        if activeProfileID == profile.id {
            stop()
            return
        }
        // Drop the previous card’s spinner immediately so the new selection feels instant.
        publishingProfileID = nil
        banner = nil
        activeProfileID = profile.id
        persistActive()
        resetAnchors(for: profile)
        didApplyThisConnection = false
        startSend(source: .user, replaceExisting: true)
    }

    func stop() {
        sendGeneration += 1
        let generation = sendGeneration
        sendTask?.cancel()
        publishingProfileID = nil
        let hadActive = activeProfileID != nil
        activeProfileID = nil
        anchorProfileID = nil
        countUpAnchor = nil
        countDownAnchor = nil
        didApplyThisConnection = true
        persistActive()
        banner = nil
        guard hadActive else { return }
        Task {
            // Bail if the user already picked another profile after Stop.
            guard generation == sendGeneration else { return }
            guard case .connected = connection else { return }
            do {
                try await ipc.clearActivity()
            } catch {
                guard generation == sendGeneration, case .connected = connection else { return }
                if let ipcError = error as? IPCError, case .notConnected = ipcError {
                    return
                }
                if error is CancellationError { return }
                banner = .error(error.localizedDescription)
            }
        }
    }

    func downloadFile(for profile: StatusProfile) throws -> (data: Data, filename: String) {
        try ProfileTransfer.exportFile(for: profile, store: store)
    }

    func uploadCard(from url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let profile = try ProfileTransfer.importProfile(from: data, store: store)
            profiles.insert(profile, at: 0)
            banner = .success("Added “\(profile.listTitle)”.")
            persistProfiles()
            schedulePreview(profile.largeImageRemoteURL)
            schedulePreview(profile.smallImageRemoteURL)
        } catch {
            banner = .error(error.localizedDescription)
        }
    }

    func duplicate(_ profile: StatusProfile) {
        var copy = profile
        copy.id = UUID()
        copy.partyID = UUID().uuidString.lowercased()
        copy.title = duplicatedTitle(from: profile.title)
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copyArtwork(from: profile.largeImageFilename, profileID: copy.id, slot: .large, into: &copy)
        copyArtwork(from: profile.smallImageFilename, profileID: copy.id, slot: .small, into: &copy)
        profiles.insert(copy, at: 0)
        persistProfiles()
    }

    func confirmDelete() {
        guard let profile = pendingDelete else { return }
        pendingDelete = nil
        if activeProfileID == profile.id {
            stop()
        }
        store.deleteArtwork(filename: profile.largeImageFilename)
        store.deleteArtwork(filename: profile.smallImageFilename)
        profiles.removeAll { $0.id == profile.id }
        persistProfiles()
    }

    func schedulePreview(_ remote: String) {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard LinkValidation.httpsURL(trimmed) != nil else { return }
        guard store.previewFile(forRemoteURL: trimmed) == nil else { return }
        guard previewTasks.insert(trimmed).inserted else { return }
        Task {
            defer { previewTasks.remove(trimmed) }
            guard let url = URL(string: trimmed) else { return }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  !data.isEmpty,
                  data.count <= 50 * 1024 * 1024 else {
                return
            }
            if store.storePreview(data: data, forRemoteURL: trimmed) != nil {
                previewRevision += 1
            }
        }
    }

    private func handle(_ event: IPCEvent) {
        switch event {
        case .idle:
            didApplyThisConnection = false
            connection = .waiting("Open Discord and sign in")
        case .searching:
            if connectedUser == nil {
                connection = .searching
            }
        case .connected(let user):
            let becameConnected = connectedUser == nil
            connection = .connected(user)
            if becameConnected {
                didApplyThisConnection = false
                reapplyIfNeeded()
            }
        case .disconnected(let message):
            didApplyThisConnection = false
            connection = .waiting(message)
        case .activityError(let message):
            banner = .error(message)
        }
    }

    private func reapplyIfNeeded() {
        guard !didApplyThisConnection,
              let id = activeProfileID,
              profiles.contains(where: { $0.id == id }) else {
            return
        }
        if let profile = profiles.first(where: { $0.id == id }) {
            ensureAnchors(for: profile)
        }
        startSend(source: .reconnect, replaceExisting: false)
    }

    private func startSend(source: ApplySource, replaceExisting: Bool) {
        sendTask?.cancel()
        sendGeneration += 1
        let generation = sendGeneration
        sendTask = Task { [weak self] in
            await self?.performSend(
                generation: generation,
                source: source,
                replaceExisting: replaceExisting
            )
        }
    }

    private func performSend(generation: Int, source: ApplySource, replaceExisting: Bool) async {
        guard generation == sendGeneration, !Task.isCancelled else { return }
        guard let profileID = activeProfileID,
              let profile = profiles.first(where: { $0.id == profileID }) else {
            return
        }
        guard case .connected = connection else {
            if source == .user {
                banner = .error("Open Discord and sign in on this Mac. “\(profile.listTitle)” will apply when Discord is connected.")
            }
            return
        }

        let hasUserLarge = profile.largeImageFilename != nil
            || !profile.largeImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let needsArtwork = hasUserLarge
            || profile.smallImageFilename != nil
            || !profile.smallImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let blankReady = defaults.string(forKey: Keys.blankPublicURL)?.hasPrefix("https://") == true
        let needsBlankUpload = !hasUserLarge && !blankReady
        publishingProfileID = profileID
        publishingLabel = (needsArtwork || needsBlankUpload) ? "Uploading artwork…" : "Setting status…"
        defer {
            if publishingProfileID == profileID {
                publishingProfileID = nil
            }
        }

        do {
            let large = try await imageKey(for: profile, slot: .large)
            guard generation == sendGeneration, !Task.isCancelled else { return }
            let latestForSmall = profiles.first(where: { $0.id == profileID }) ?? profile
            let small = try await imageKey(for: latestForSmall, slot: .small)
            guard generation == sendGeneration, !Task.isCancelled else { return }
            let current = profiles.first(where: { $0.id == profileID }) ?? profile
            ensureAnchors(for: current)
            let activity = ActivityBuilder.makeActivity(
                profile: current,
                largeImage: large,
                smallImage: small,
                countUpStart: countUpAnchor,
                countDownEnd: countDownAnchor
            )
            // A fresh activity makes Discord keep a timer, so timer-off profiles update in place
            // and leave timestamps out of the payload.
            let clearForSwitch = replaceExisting && current.timerMode != .off
            if clearForSwitch {
                try await ipc.clearActivity()
                guard generation == sendGeneration, !Task.isCancelled else { return }
            }
            let sentBlankLarge = current.largeImageFilename == nil
                && LinkValidation.httpsURL(current.largeImageRemoteURL) == nil
            var confirmed = try await ipc.setActivity(activity)
            guard generation == sendGeneration else {
                if activeProfileID == nil {
                    try? await ipc.clearActivity()
                }
                return
            }
            if ActivityConfirmation.problem(sent: activity, confirmed: confirmed, ignoreMissingLargeImage: sentBlankLarge) != nil {
                confirmed = try await ipc.setActivity(activity)
                guard generation == sendGeneration else {
                    if activeProfileID == nil {
                        try? await ipc.clearActivity()
                    }
                    return
                }
                if let still = ActivityConfirmation.problem(sent: activity, confirmed: confirmed, ignoreMissingLargeImage: sentBlankLarge) {
                    banner = .error(still)
                    didApplyThisConnection = false
                    return
                }
            }
            didApplyThisConnection = true
            banner = nil
        } catch is CancellationError {
            return
        } catch {
            guard generation == sendGeneration else { return }
            banner = .error(error.localizedDescription)
            let rejected: Bool
            if let ipcError = error as? IPCError, case .discord = ipcError {
                rejected = true
            } else {
                rejected = false
            }
            if source == .user || rejected {
                if activeProfileID == profileID {
                    activeProfileID = nil
                    didApplyThisConnection = true
                    persistActive()
                }
            }
        }
    }

    private func imageKey(for profile: StatusProfile, slot: ArtworkSlot) async throws -> String? {
        let filename = slot == .large ? profile.largeImageFilename : profile.smallImageFilename
        let remote = slot == .large ? profile.largeImageRemoteURL : profile.smallImageRemoteURL
        let cache = storedCache(profile: profile, slot: slot)

        if let filename {
            guard let fileURL = store.artworkURL(filename: filename) else {
                throw ArtworkError.missingFile
            }
            let published = try await publisher.publish(
                source: .file(fileURL),
                cache: cache
            )
            remember(published, profileID: profile.id, slot: slot)
            return published.assetKey
        }

        if let url = LinkValidation.httpsURL(remote) {
            let published = try await publisher.publish(
                source: .remote(url),
                cache: cache
            )
            remember(published, profileID: profile.id, slot: slot)
            return published.assetKey
        }
        // Discord draws the application icon when large_image is omitted. Send a blank image instead.
        if slot == .large {
            return try await blankImageKey()
        }
        return nil
    }

    private func blankImageKey() async throws -> String {
        let url = try store.blankArtworkURL()
        let fingerprint = ArtworkPublisher.fileFingerprint(url: url) ?? url.path
        let cache: PublishedArtwork?
        if defaults.string(forKey: Keys.blankFingerprint) == fingerprint,
           let publicURL = defaults.string(forKey: Keys.blankPublicURL),
           let assetKey = defaults.string(forKey: Keys.blankAssetKey),
           publicURL.hasPrefix("https://"), !assetKey.isEmpty {
            cache = PublishedArtwork(fingerprint: fingerprint, publicURL: publicURL, assetKey: assetKey)
        } else {
            cache = nil
        }
        let published = try await publisher.publish(source: .file(url), cache: cache)
        defaults.set(published.fingerprint, forKey: Keys.blankFingerprint)
        defaults.set(published.publicURL, forKey: Keys.blankPublicURL)
        defaults.set(published.assetKey, forKey: Keys.blankAssetKey)
        return published.assetKey
    }

    private func storedCache(profile: StatusProfile, slot: ArtworkSlot) -> PublishedArtwork? {
        switch slot {
        case .large:
            guard let fingerprint = profile.largeFingerprint,
                  let publicURL = profile.largePublicURL,
                  let assetKey = profile.largeAssetKey else { return nil }
            return PublishedArtwork(fingerprint: fingerprint, publicURL: publicURL, assetKey: assetKey)
        case .small:
            guard let fingerprint = profile.smallFingerprint,
                  let publicURL = profile.smallPublicURL,
                  let assetKey = profile.smallAssetKey else { return nil }
            return PublishedArtwork(fingerprint: fingerprint, publicURL: publicURL, assetKey: assetKey)
        }
    }

    private func remember(_ published: PublishedArtwork, profileID: UUID, slot: ArtworkSlot) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        switch slot {
        case .large:
            profiles[index].largeFingerprint = published.fingerprint
            profiles[index].largePublicURL = published.publicURL
            profiles[index].largeAssetKey = published.assetKey
        case .small:
            profiles[index].smallFingerprint = published.fingerprint
            profiles[index].smallPublicURL = published.publicURL
            profiles[index].smallAssetKey = published.assetKey
        }
        persistProfiles()
    }

    private func applyArtworkSlot(
        staged: URL?,
        cleared: Bool,
        originalFilename: String?,
        filename: inout String?,
        remote: inout String,
        fingerprint: inout String?,
        publicURL: inout String?,
        assetKey: inout String?,
        profileID: UUID,
        slot: ArtworkSlot
    ) throws {
        if let staged {
            let committed = try store.commitArtwork(from: staged, profileID: profileID, slot: slot)
            if let originalFilename, originalFilename != committed {
                store.deleteArtwork(filename: originalFilename)
            }
            filename = committed
            remote = ""
            fingerprint = nil
            publicURL = nil
            assetKey = nil
            return
        }
        if cleared {
            store.deleteArtwork(filename: originalFilename)
            filename = nil
            fingerprint = nil
            publicURL = nil
            assetKey = nil
        }
    }

    private func copyArtwork(
        from filename: String?,
        profileID: UUID,
        slot: ArtworkSlot,
        into copy: inout StatusProfile
    ) {
        guard let filename else { return }
        guard let copiedName = store.duplicateArtwork(named: filename, profileID: profileID, slot: slot),
              let url = store.artworkURL(filename: copiedName) else {
            clearCache(slot, on: &copy)
            return
        }
        switch slot {
        case .large:
            copy.largeImageFilename = copiedName
            if let fingerprint = ArtworkPublisher.fileFingerprint(url: url) {
                copy.largeFingerprint = fingerprint
            }
        case .small:
            copy.smallImageFilename = copiedName
            if let fingerprint = ArtworkPublisher.fileFingerprint(url: url) {
                copy.smallFingerprint = fingerprint
            }
        }
    }

    private func clearCache(_ slot: ArtworkSlot, on profile: inout StatusProfile) {
        switch slot {
        case .large:
            profile.largeImageFilename = nil
            profile.largeFingerprint = nil
            profile.largePublicURL = nil
            profile.largeAssetKey = nil
        case .small:
            profile.smallImageFilename = nil
            profile.smallFingerprint = nil
            profile.smallPublicURL = nil
            profile.smallAssetKey = nil
        }
    }

    private func resolvedArtwork(
        filename: String?,
        remote: String,
        staged: URL?,
        cleared: Bool
    ) -> (local: URL?, remote: URL?) {
        if let staged {
            return (staged, nil)
        }
        if !cleared, let local = store.artworkURL(filename: filename) {
            return (local, nil)
        }
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        if let remoteURL = LinkValidation.httpsURL(trimmed) {
            return (store.previewFile(forRemoteURL: trimmed), remoteURL)
        }
        return (nil, nil)
    }

    private func resetAnchors(for profile: StatusProfile, now: Date = Date()) {
        anchorProfileID = profile.id
        countUpAnchor = now
        if profile.timerMode == .custom {
            countDownAnchor = now.addingTimeInterval(profile.customDuration)
        } else {
            countDownAnchor = now.addingTimeInterval(profile.countdownDuration)
        }
    }

    private func ensureAnchors(for profile: StatusProfile, now: Date = Date()) {
        if anchorProfileID != profile.id || countUpAnchor == nil || countDownAnchor == nil {
            resetAnchors(for: profile, now: now)
        }
    }

    private func upsert(_ profile: StatusProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.insert(profile, at: 0)
        }
        persistProfiles()
    }

    private func persistProfiles() {
        do {
            try store.save(profiles)
        } catch {
            banner = .error(error.localizedDescription)
        }
    }

    private func persistActive() {
        if let activeProfileID {
            defaults.set(activeProfileID.uuidString, forKey: Keys.activeProfileID)
        } else {
            defaults.removeObject(forKey: Keys.activeProfileID)
        }
    }

    private func startIdleActivityClear() {
        idleClearTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                await self?.clearActivityIfIdle()
            }
        }
    }

    /// If no profile is selected, clear Discord so a leftover activity does not stay up.
    private func clearActivityIfIdle() async {
        guard activeProfileID == nil else { return }
        guard case .connected = connection else { return }
        let generation = sendGeneration
        do {
            try await ipc.clearActivity()
        } catch {
            return
        }
        guard generation != sendGeneration, activeProfileID != nil else { return }
        startSend(source: .reconnect, replaceExisting: true)
    }

    private func refreshRemotePreviews() {
        for profile in profiles {
            schedulePreview(profile.largeImageRemoteURL)
            schedulePreview(profile.smallImageRemoteURL)
        }
    }

    private func duplicatedTitle(from title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let stem = trimmed.isEmpty ? "Untitled" : trimmed
        let suffix = " copy"
        if stem.count + suffix.count <= ProfileLimits.title {
            return stem + suffix
        }
        return String(stem.prefix(ProfileLimits.title - suffix.count)) + suffix
    }
}

struct CardArtwork: Equatable {
    var largeLocal: URL?
    var smallLocal: URL?
    var largeRemote: URL?
    var smallRemote: URL?
}
