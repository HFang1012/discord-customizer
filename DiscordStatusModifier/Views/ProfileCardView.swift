import SwiftUI

struct ProfileCardView: View {
    var profile: StatusProfile
    var artwork: CardArtwork
    var timer: TimerDisplay
    var isLive: Bool
    var isPublishing: Bool
    var publishingLabel: String
    var statusNote: String?
    var showsMenu: Bool
    var isInteractive: Bool
    var onSelect: () -> Void
    var onEdit: () -> Void
    var onDuplicate: () -> Void
    var onDelete: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            cardButton
            if showsMenu {
                overflowMenu
                    .padding(.top, 8)
                    .padding(.trailing, 8)
            }
        }
        .background(DiscordTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .compositingGroup()
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isLive ? DiscordTheme.accent : Color.white.opacity(0.06), lineWidth: isLive ? 2 : 1)
        )
        .shadow(color: isLive ? DiscordTheme.accent.opacity(0.28) : .clear, radius: 10, y: 0)
        .overlay {
            if isPublishing {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                    .allowsHitTesting(false)
                VStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(publishingLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var cardButton: some View {
        Button(action: {
            guard isInteractive else { return }
            onSelect()
        }) {
            cardBody
        }
        .buttonStyle(.plain)
        .disabled(!isInteractive)
        .accessibilityAddTraits(isLive ? .isSelected : [])
        .accessibilityLabel("\(profile.activityType.label), \(profile.listTitle)")
        .accessibilityHint(isLive ? "Stops this status" : "Sets this status live")
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.activityType.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DiscordTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsMenu ? 28 : 0)

            HStack(alignment: .top, spacing: 12) {
                artworkStack
                VStack(alignment: .leading, spacing: 3) {
                    Text(DiscordFormatting.attributed(
                        profile.titleSource.isEmpty ? "Untitled" : profile.titleSource,
                        size: 16,
                        weight: .bold,
                        color: .white
                    ))
                        .lineLimit(2)
                    if !DiscordFormatting.plain(profile.details).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(DiscordFormatting.attributed(
                            profile.details,
                            size: 13,
                            weight: .regular,
                            color: DiscordTheme.secondary
                        ))
                            .lineLimit(1)
                    }
                    if !DiscordFormatting.plain(profile.state).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(DiscordFormatting.attributed(
                            profile.state,
                            size: 13,
                            weight: .regular,
                            color: DiscordTheme.secondary
                        ))
                            .lineLimit(1)
                    }
                    if timer != .hidden {
                        PresenceTimer(display: timer)
                    }
                    if let statusNote {
                        Text(statusNote)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DiscordTheme.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            let buttons = profile.visibleButtons
            if !buttons.isEmpty {
                VStack(spacing: 6) {
                    ForEach(Array(buttons.prefix(2))) { button in
                        Text(DiscordFormatting.attributed(
                            button.label,
                            size: 14,
                            weight: .medium,
                            color: .white
                        ))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(DiscordTheme.button)
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var artworkStack: some View {
        ZStack(alignment: .bottomTrailing) {
            ArtworkImage(local: artwork.largeLocal, remote: artwork.largeRemote, cornerRadius: 12)
                .frame(width: 72, height: 72)
                .clipped()
                .help(DiscordFormatting.plain(profile.largeImageText))
            if hasSmallArtwork {
                ArtworkImage(
                    local: artwork.smallLocal,
                    remote: artwork.smallRemote,
                    cornerRadius: 6,
                    clipsAsCircle: true
                )
                .frame(width: 24, height: 24)
                .clipped()
                .overlay(Circle().stroke(DiscordTheme.card, lineWidth: 3))
                .offset(x: 6, y: 6)
                .help(DiscordFormatting.plain(profile.smallImageText))
            }
        }
        .frame(width: 78, height: 78, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    private var hasSmallArtwork: Bool {
        artwork.smallLocal != nil || artwork.smallRemote != nil
    }

    private var overflowMenu: some View {
        Menu {
            Button("Edit", action: onEdit)
            Button("Duplicate", action: onDuplicate)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DiscordTheme.secondary)
                .frame(width: 28, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Edit, duplicate, or delete")
        .accessibilityLabel("Actions for \(profile.listTitle)")
    }
}
