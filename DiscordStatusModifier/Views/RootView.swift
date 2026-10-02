import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var exporterPresented = false
    @State private var uploadDelegate = UploadPanelDelegate()
    @State private var exportDocument: ActivityCardDocument?
    @State private var exportFilename = "profile"
    @State private var libraryFilter: LibraryFilter = .all
    @State private var restingFrames: [UUID: CGRect] = [:]
    @State private var dragID: UUID?
    @State private var dragTranslation: CGSize = .zero
    @State private var dragOrder: [UUID] = []
    @State private var isSettling = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                filterBar
                if let banner = model.banner {
                    bannerView(banner)
                }
                Group {
                    if model.profiles.isEmpty {
                        emptyState
                    } else if filteredProfiles.isEmpty {
                        filteredEmptyState
                    } else {
                        profileGrid
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DiscordTheme.background)
            .navigationTitle("Discord Status Modifier")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        downloadFull()
                    } label: {
                        Label("Download full", systemImage: "folder")
                    }
                    .disabled(model.profiles.isEmpty)
                    .help("Save every profile into a folder")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        presentUpload()
                    } label: {
                        Label("Upload", systemImage: "square.and.arrow.up")
                    }
                    .help("Upload a profile file or a folder of profiles")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.beginNewProfile()
                    } label: {
                        Label("New profile", systemImage: "plus")
                    }
                    .help("New profile")
                }
            }
            .toolbarBackground(DiscordTheme.background, for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
        }
        .preferredColorScheme(.dark)
        .tint(DiscordTheme.accent)
        .frame(minWidth: 560, minHeight: 520)
        .overlay(alignment: .bottomTrailing) {
            Text("© 2026 hucklberi & automagicle")
                .font(.system(size: 9))
                .foregroundStyle(DiscordTheme.muted.opacity(0.4))
                .padding(.trailing, 16)
                .padding(.bottom, 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .sheet(item: $model.editor) { session in
            ProfileEditorView(session: session)
                .environmentObject(model)
        }
        .fileExporter(
            isPresented: $exporterPresented,
            document: exportDocument,
            contentType: .discordStatusCard,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success(let url):
                model.banner = .success("Saved “\(url.lastPathComponent)”.")
            case .failure(let error):
                if !isCancellation(error) {
                    model.banner = .error(error.localizedDescription)
                }
            }
        }
        .confirmationDialog(
            "Delete this profile?",
            isPresented: Binding(
                get: { model.pendingDelete != nil },
                set: { if !$0 { model.pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                model.confirmDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let profile = model.pendingDelete {
                Text("“\(profile.listTitle)” is removed from this Mac. Discord itself is left alone.")
            }
        }
        .onAppear {
            AppDelegate.onReopen = {
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    private var topBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) {
                connectionCluster
                Spacer(minLength: 12)
                controlButtons
            }
            VStack(alignment: .leading, spacing: 12) {
                connectionCluster
                controlButtons
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(DiscordTheme.elevated)
    }

    private var filterBar: some View {
        HStack(spacing: 6) {
            ForEach(LibraryFilter.allCases) { filter in
                let isSelected = libraryFilter == filter
                Button {
                    libraryFilter = filter
                    cancelDrag()
                } label: {
                    Text(filter.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.white : DiscordTheme.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background {
                            Capsule(style: .continuous)
                                .fill(isSelected ? DiscordTheme.accent : Color.white.opacity(0.06))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DiscordTheme.elevated)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
        }
    }

    private var filteredProfiles: [StatusProfile] {
        guard let type = libraryFilter.activityType else { return model.profiles }
        return model.profiles.filter { $0.activityType == type }
    }

    private var connectionCluster: some View {
        HStack(spacing: 10) {
            connectionAvatar
            VStack(alignment: .leading, spacing: 2) {
                Text(model.connectionTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(model.connectionSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(DiscordTheme.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var connectionAvatar: some View {
        if let user = model.connectedUser {
            AsyncImage(url: user.avatarURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(DiscordTheme.muted)
                        .padding(4)
                }
            }
            .frame(width: 36, height: 36)
            .background(Circle().fill(Color.white.opacity(0.06)))
            .clipShape(Circle())
            .accessibilityLabel("Avatar for \(user.displayName)")
        } else {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                Image(systemName: connectionSymbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DiscordTheme.secondary)
            }
            .frame(width: 36, height: 36)
        }
    }

    private var connectionSymbol: String {
        switch model.connection {
        case .searching:
            return "arrow.triangle.2.circlepath"
        case .connected:
            return "person.crop.circle.fill"
        case .waiting:
            return "exclamationmark"
        }
    }

    private var controlButtons: some View {
        HStack(spacing: 8) {
            Button("Stop") {
                model.stop()
            }
            .buttonStyle(.bordered)
            .disabled(model.activeProfileIDs.isEmpty)
            .help("Clear every live status")
        }
    }

    private func bannerView(_ banner: StatusBanner) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: banner.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(banner.isSuccess ? DiscordTheme.timer : DiscordTheme.danger)
            Text(banner.message)
                .font(.system(size: 13))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                model.banner = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(DiscordTheme.secondary)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(banner.isSuccess ? DiscordTheme.timer.opacity(0.18) : DiscordTheme.dangerFill)
        .accessibilityElement(children: .combine)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(DiscordTheme.muted)
            Text("No profiles yet")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Create a card for what you’re doing — a project, a playlist, a match. Pick one or more when Discord is open and they show on your profile.")
                .font(.system(size: 14))
                .foregroundStyle(DiscordTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            HStack(spacing: 8) {
                Button("New profile") {
                    model.beginNewProfile()
                }
                .buttonStyle(.borderedProminent)
                .tint(DiscordTheme.accent)
                Button("Upload profile") {
                    presentUpload()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: 10) {
            Text("No \(libraryFilter.title.lowercased()) profiles")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
            Text("Cards set to \(libraryFilter.title) show up here.")
                .font(.system(size: 14))
                .foregroundStyle(DiscordTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileGrid: some View {
        let revision = model.previewRevision
        let visibleIDs = filteredProfiles.map(\.id)
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 16)],
                spacing: 16
            ) {
                ForEach(filteredProfiles) { profile in
                    let artwork = model.artwork(for: profile)
                    profileCard(profile, isInteractive: true) { value in
                        handleDragChanged(value, profileID: profile.id)
                    } onDragEnded: { _ in
                        guard dragID == profile.id else { return }
                        finishDrag()
                    }
                    .id("\(profile.id.uuidString)-\(revision)-\(artworkDisplayID(local: artwork.largeLocal, remote: artwork.largeRemote))-\(artworkDisplayID(local: artwork.smallLocal, remote: artwork.smallRemote))")
                    .background {
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: CardFramePreference.self,
                                value: [profile.id: geo.frame(in: .named(ProfileGridCoordinate.name))]
                            )
                        }
                    }
                    .opacity(dragID == profile.id ? 0 : 1)
                    .offset(cardOffset(for: profile.id, layoutIDs: visibleIDs))
                    .animation(dragID == profile.id ? nil : .spring(response: 0.28, dampingFraction: 0.84), value: dragOrder)
                }
            }
            .coordinateSpace(name: ProfileGridCoordinate.name)
            .onPreferenceChange(CardFramePreference.self) { frames in
                guard dragID == nil else { return }
                restingFrames = frames
            }
            .overlay(alignment: .topLeading) {
                dragLayer(layoutIDs: visibleIDs)
            }
            .padding(20)
            .animation(dragID == nil && !isSettling ? .easeInOut(duration: 0.18) : nil, value: visibleIDs)
        }
        .scrollContentBackground(.hidden)
    }

    private func dragLayer(layoutIDs: [UUID]) -> some View {
        ZStack(alignment: .topLeading) {
            if let gap = gapFrame(layoutIDs: layoutIDs) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                    .frame(width: gap.width, height: gap.height)
                    .offset(x: gap.minX, y: gap.minY)
                    .animation(.spring(response: 0.28, dampingFraction: 0.84), value: dragOrder)
            }
            if let dragID,
               let profile = model.profiles.first(where: { $0.id == dragID }),
               let home = restingFrames[dragID] {
                profileCard(profile, isInteractive: false)
                    .frame(width: home.width, height: home.height)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                    .offset(x: home.minX + dragTranslation.width, y: home.minY + dragTranslation.height)
            }
        }
        .allowsHitTesting(false)
    }

    private func profileCard(
        _ profile: StatusProfile,
        isInteractive: Bool,
        onDragChanged: ((DragGesture.Value) -> Void)? = nil,
        onDragEnded: ((DragGesture.Value) -> Void)? = nil
    ) -> some View {
        let artwork = model.artwork(for: profile)
        return ProfileCardView(
            profile: profile,
            artwork: artwork,
            timer: model.timerDisplay(for: profile, previewAnchor: nil),
            isLive: model.isLive(profile.id),
            isPublishing: model.isPublishing(profile.id),
            publishingLabel: model.publishingLabel(for: profile.id),
            statusNote: model.statusNote(for: profile),
            showsMenu: true,
            isInteractive: isInteractive,
            onSelect: { model.select(profile) },
            onEdit: { model.beginEdit(profile) },
            onDuplicate: { model.duplicate(profile) },
            onDownload: { download(profile) },
            onDownloadFull: { downloadFull() },
            onDelete: { model.pendingDelete = profile },
            onCustomTimer: { hours, minutes, seconds in
                model.setCustomTimer(profileID: profile.id, hours: hours, minutes: minutes, seconds: seconds)
            },
            onDragChanged: onDragChanged,
            onDragEnded: onDragEnded
        )
    }

    private func cardOffset(for id: UUID, layoutIDs: [UUID]) -> CGSize {
        guard dragID != nil, id != dragID,
              let homeIndex = layoutIDs.firstIndex(of: id),
              let visualIndex = dragOrder.firstIndex(of: id),
              let home = restingFrames[layoutIDs[homeIndex]],
              let slot = restingFrames[layoutIDs[visualIndex]] else {
            return .zero
        }
        return CGSize(width: slot.minX - home.minX, height: slot.minY - home.minY)
    }

    private func gapFrame(layoutIDs: [UUID]) -> CGRect? {
        guard let dragID, let index = dragOrder.firstIndex(of: dragID), layoutIDs.indices.contains(index) else {
            return nil
        }
        return restingFrames[layoutIDs[index]]
    }

    private func handleDragChanged(_ value: DragGesture.Value, profileID: UUID) {
        guard !isSettling, restingFrames[profileID] != nil else { return }
        if dragID == nil {
            dragID = profileID
            dragOrder = filteredProfiles.map(\.id)
        }
        guard dragID == profileID, let home = restingFrames[profileID] else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragTranslation = value.translation
        }
        let center = CGPoint(
            x: home.midX + value.translation.width,
            y: home.midY + value.translation.height
        )
        updateDragOrder(center: center)
    }

    private func updateDragOrder(center: CGPoint) {
        guard let dragID else { return }
        let layoutIDs = filteredProfiles.map(\.id)
        guard !layoutIDs.isEmpty, dragOrder.count == layoutIDs.count else { return }
        var bestIndex = dragOrder.firstIndex(of: dragID) ?? 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for index in layoutIDs.indices {
            guard let slot = restingFrames[layoutIDs[index]] else { continue }
            let dx = slot.midX - center.x
            let dy = slot.midY - center.y
            let distance = (dx * dx) + (dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        guard dragOrder[bestIndex] != dragID, let from = dragOrder.firstIndex(of: dragID) else { return }
        var order = dragOrder
        order.remove(at: from)
        order.insert(dragID, at: bestIndex)
        dragOrder = order
    }

    private func finishDrag() {
        guard let dragID, !isSettling else { return }
        let layoutIDs = filteredProfiles.map(\.id)
        let order = dragOrder
        let settle: CGSize
        if let home = restingFrames[dragID],
           let index = order.firstIndex(of: dragID),
           layoutIDs.indices.contains(index),
           let target = restingFrames[layoutIDs[index]] {
            settle = CGSize(width: target.minX - home.minX, height: target.minY - home.minY)
        } else {
            settle = .zero
        }
        isSettling = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.86), completionCriteria: .logicallyComplete) {
            dragTranslation = settle
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if !order.isEmpty {
                    model.applyVisibleOrder(order)
                }
                self.dragID = nil
                self.dragTranslation = .zero
                self.dragOrder = []
                self.isSettling = false
            }
        }
    }

    private func cancelDrag() {
        guard !isSettling else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragID = nil
            dragTranslation = .zero
            dragOrder = []
        }
    }

    private func presentUpload() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Upload"
        panel.message = "Choose a profile file or a folder of profiles."
        panel.delegate = uploadDelegate
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.uploadCard(from: url)
        }
    }

    private func downloadFull() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Discord Profiles"
        panel.prompt = "Save"
        panel.message = "Saves every profile into this folder."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let count = try model.exportLibrary(to: url)
                let word = count == 1 ? "profile" : "profiles"
                model.banner = .success("Saved \(count) \(word) to “\(url.lastPathComponent)”.")
            } catch {
                model.banner = .error(error.localizedDescription)
            }
        }
    }

    private func download(_ profile: StatusProfile) {
        do {
            let file = try model.downloadFile(for: profile)
            exportDocument = ActivityCardDocument(data: file.data)
            exportFilename = file.filename
            exporterPresented = true
        } catch {
            model.banner = .error(error.localizedDescription)
        }
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let ns = error as NSError
        return ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError
    }
}

private final class UploadPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return false
        }
        if isDirectory.boolValue { return true }
        let ext = url.pathExtension.lowercased()
        return ext == "dscard" || ext == "json"
    }
}

enum ProfileGridCoordinate {
    static let name = "profileGrid"
}

private struct CardFramePreference: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private enum LibraryFilter: String, CaseIterable, Identifiable {
    case all
    case watching
    case listening
    case playing
    case competing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .watching: return "Watching"
        case .listening: return "Listening"
        case .playing: return "Playing"
        case .competing: return "Competing"
        }
    }

    var activityType: ActivityType? {
        switch self {
        case .all: return nil
        case .watching: return .watching
        case .listening: return .listening
        case .playing: return .playing
        case .competing: return .competing
        }
    }
}

struct ActivityCardDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.discordStatusCard] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw ProfileTransferError.unreadable
        }
        self.data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
