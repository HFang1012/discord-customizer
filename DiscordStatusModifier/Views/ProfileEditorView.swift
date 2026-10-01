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

            section("Artwork", footnote: "Uploaded artwork is posted to a public host so Discord can fetch it, including GIFs. Anyone with the link can open the file. A pasted https link skips the upload and is sent to Discord directly. Nothing is uploaded until this profile is set live.") {
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

            section("Timer", footnote: "Count up shows elapsed time. An end time counts down. The green timer looks like 1:26:34.") {
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

            section("Party", footnote: "Optional. Discord shows the current size and the max, for example 1 of 4.") {
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

            if let validation = session.validation {
                Text(validation)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DiscordTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var previewColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DiscordTheme.muted)
            ProfileCardView(
                profile: session.draft,
                artwork: model.editorArtwork(for: session),
                timer: model.timerDisplay(for: session.draft, previewAnchor: session.openedAt),
                isLive: model.activeProfileID == session.draft.id,
                isPublishing: false,
                publishingLabel: "",
                statusNote: nil,
                showsMenu: false,
                isInteractive: false,
                onSelect: {},
                onEdit: {},
                onDuplicate: {},
                onDelete: {}
            )
            .id(model.previewRevision)
            Text("The preview uses the image on this Mac. Discord receives it only after you set the profile live.")
                .font(.system(size: 12))
                .foregroundStyle(DiscordTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Beside your name in the member list: \(session.draft.statusDisplayType.label).")
                .font(.system(size: 12))
                .foregroundStyle(DiscordTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
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
            DatePicker(
                "Start",
                selection: Binding(
                    get: { session.draft.timerStart ?? Date() },
                    set: { session.draft.timerStart = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
            )
        case .countDownDuration:
            Stepper(value: $session.draft.countdownHours, in: 0...48) {
                Text("Hours: \(session.draft.countdownHours)")
                    .foregroundStyle(.white)
            }
            Stepper(value: $session.draft.countdownMinutes, in: 0...59) {
                Text("Minutes: \(session.draft.countdownMinutes)")
                    .foregroundStyle(.white)
            }
            Stepper(value: $session.draft.countdownSeconds, in: 0...59) {
                Text("Seconds: \(session.draft.countdownSeconds)")
                    .foregroundStyle(.white)
            }
        case .countDownUntil:
            DatePicker(
                "End",
                selection: Binding(
                    get: { session.draft.timerEnd ?? Date().addingTimeInterval(3600) },
                    set: { session.draft.timerEnd = $0 }
                ),
                displayedComponents: [.date, .hourAndMinute]
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
                    .frame(width: 64, height: 64)
                    .clipped()
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("PNG, JPEG, WebP, or GIF. Drop a file here or paste an https link.")
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

    private func section<Content: View>(_ title: String, footnote: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text(footnote)
                .font(.system(size: 12))
                .foregroundStyle(DiscordTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
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
            session.applyStaged(staged, slot: slot)
        } catch {
            session.validation = error.localizedDescription
        }
    }

    private func handleDrop(_ providers: [NSItemProvider], slot: ArtworkSlot) -> Bool {
        guard let provider = providers.first else { return false }
        let store = model.store
        let editorSession = session
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object as? URL else { return }
                stageIncomingFile(at: url, store: store, session: editorSession, slot: slot)
            }
            return true
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                guard let url else { return }
                stageIncomingFile(at: url, store: store, session: editorSession, slot: slot)
            }
            return true
        }
        return false
    }

    private func save() {
        model.save(session: session)
    }

    private func cancel() {
        model.discardStaged(session.largeStaged)
        model.discardStaged(session.smallStaged)
        session.largeStaged = nil
        session.smallStaged = nil
        model.editor = nil
        dismiss()
    }
}

private func stageIncomingFile(at url: URL, store: ProfileStore, session: EditorSession, slot: ArtworkSlot) {
    let accessed = url.startAccessingSecurityScopedResource()
    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
    do {
        let staged = try store.stageCopy(of: url)
        DispatchQueue.main.async {
            session.applyStaged(staged, slot: slot)
        }
    } catch {
        let message = error.localizedDescription
        DispatchQueue.main.async {
            session.validation = message
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
