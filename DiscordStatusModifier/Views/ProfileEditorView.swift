import SwiftUI
import UniformTypeIdentifiers

struct ProfileEditorView: View {
    @ObservedObject var session: EditorSession
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var importing: ArtworkSlot?
    @State private var importerPresented = false
    @State private var largeTargeted = false
    @State private var smallTargeted = false
    @State private var pendingCrop: PendingCrop?

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Group {
                    if geometry.size.width < 760 {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 24) {
                                previewColumn
                                form
                            }
                            .padding(20)
                        }
                    } else {
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                form
                                    .padding(20)
                            }
                            Divider().overlay(Color.white.opacity(0.06))
                            ScrollView {
                                previewColumn
                                    .padding(20)
                            }
                            .frame(width: 400)
                            .background(DiscordTheme.elevated.opacity(0.65))
                        }
                    }
                }
            }
            .background(DiscordTheme.background)
            .navigationTitle(session.isNew ? "New profile" : "Edit profile")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 680, minHeight: 560)
        .preferredColorScheme(.dark)
        .tint(DiscordTheme.accent)
        .fileImporter(
            isPresented: $importerPresented,
            allowedContentTypes: [.png, .jpeg, .webP, .gif],
            allowsMultipleSelection: false
        ) { result in
            guard let slot = importing else { return }
            importing = nil
            switch result {
            case .failure:
                session.validation = "Couldn’t read that file."
            case .success(let urls):
                guard let url = urls.first else { return }
                acceptFile(url, slot: slot)
            }
        }
        .sheet(item: $pendingCrop) { pending in
            SquareCropSheet(sourceURL: pending.url) { data, fileExtension in
                commitCrop(pending, data: data, fileExtension: fileExtension)
            } onCancel: {
                model.discardStaged(pending.url)
                pendingCrop = nil
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 22) {
            section("Activity", footnote: "The title is the bold line. Details and state are the two gray lines under it. Formatting: **bold**, *italic* or _italic_, ***both***, __underline__, ~~strike~~, `code`, ||spoiler||. A backslash escapes the next character.") {
                LimitedField(title: "Title", prompt: "homework", text: $session.draft.title, limit: ProfileLimits.title)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Type")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DiscordTheme.secondary)
                    Picker("Type", selection: $session.draft.activityType) {
                        ForEach(ActivityType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Sets the word above the title.")
                        .font(.system(size: 12))
                        .foregroundStyle(DiscordTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                LimitedField(title: "Details", prompt: "Chapter 4, problem set", text: $session.draft.details, limit: ProfileLimits.line)
                LimitedField(title: "Details link", prompt: "https://", text: $session.draft.detailsURL, limit: ProfileLimits.url)
                LimitedField(title: "State", prompt: "Almost done", text: $session.draft.state, limit: ProfileLimits.line)
                LimitedField(title: "State link", prompt: "https://", text: $session.draft.stateURL, limit: ProfileLimits.url)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Text beside your name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DiscordTheme.secondary)
                    Picker("Text beside your name", selection: $session.draft.statusDisplayType) {
                        ForEach(StatusDisplayType.allCases) { type in
                            Text(type.label).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("Chooses what shows next to your name in the member list: the title, the details line, or the state line.")
                        .font(.system(size: 12))
                        .foregroundStyle(DiscordTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            section("Artwork", footnote: "Uploaded artwork is posted to a public host so Discord can fetch it, including GIFs. Anyone with the link can open the file. A pasted https link skips the upload and is sent to Discord directly. Nothing is uploaded until this profile is set live. An empty large image is sent as a blank image, so Discord does not fill in the application icon.") {
                imageWell(
                    title: "Large image",
                    slot: .large,
                    remote: $session.draft.largeImageRemoteURL,
                    hover: $session.draft.largeImageText,
                    clickURL: $session.draft.largeImageURL,
                    targeted: $largeTargeted
                )
                imageWell(
                    title: "Small image",
                    slot: .small,
                    remote: $session.draft.smallImageRemoteURL,
                    hover: $session.draft.smallImageText,
                    clickURL: $session.draft.smallImageURL,
                    targeted: $smallTargeted
                )
            }
            .onChange(of: session.draft.largeImageRemoteURL) { _, newValue in
                noteRemoteChange(newValue, slot: .large)
            }
            .onChange(of: session.draft.smallImageRemoteURL) { _, newValue in
                noteRemoteChange(newValue, slot: .small)
            }

            section("Buttons", footnote: "Discord only shows buttons to other people, not on your own profile. This preview still shows them. Button labels use the same formatting as the activity lines.") {
                buttonFields(index: 0, title: "First button")
                buttonFields(index: 1, title: "Second button")
            }

            if let validation = session.validation {
                Text(validation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DiscordTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewColumn: some View {
        let artwork = model.editorArtwork(for: session)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DiscordTheme.muted)
            ProfileCardView(
                profile: session.draft,
                artwork: artwork,
                timer: model.timerDisplay(for: session.draft, previewAnchor: session.openedAt),
                isLive: model.isLive(session.draft.id),
                isPublishing: false,
                publishingLabel: "",
                statusNote: nil,
                showsMenu: false,
                isInteractive: false,
                onSelect: {},
                onEdit: {},
                onDuplicate: {},
                onDownload: {},
                onDownloadFull: {},
                onDelete: {},
                onCustomTimer: { hours, minutes, seconds in
                    session.draft.customHours = hours
                    session.draft.customMinutes = minutes
                    session.draft.customSeconds = seconds
                }
            )
            .id(previewCardID(artwork))
            VStack(alignment: .leading, spacing: 22) {
                section("Timer", footnote: "Off shows no timer on Discord. Count up shows elapsed time. An end time counts down. Custom timer can also be typed on the card, like 1:26:34, and Discord counts down from it.") {
                    Picker("Timer", selection: $session.draft.timerMode) {
                        ForEach(TimerMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    timerControls
                }
                .onChange(of: session.draft.timerMode) { _, mode in
                    if mode == .countUpFromStart, session.draft.timerStart == nil {
                        session.draft.timerStart = Date()
                    }
                    if mode == .countDownUntil, session.draft.timerEnd == nil {
                        session.draft.timerEnd = Date().addingTimeInterval(3600)
                    }
                }

                section("Party") {
                    Toggle("Show party size", isOn: $session.partyEnabled)
                        .toggleStyle(.switch)
                    if session.partyEnabled {
                        Stepper(value: $session.partyCurrent, in: 1...999) {
                            Text("Current: \(session.partyCurrent)")
                                .foregroundStyle(.white)
                        }
                        Stepper(value: $session.partyMax, in: 1...999) {
                            Text("Max: \(session.partyMax)")
                                .foregroundStyle(.white)
                        }
                        .onChange(of: session.partyCurrent) { _, value in
                            if session.partyMax < value {
                                session.partyMax = value
                            }
                        }
                        .onChange(of: session.partyMax) { _, value in
                            if session.partyCurrent > value {
                                session.partyCurrent = value
                            }
                        }
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    @ViewBuilder
    private var timerControls: some View {
        switch session.draft.timerMode {
        case .off:
            EmptyView()
        case .countUpFromApply:
            Text("The timer starts when you click the profile, and keeps running if Discord reconnects.")
                .font(.system(size: 12))
                .foregroundStyle(DiscordTheme.muted)
        case .countUpFromStart:
            MomentEditor(
                date: Binding(
                    get: { session.draft.timerStart ?? Date() },
                    set: { session.draft.timerStart = $0 }
                ),
                kind: .start
            )
        case .countDownDuration:
            DurationEditor(
                hours: $session.draft.countdownHours,
                minutes: $session.draft.countdownMinutes,
                seconds: $session.draft.countdownSeconds,
                maxHours: 48
            )
        case .countDownUntil:
            MomentEditor(
                date: Binding(
                    get: { session.draft.timerEnd ?? Date().addingTimeInterval(3600) },
                    set: { session.draft.timerEnd = $0 }
                ),
                kind: .end
            )
        case .custom:
            DurationEditor(
                hours: Binding(get: { session.draft.customHoursValue }, set: { session.draft.customHours = $0 }),
                minutes: Binding(get: { session.draft.customMinutesValue }, set: { session.draft.customMinutes = $0 }),
                seconds: Binding(get: { session.draft.customSecondsValue }, set: { session.draft.customSeconds = $0 }),
                maxHours: 999
            )
        }
    }

    private func imageWell(
        title: String,
        slot: ArtworkSlot,
        remote: Binding<String>,
        hover: Binding<String>,
        clickURL: Binding<String>,
        targeted: Binding<Bool>
    ) -> some View {
        let preview = slot == .large
            ? model.editorArtwork(for: session).largeLocal
            : model.editorArtwork(for: session).smallLocal
        let remotePreview = slot == .large
            ? model.editorArtwork(for: session).largeRemote
            : model.editorArtwork(for: session).smallRemote
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                ArtworkImage(local: preview, remote: remotePreview, cornerRadius: 10)
                    .id(artworkDisplayID(local: preview, remote: remotePreview))
                    .frame(width: 64, height: 64)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("PNG, JPEG, WebP, or GIF. A file is cropped to a square. You can also paste an https link.")
                        .font(.system(size: 12))
                        .foregroundStyle(DiscordTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Choose file") {
                            importing = slot
                            importerPresented = true
                        }
                        Button("Remove") {
                            removeImage(slot)
                        }
                        .disabled(!hasImage(slot))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        targeted.wrappedValue ? DiscordTheme.accent : Color.white.opacity(0.08),
                        style: StrokeStyle(lineWidth: 1, dash: targeted.wrappedValue ? [CGFloat]() : [4, 4])
                    )
            )
            .onDrop(of: [.fileURL, .image], isTargeted: targeted) { providers in
                handleDrop(providers, slot: slot)
            }

            LimitedField(title: "\(title) https link", prompt: "https://", text: remote, limit: ProfileLimits.url)
            LimitedField(title: "Hover text", prompt: "Cover art", text: hover, limit: ProfileLimits.hover)
            LimitedField(title: "Click link", prompt: "https://", text: clickURL, limit: ProfileLimits.url)
        }
    }

    private func buttonFields(index: Int, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            LimitedField(
                title: "Label",
                prompt: index == 0 ? "github code" : "Website",
                text: buttonLabel(index),
                limit: ProfileLimits.buttonLabel
            )
            LimitedField(
                title: "Link",
                prompt: "https://github.com",
                text: buttonURL(index),
                limit: ProfileLimits.url
            )
        }
    }

    private func buttonLabel(_ index: Int) -> Binding<String> {
        Binding(
            get: { session.draft.buttons[index].label },
            set: { session.draft.buttons[index].label = $0 }
        )
    }

    private func buttonURL(_ index: Int) -> Binding<String> {
        Binding(
            get: { session.draft.buttons[index].url },
            set: { session.draft.buttons[index].url = $0 }
        )
    }

    private func section<Content: View>(_ title: String, footnote: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            if let footnote {
                Text(footnote)
                    .font(.system(size: 12))
                    .foregroundStyle(DiscordTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
    }

    private func previewCardID(_ artwork: CardArtwork) -> String {
        [
            String(model.previewRevision),
            artworkDisplayID(local: artwork.largeLocal, remote: artwork.largeRemote),
            artworkDisplayID(local: artwork.smallLocal, remote: artwork.smallRemote)
        ].joined(separator: "|")
    }

    private func hasImage(_ slot: ArtworkSlot) -> Bool {
        switch slot {
        case .large:
            return session.largeStaged != nil
                || (!session.largeCleared && session.originalLargeFilename != nil)
                || !session.draft.largeImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !session.draft.largeImageText.isEmpty
                || !session.draft.largeImageURL.isEmpty
        case .small:
            return session.smallStaged != nil
                || (!session.smallCleared && session.originalSmallFilename != nil)
                || !session.draft.smallImageRemoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !session.draft.smallImageText.isEmpty
                || !session.draft.smallImageURL.isEmpty
        }
    }

    private func removeImage(_ slot: ArtworkSlot) {
        switch slot {
        case .large:
            model.discardStaged(session.largeStaged)
        case .small:
            model.discardStaged(session.smallStaged)
        }
        session.clearImage(slot)
    }

    private func noteRemoteChange(_ value: String, slot: ArtworkSlot) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        switch slot {
        case .large:
            if let staged = session.largeStaged {
                model.discardStaged(staged)
                session.largeStaged = nil
            }
            session.largeCleared = true
        case .small:
            if let staged = session.smallStaged {
                model.discardStaged(staged)
                session.smallStaged = nil
            }
            session.smallCleared = true
        }
        model.schedulePreview(trimmed)
    }

    private func acceptFile(_ url: URL, slot: ArtworkSlot) {
        do {
            let staged = try model.stageImage(from: url)
            presentCrop(url: staged, slot: slot)
        } catch {
            session.validation = error.localizedDescription
        }
    }

    private func presentCrop(url: URL, slot: ArtworkSlot) {
        if let existing = pendingCrop {
            model.discardStaged(existing.url)
        }
        pendingCrop = PendingCrop(url: url, slot: slot)
    }

    private func commitCrop(_ pending: PendingCrop, data: Data, fileExtension: String) {
        do {
            let staged = try model.store.stageData(data, fileExtension: fileExtension)
            model.discardStaged(pending.url)
            session.applyStaged(staged, slot: pending.slot)
            pendingCrop = nil
        } catch {
            session.validation = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], slot: ArtworkSlot) -> Bool {
        guard let provider = providers.first else { return false }
        let store = model.store
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                stageIncomingFile(at: url, store: store, onStaged: { staged in
                    presentCrop(url: staged, slot: slot)
                }, onError: { message in
                    session.validation = message
                })
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { return }
                stageIncomingFile(at: url, store: store, onStaged: { staged in
                    presentCrop(url: staged, slot: slot)
                }, onError: { message in
                    session.validation = message
                })
            }
            return true
        }
        return false
    }

    private func save() {
        model.save(session: session)
    }

    private func cancel() {
        if let pending = pendingCrop {
            model.discardStaged(pending.url)
            pendingCrop = nil
        }
        model.discardStaged(session.largeStaged)
        model.discardStaged(session.smallStaged)
        session.largeStaged = nil
        session.smallStaged = nil
        model.editor = nil
        dismiss()
    }
}

private struct PendingCrop: Identifiable {
    let id = UUID()
    let url: URL
    let slot: ArtworkSlot
}

private func stageIncomingFile(
    at url: URL,
    store: ProfileStore,
    onStaged: @escaping (URL) -> Void,
    onError: @escaping (String) -> Void
) {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
        let staged = try store.stageCopy(of: url)
        DispatchQueue.main.async {
            onStaged(staged)
        }
    } catch {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            onError(message)
        }
    }
}

struct LimitedField: View {
    var title: String
    var prompt: String
    @Binding var text: String
    var limit: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DiscordTheme.secondary)
                Spacer()
                Text("\(text.count)/\(limit)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(text.count >= limit ? DiscordTheme.timer : DiscordTheme.muted)
            }
            TextField("", text: $text, prompt: Text(prompt))
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(DiscordTheme.field)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .accessibilityLabel(title)
                .onChange(of: text) { _, newValue in
                    let cleaned = newValue.replacingOccurrences(of: "\n", with: " ")
                    let next = cleaned.count > limit ? String(cleaned.prefix(limit)) : cleaned
                    if next != newValue {
                        text = next
                    }
                }
        }
    }
}
