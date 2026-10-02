import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

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
            let token = ArtworkFileToken.token(for: local)
            LocalArtwork(url: local, stamp: token)
                .id(token)
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
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mask: AnyShape {
        if clipsAsCircle {
            return AnyShape(Circle())
        }
        return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

func artworkDisplayID(local: URL?, remote: URL?) -> String {
    "\(ArtworkFileToken.token(for: local))|\(remote?.absoluteString ?? "")"
}

enum ArtworkFileToken {
    /// Path plus size and modification time, so a replaced file is a new image.
    static func token(for url: URL?) -> String {
        guard let url else { return "" }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        return "\(url.path)|\(size)|\(modified)"
    }
}

private struct LocalArtwork: NSViewRepresentable {
    var url: URL
    var stamp: String

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
        if context.coordinator.url == url, context.coordinator.stamp == stamp, view.image != nil { return }
        context.coordinator.url = url
        context.coordinator.stamp = stamp
        view.image = nil
        view.animates = false
        // `NSImage(contentsOf:)` caches by path, so a replaced file would keep the old picture.
        let image = (try? Data(contentsOf: url)).flatMap { NSImage(data: $0) }
        view.image = image
        view.animates = url.pathExtension.lowercased() == "gif"
    }

    final class Coordinator {
        var url: URL?
        var stamp: String?
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
    var activityType: ActivityType = .playing

    var body: some View {
        switch display {
        case .hidden:
            EmptyView()
        case .fixed(let interval):
            label(ClockFormat.string(from: interval), spoken: "Timer")
        case .countUp(let start):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(ClockFormat.string(from: context.date.timeIntervalSince(start)), spoken: "Elapsed")
            }
        case .countDown(let end):
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(ClockFormat.string(from: end.timeIntervalSince(context.date)), spoken: "Remaining")
            }
        }
    }

    private func label(_ text: String, spoken: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: activityType.timerSymbol)
            Text(text)
        }
        .font(.system(size: 13, weight: .semibold).monospacedDigit())
        .foregroundStyle(DiscordTheme.timer)
        .accessibilityLabel("\(spoken) \(text)")
    }
}

struct SquareCropSheet: View {
    var sourceURL: URL
    var onApply: (Data, String) -> Void
    var onCancel: () -> Void

    @State private var image: NSImage?
    @State private var pixelSize = CGSize.zero
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @State private var dragStart = CGSize.zero
    @State private var errorText: String?
    @State private var failed = false

