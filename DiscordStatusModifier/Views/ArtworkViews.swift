import AppKit
import SwiftUI

struct ArtworkImage: View {
    var local: URL?
    var remote: URL?
    var cornerRadius: CGFloat = 12
    var clipsAsCircle = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
            content
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .compositingGroup()
        .clipped()
        .clipShape(mask)
        .contentShape(mask)
        .overlay(mask.stroke(Color.white.opacity(0.06), lineWidth: 1))
        .accessibilityHidden(local == nil && remote == nil)
    }

    @ViewBuilder
    private var content: some View {
        if let local {
            LocalArtwork(url: local)
                .id(local.absoluteString)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .allowsHitTesting(false)
        } else if let remote {
            AsyncImage(url: remote) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                default:
                    placeholder
                }
            }
            .id(remote.absoluteString)
            .allowsHitTesting(false)
        } else {
            placeholder
                .allowsHitTesting(false)
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(DiscordTheme.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mask: AnyShape {
        if clipsAsCircle {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct LocalArtwork: NSViewRepresentable {
    var url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ArtworkHostView {
        let view = ArtworkHostView()
        load(into: view.imageView, context: context)
        return view
    }

    func updateNSView(_ view: ArtworkHostView, context: Context) {
        load(into: view.imageView, context: context)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ArtworkHostView, context: Context) -> CGSize? {
        let width = proposal.width ?? 64
        let height = proposal.height ?? 64
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            return CGSize(width: 64, height: 64)
        }
        return CGSize(width: width, height: height)
    }

    private func load(into view: NSImageView, context: Context) {
        if context.coordinator.url == url, view.image != nil { return }
        context.coordinator.url = url
        view.image = nil
        view.animates = false
        let image = NSImage(contentsOf: url)
        view.image = image
        view.animates = url.pathExtension.lowercased() == "gif"
    }

    final class Coordinator {
        var url: URL?
    }
}

/// Hosts `NSImageView` so GIFs animate without expanding SwiftUI layout beyond the framed box.
private final class ArtworkHostView: NSView {
    let imageView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        clipsToBounds = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.imageFrameStyle = .none
        imageView.autoresizingMask = [.width, .height]
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        addSubview(imageView)
    }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct PresenceTimer: View {
    var display: TimerDisplay

    var body: some View {
        switch display {
        case .hidden:
            EmptyView()
        case .fixed(let interval):
            label(ClockFormat.string(from: interval))
        case .countUp(let start):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(ClockFormat.string(from: context.date.timeIntervalSince(start)))
            }
        case .countDown(let end):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(ClockFormat.string(from: end.timeIntervalSince(context.date)))
            }
        }
    }

    private func label(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gamecontroller.fill")
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(DiscordTheme.timer)
        .accessibilityLabel("Elapsed \(text)")
    }
}
