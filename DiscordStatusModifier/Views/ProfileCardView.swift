import AppKit
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
    var onDownload: () -> Void
    var onDownloadFull: () -> Void
    var onDelete: () -> Void
    var onCustomTimer: ((Int, Int, Int) -> Void)? = nil
    var onDragChanged: ((DragGesture.Value) -> Void)? = nil
    var onDragEnded: ((DragGesture.Value) -> Void)? = nil

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
        cardControl
            .accessibilityAddTraits(isLive ? .isSelected : [])
            .accessibilityLabel("\(profile.activityType.label), \(profile.listTitle)")
            .accessibilityHint(isInteractive ? (isLive ? "Removes this status. Drag to rearrange." : "Adds this status. Drag to rearrange.") : "")
            .accessibilityAddTraits(isInteractive ? .isButton : [])
    }

    @ViewBuilder
    private var cardControl: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if let onDragChanged, let onDragEnded {
            cardBody
                .contentShape(shape)
                .gesture(reorderGesture(onChanged: onDragChanged, onEnded: onDragEnded))
        } else {
            cardBody
                .contentShape(shape)
                .onTapGesture {
                    guard isInteractive else { return }
                    onSelect()
                }
        }
    }

    private func reorderGesture(
        onChanged: @escaping (DragGesture.Value) -> Void,
        onEnded: @escaping (DragGesture.Value) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .named(ProfileGridCoordinate.name))
            .onChanged(onChanged)
            .onEnded(onEnded)
            .exclusively(before: TapGesture().onEnded {
                guard isInteractive else { return }
                onSelect()
            })
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(profile.activityType.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DiscordTheme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, showsMenu ? 28 : 0)
                .allowsHitTesting(false)

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
                        .allowsHitTesting(false)
                    if !DiscordFormatting.plain(profile.details).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(DiscordFormatting.attributed(
                            profile.details,
                            size: 13,
                            weight: .regular,
                            color: DiscordTheme.secondary
                        ))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if !DiscordFormatting.plain(profile.state).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(DiscordFormatting.attributed(
                            profile.state,
                            size: 13,
                            weight: .regular,
                            color: DiscordTheme.secondary
                        ))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                    if profile.timerMode == .custom {
                        CustomTimerFields(
                            hours: profile.customHoursValue,
                            minutes: profile.customMinutesValue,
                            seconds: profile.customSecondsValue,
                            activityType: profile.activityType,
                            isEnabled: !isPublishing,
                            onCommit: { hours, minutes, seconds in
                                onCustomTimer?(hours, minutes, seconds)
                            }
                        )
                    } else if timer != .hidden {
                        PresenceTimer(display: timer, activityType: profile.activityType)
                            .allowsHitTesting(false)
                    }
                    if let statusNote {
                        Text(statusNote)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DiscordTheme.accent)
                            .allowsHitTesting(false)
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
                            .allowsHitTesting(false)
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

private struct CustomTimerFields: View {
    var hours: Int
    var minutes: Int
    var seconds: Int
    var activityType: ActivityType
    var isEnabled: Bool
    var onCommit: (Int, Int, Int) -> Void

    @State private var hoursText = ""
    @State private var minutesText = ""
    @State private var secondsText = ""
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case hours, minutes, seconds
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: activityType.timerSymbol)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                part($hoursText, field: .hours, width: 36)
                Text(":")
                    .allowsHitTesting(false)
                part($minutesText, field: .minutes, width: 28)
                Text(":")
                    .allowsHitTesting(false)
                part($secondsText, field: .seconds, width: 28)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(DiscordTheme.timer, lineWidth: focused == nil ? 1 : 1.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .background {
                OutsideClickMonitor(enabled: focused != nil) {
                    focused = nil
                }
            }
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(DiscordTheme.timer)
        .onAppear(perform: sync)
        .onChange(of: hours) { _, _ in syncIfIdle() }
        .onChange(of: minutes) { _, _ in syncIfIdle() }
        .onChange(of: seconds) { _, _ in syncIfIdle() }
        .onChange(of: focused) { old, new in
            if old != nil, old != new {
                commit()
            }
        }
        .onExitCommand {
            focused = nil
        }
        .help("Remaining time. Click outside the box when you’re done. Extra minutes and seconds roll into the next unit.")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Custom timer")
    }

    private func part(_ text: Binding<String>, field: Field, width: CGFloat) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .multilineTextAlignment(.center)
            .frame(width: width)
            .focused($focused, equals: field)
            .disabled(!isEnabled)
            .onSubmit { focused = nil }
    }

    private func syncIfIdle() {
        guard focused == nil else { return }
        sync()
    }

    private func sync() {
        hoursText = String(hours)
        minutesText = String(format: "%02d", minutes)
        secondsText = String(format: "%02d", seconds)
    }

    private func commit() {
        var nextSeconds = max(0, Int(secondsText.filter(\.isNumber)) ?? 0)
        var nextMinutes = max(0, Int(minutesText.filter(\.isNumber)) ?? 0)
        var nextHours = max(0, Int(hoursText.filter(\.isNumber)) ?? 0)
        nextMinutes += nextSeconds / 60
        nextSeconds %= 60
        nextHours += nextMinutes / 60
        nextMinutes %= 60
        if nextHours > 999 {
            nextHours = 999
            nextMinutes = 59
            nextSeconds = 59
        }
        hoursText = String(nextHours)
        minutesText = String(format: "%02d", nextMinutes)
        secondsText = String(format: "%02d", nextSeconds)
        if nextHours != hours || nextMinutes != minutes || nextSeconds != seconds {
            onCommit(nextHours, nextMinutes, nextSeconds)
        }
    }
}

/// Ends timer editing when the user clicks anywhere outside the time box.
private struct OutsideClickMonitor: NSViewRepresentable {
    var enabled: Bool
    var onOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        MonitorView()
    }

    func updateNSView(_ view: MonitorView, context: Context) {
        view.onOutside = onOutside
        view.enabled = enabled
    }

    final class MonitorView: NSView {
        var onOutside: (() -> Void)?
        var enabled = false {
            didSet {
                if enabled != oldValue {
                    updateMonitor()
                }
            }
        }

        private var monitor: Any?

        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateMonitor()
        }

        private func updateMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard enabled, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .keyDown]) { [weak self] event in
                guard let self else { return event }
                if event.type == .keyDown {
                    guard event.keyCode == 53 else { return event }
                    DispatchQueue.main.async { self.onOutside?() }
                    return nil
                }
                guard let window = self.window, event.window === window else { return event }
                let point = self.convert(event.locationInWindow, from: nil)
                guard !self.bounds.contains(point) else { return event }
                DispatchQueue.main.async { self.onOutside?() }
                return nil
            }
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
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
            Button("Download", action: onDownload)
            Button("Download full", action: onDownloadFull)
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
        .help("Edit, duplicate, download, download full, or delete")
        .accessibilityLabel("Actions for \(profile.listTitle)")
    }
}
