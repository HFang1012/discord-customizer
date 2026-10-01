import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                topBar
                if let banner = model.banner {
                    bannerView(banner)
                }
                Group {
                    if model.profiles.isEmpty {
                        emptyState
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
        .sheet(item: $model.editor) { session in
            ProfileEditorView(session: session)
                .environmentObject(model)
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
            .disabled(model.activeProfileID == nil)
            .help("Clear the Discord status")
        }
    }

    private func bannerView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DiscordTheme.danger)
            Text(message)
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
        .background(DiscordTheme.dangerFill)
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
            Text("Create a card for what you’re doing — a project, a playlist, a match. Pick it when Discord is open and the status shows on your profile.")
                .font(.system(size: 14))
                .foregroundStyle(DiscordTheme.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
            Button("New profile") {
                model.beginNewProfile()
            }
            .buttonStyle(.borderedProminent)
            .tint(DiscordTheme.accent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profileGrid: some View {
        let revision = model.previewRevision
        return ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 320, maximum: 460), spacing: 16)],
                spacing: 16
            ) {
                ForEach(model.profiles) { profile in
                    ProfileCardView(
                        profile: profile,
                        artwork: model.artwork(for: profile),
                        timer: model.timerDisplay(for: profile, previewAnchor: nil),
                        isLive: model.activeProfileID == profile.id,
                        isPublishing: model.publishingProfileID == profile.id,
                        publishingLabel: model.publishingLabel,
                        statusNote: model.statusNote(for: profile),
                        showsMenu: true,
                        isInteractive: true,
                        onSelect: { model.select(profile) },
                        onEdit: { model.beginEdit(profile) },
                        onDuplicate: { model.duplicate(profile) },
                        onDelete: { model.pendingDelete = profile }
                    )
                    .id("\(profile.id.uuidString)-\(revision)")
                }
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
    }
}