    private let viewport: CGFloat = 280

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Crop to a square")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
            Text("Drag to move the image. The square is what gets saved.")
                .font(.system(size: 12))
                .foregroundStyle(DiscordTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Group {
                if let image {
                    cropCanvas(image)
                    HStack(spacing: 10) {
                        Text("Zoom")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(DiscordTheme.secondary)
                        Slider(value: $zoom, in: 1...4)
                    }
                } else if failed {
                    Text("Couldn’t read that image.")
                        .foregroundStyle(DiscordTheme.danger)
                } else {
                    ProgressView()
                        .frame(width: viewport, height: viewport)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DiscordTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use image", action: apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(image == nil)
            }
        }
        .padding(20)
        .frame(width: 360)
        .background(DiscordTheme.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .onChange(of: zoom) { _, _ in
            offset = clamped(offset)
            dragStart = offset
        }
    }

    private func cropCanvas(_ image: NSImage) -> some View {
        let size = displaySize
        return Image(nsImage: image)
            .resizable()
            .frame(width: size.width, height: size.height)
            .offset(offset)
            .frame(width: viewport, height: viewport)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DiscordTheme.accent, lineWidth: 2)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        offset = clamped(CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        ))
                    }
                    .onEnded { _ in
                        dragStart = offset
                    }
            )
            .accessibilityLabel("Crop area")
    }

    private var displaySize: CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else {
            return CGSize(width: viewport, height: viewport)
        }
        let base = max(viewport / pixelSize.width, viewport / pixelSize.height)
        return CGSize(width: pixelSize.width * base * zoom, height: pixelSize.height * base * zoom)
    }

    private func clamped(_ proposed: CGSize) -> CGSize {
        let size = displaySize
        let maxX = max(0, (size.width - viewport) / 2)
        let maxY = max(0, (size.height - viewport) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func cropRect() -> CGRect {
        let width = pixelSize.width
        let height = pixelSize.height
        guard width > 0, height > 0 else { return .zero }
        let factor = max(viewport / width, viewport / height) * zoom
        let displayW = width * factor
        let displayH = height * factor
        let originX = viewport / 2 + offset.width - displayW / 2
        let originY = viewport / 2 + offset.height - displayH / 2
        var side = Int(floor(viewport / factor))
        side = max(1, min(side, Int(width), Int(height)))
        let maxX = max(0, Int(width) - side)
        let maxY = max(0, Int(height) - side)
        let x = min(max(0, Int(floor(-originX / factor))), maxX)
        let y = min(max(0, Int(floor(-originY / factor))), maxY)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    private func load() {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            failed = true
            return
        }
        pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private func apply() {
        do {
            let result = try SquareImageCrop.export(from: sourceURL, crop: cropRect())
            onApply(result.data, result.fileExtension)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

enum SquareImageCrop {
    struct Result {
        var data: Data
        var fileExtension: String
    }

    static func export(from url: URL, crop: CGRect) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw StoreError.unreadableImage
        }
        guard crop.width >= 1, crop.height >= 1 else {
            throw StoreError.unreadableImage
        }
        if url.pathExtension.lowercased() == "gif" {
            return Result(data: try gifData(source: source, crop: crop), fileExtension: "gif")
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = image.cropping(to: crop) else {
            throw StoreError.unreadableImage
        }
        return Result(data: try pngData(fittedSquare(cropped, maxSide: 1024)), fileExtension: "png")
    }

    private static func gifData(source: CGImageSource, crop: CGRect) throws -> Data {
        let count = CGImageSourceGetCount(source)
        guard count > 0, let first = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw StoreError.unreadableImage
        }
        let canvas = CGSize(width: first.width, height: first.height)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, count, nil) else {
            throw StoreError.unreadableImage
        }
        var loop: Any = 0
        if let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any],
           let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any],
           let existing = gif[kCGImagePropertyGIFLoopCount] {
            loop = existing
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: loop]
        ] as CFDictionary)

        var written = 0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let full = frameOnCanvas(frame, canvas: canvas)
            guard let piece = full.cropping(to: crop) else { continue }
            let square = fittedSquare(piece, maxSide: 512)
            let delay = frameDelay(source: source, index: index)
            let frameProps: [CFString: Any] = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: delay,
                    kCGImagePropertyGIFUnclampedDelayTime: delay
                ]
            ]
            CGImageDestinationAddImage(destination, square, frameProps as CFDictionary)
            written += 1
        }
        guard written > 0, CGImageDestinationFinalize(destination) else {
            throw StoreError.unreadableImage
        }
        return data as Data
    }

    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any] else {
            return 0.1
        }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime]
        let clamped = gif[kCGImagePropertyGIFDelayTime]
        for value in [unclamped, clamped] {
            if let delay = value as? Double, delay > 0 { return delay }
            if let delay = value as? NSNumber, delay.doubleValue > 0 { return delay.doubleValue }
        }
        return 0.1
    }

    private static func frameOnCanvas(_ frame: CGImage, canvas: CGSize) -> CGImage {
        let width = Int(canvas.width)
        let height = Int(canvas.height)
        if frame.width == width, frame.height == height { return frame }
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return frame
        }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        return context.makeImage() ?? frame
    }

    private static func fittedSquare(_ image: CGImage, maxSide: Int) -> CGImage {
        let side = min(image.width, image.height, maxSide)
        guard side > 0 else { return image }
        if image.width == side, image.height == side { return image }
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage() ?? image
    }

    private static func pngData(_ image: CGImage) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw StoreError.unreadableImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw StoreError.unreadableImage
        }
        return data as Data
    }
}
