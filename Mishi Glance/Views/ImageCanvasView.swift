//
//  ImageCanvasView.swift
//  Mishi Glance
//
//  The image surface. AppKit rather than SwiftUI because it needs precise
//  layer geometry plus pinch, Cmd-scroll, drag-to-pan and two-finger swipe.
//

import AppKit
import AVFoundation
import SwiftUI

final class ImageCanvasNSView: NSView, NSDraggingSource {
    weak var controller: ViewerController?

    private let backdropLayer = CALayer()
    private let imageLayer = CALayer()
    private var lastDragPoint: CGPoint?
    private var dragOrigin: CGPoint?
    private var isDraggingFileOut = false
    private var swipeAccumulator: CGFloat = 0
    private var swipeArmed = true
    private var cursorHideTask: Task<Void, Never>?
    private var trackingArea: NSTrackingArea?
    private var checkerboardSize: CGSize = .zero
    /// Размер показываемого кадра в пикселях. В режиме сравнения вторая
    /// канва рисует другой снимок, поэтому размер приходит извне.
    var pixelSizeOverride: CGSize?
    /// Вторая канва не должна перехватывать жесты и менять viewport.
    var isSecondary = false
    private var animationKey: ObjectIdentifier?
    private var livePlayer: AVPlayer?
    private var liveLayer: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(backdropLayer)
        layer?.addSublayer(imageLayer)
        backdropLayer.contentsGravity = .resize
        imageLayer.contentsGravity = .resize
        imageLayer.isOpaque = false
        registerForDraggedTypes([.fileURL])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }

    // MARK: - Geometry

    override func layout() {
        super.layout()
        if !isSecondary { controller?.viewportSize = bounds.size }
        applyTransform()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    /// Кадры проигрываются самим Core Animation: дискретная покадровая
    /// анимация свойства contents дешевле таймера на главном потоке.
    func setAnimation(_ animation: AnimatedImage?, playing: Bool) {
        let key = animation.map { ObjectIdentifier($0.frames[0]) }
        if key == animationKey, playing == (imageLayer.animation(forKey: "frames") != nil) {
            return
        }
        animationKey = key
        imageLayer.removeAnimation(forKey: "frames")

        guard let animation, animation.frames.count > 1, playing else { return }

        let total = max(animation.duration, 0.02)
        var times: [NSNumber] = []
        var elapsed = 0.0
        for delay in animation.delays {
            times.append(NSNumber(value: elapsed / total))
            elapsed += delay
        }

        let keyframes = CAKeyframeAnimation(keyPath: "contents")
        keyframes.values = animation.frames
        keyframes.keyTimes = times
        keyframes.duration = total
        keyframes.calculationMode = .discrete
        keyframes.repeatCount = animation.loopCount == 0
            ? .greatestFiniteMagnitude : Float(animation.loopCount)
        keyframes.isRemovedOnCompletion = false
        keyframes.fillMode = .forwards
        imageLayer.add(keyframes, forKey: "frames")
    }

    /// Проигрывает ролик Live Photo поверх снимка — один раз, как в Фото.
    func playLivePhoto(_ url: URL?) {
        stopLivePhoto()
        guard let url else { return }

        let player = AVPlayer(url: url)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = imageLayer.frame
        layer.transform = imageLayer.transform
        self.layer?.addSublayer(layer)
        livePlayer = player
        liveLayer = layer

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopLivePhoto() }
        }
        player.play()
    }

    func stopLivePhoto() {
        livePlayer?.pause()
        liveLayer?.removeFromSuperlayer()
        livePlayer = nil
        liveLayer = nil
    }

    func setImage(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        imageLayer.isHidden = (image == nil)
        CATransaction.commit()
        checkerboardSize = .zero
        applyTransform()
    }

    /// Positions the layers from the controller's scale / offset / rotation.
    /// Layer bounds use the *unrotated* size; the rotation transform then
    /// produces the correct on-screen bounding box.
    func applyTransform() {
        guard let controller else { return }
        let unrotatedSize = pixelSizeOverride ?? controller.displayed?.pixelSize
        guard let unrotated = unrotatedSize, unrotated.width > 0 else {
            imageLayer.isHidden = true
            backdropLayer.isHidden = true
            return
        }
        imageLayer.isHidden = false

        let smooth = AppSettings.smoothScaling
        imageLayer.magnificationFilter = smooth ? .linear : .nearest
        imageLayer.minificationFilter = smooth ? .trilinear : .nearest

        let scaled = CGSize(width: unrotated.width * controller.scale,
                            height: unrotated.height * controller.scale)
        let position = CGPoint(x: bounds.midX + controller.offset.width,
                               y: bounds.midY + controller.offset.height)
        let radians = CGFloat(controller.rotation) * .pi / 180
        let transform = CATransform3DMakeRotation(-radians, 0, 0, 1)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.bounds = CGRect(origin: .zero, size: scaled)
        imageLayer.position = position
        imageLayer.transform = transform
        if let liveLayer {
            liveLayer.bounds = imageLayer.bounds
            liveLayer.position = position
            liveLayer.transform = transform
        }

        updateBackdrop(bounds: CGRect(origin: .zero, size: scaled),
                       position: position,
                       transform: transform,
                       hasAlpha: controller.displayed?.hasAlpha ?? false)
        CATransaction.commit()
    }

    /// Paints what shows through a transparent image, per Settings.
    private func updateBackdrop(bounds rect: CGRect, position: CGPoint,
                                transform: CATransform3D, hasAlpha: Bool) {
        guard hasAlpha else {
            backdropLayer.isHidden = true
            return
        }
        backdropLayer.isHidden = false
        backdropLayer.bounds = rect
        backdropLayer.position = position
        backdropLayer.transform = transform

        switch AppSettings.transparencyMode {
        case .checkerboard:
            backdropLayer.backgroundColor = nil
            let scale = window?.backingScaleFactor ?? 2
            if checkerboardSize != rect.size {
                checkerboardSize = rect.size
                backdropLayer.contents = Self.checkerboard(size: rect.size, scale: scale)
                backdropLayer.contentsScale = scale
            }
        case .background:
            backdropLayer.contents = nil
            backdropLayer.backgroundColor = AppSettings.background.nsColor.cgColor
        case .white:
            backdropLayer.contents = nil
            backdropLayer.backgroundColor = NSColor.white.cgColor
        case .black:
            backdropLayer.contents = nil
            backdropLayer.backgroundColor = NSColor.black.cgColor
        }
    }

    /// Fixed 16 pt squares, so the pattern stays put while the image zooms.
    private static func checkerboard(size: CGSize, scale: CGFloat) -> CGImage? {
        let width = Int((size.width * scale).rounded(.up))
        let height = Int((size.height * scale).rounded(.up))
        guard width > 0, height > 0, width * height < 40_000_000 else { return nil }

        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        let tile = 16 * scale
        context.setFillColor(gray: 0.85, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        context.setFillColor(gray: 0.65, alpha: 1)
        var row = 0
        var y: CGFloat = 0
        while y < CGFloat(height) {
            var column = row % 2
            var x: CGFloat = CGFloat(column) * tile
            while x < CGFloat(width) {
                context.fill(CGRect(x: x, y: y, width: tile, height: tile))
                x += tile * 2
                column += 2
            }
            y += tile
            row += 1
        }
        return context.makeImage()
    }

    // MARK: - Pointer

    /// Command inverts whichever drag mode the user picked in Settings.
    private func shouldDragFileOut(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        return (AppSettings.dragBehavior == .dragOut) != command
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        lastDragPoint = point
        dragOrigin = point
        isDraggingFileOut = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let controller else { return }
        let point = convert(event.locationInWindow, from: nil)

        if shouldDragFileOut(event) {
            guard !isDraggingFileOut, let origin = dragOrigin,
                  hypot(point.x - origin.x, point.y - origin.y) > 4
            else { return }
            isDraggingFileOut = true
            beginFileDrag(with: event)
            return
        }

        guard controller.canPan, let last = lastDragPoint else { return }
        controller.pan(by: CGSize(width: point.x - last.x, height: point.y - last.y))
        lastDragPoint = point
    }

    override func mouseUp(with event: NSEvent) {
        lastDragPoint = nil
        dragOrigin = nil
        guard !isDraggingFileOut else { return }
        // Live Photo оживает по одиночному клику, как в «Фото».
        if event.clickCount == 1, let controller, controller.hasLivePhoto {
            playLivePhoto(controller.livePhotoVideo)
            return
        }
        if event.clickCount == 2, AppSettings.doubleClickActualSize {
            if controller?.isFitMode == true {
                controller?.zoomToActualSize()
                Task { await controller?.ensureFullResolutionIfNeeded() }
            } else {
                controller?.applyFit()
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        showCursorAndScheduleHide()
        controller?.flashOverlay()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if AppSettings.dragBehavior == .dragOut {
            addCursorRect(bounds, cursor: .openHand)
        } else if controller?.canPan == true {
            addCursorRect(bounds, cursor: .openHand)
        }
    }

    // MARK: - Dragging the file out

    private func beginFileDrag(with event: NSEvent) {
        guard let entry = controller?.folder.current else { return }

        let item = NSDraggingItem(pasteboardWriter: entry.url as NSURL)
        let preview = NSWorkspace.shared.icon(forFile: entry.url.path)
        preview.size = NSSize(width: 128, height: 128)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            CGRect(x: point.x - 64, y: point.y - 64, width: 128, height: 128),
            contents: preview
        )
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy] : []
    }

    // MARK: - Gestures

    override func magnify(with event: NSEvent) {
        guard let controller else { return }
        let anchor = convert(event.locationInWindow, from: nil)
        controller.setScale(controller.scale * (1 + event.magnification), anchor: anchor)
        Task { await controller.ensureFullResolutionIfNeeded() }
    }

    override func scrollWheel(with event: NSEvent) {
        guard let controller else { return }

        if event.modifierFlags.contains(.command) {
            let anchor = convert(event.locationInWindow, from: nil)
            let step = 1 + (event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.005
                                                            : event.scrollingDeltaY * 0.05)
            controller.setScale(controller.scale * step, anchor: anchor)
            Task { await controller.ensureFullResolutionIfNeeded() }
            return
        }

        if controller.canPan {
            controller.pan(by: CGSize(width: event.scrollingDeltaX, height: -event.scrollingDeltaY))
            return
        }

        guard AppSettings.swipeNavigation else { return }
        trackSwipe(event)
    }

    /// Two-finger horizontal swipe pages through the folder. One navigation per
    /// gesture: re-arms only after the fingers lift or the direction reverses.
    private func trackSwipe(_ event: NSEvent) {
        switch event.phase {
        case .began:
            swipeAccumulator = 0
            swipeArmed = true
        case .ended, .cancelled:
            swipeAccumulator = 0
            swipeArmed = true
            return
        default:
            break
        }

        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return }
        swipeAccumulator += event.scrollingDeltaX

        guard swipeArmed, abs(swipeAccumulator) > 50 else { return }
        swipeArmed = false
        // Swiping left (content moves left) reveals the next image.
        if swipeAccumulator < 0 {
            controller?.next()
        } else {
            controller?.previous()
        }
        swipeAccumulator = 0
    }

    // MARK: - Cursor auto-hide

    func showCursorAndScheduleHide() {
        cursorHideTask?.cancel()
        NSCursor.unhide()

        guard window?.styleMask.contains(.fullScreen) == true else { return }
        cursorHideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, self?.window?.styleMask.contains(.fullScreen) == true else { return }
            NSCursor.setHiddenUntilMouseMoves(true)
        }
    }

    func cancelCursorHiding() {
        cursorHideTask?.cancel()
        cursorHideTask = nil
        NSCursor.unhide()
    }
}

// MARK: - SwiftUI bridge

struct ImageCanvas: NSViewRepresentable {
    let controller: ViewerController
    // Passed explicitly so SwiftUI observes them and re-runs updateNSView.
    let image: CGImage?
    let scale: CGFloat
    let offset: CGSize
    let rotation: Int
    let animation: AnimatedImage?
    let isPlaying: Bool
    var pixelSize: CGSize?
    var isSecondary = false

    func makeNSView(context: Context) -> ImageCanvasNSView {
        let view = ImageCanvasNSView(frame: .zero)
        view.controller = controller
        view.pixelSizeOverride = pixelSize
        view.isSecondary = isSecondary
        view.setImage(image)
        return view
    }

    func updateNSView(_ view: ImageCanvasNSView, context: Context) {
        view.controller = controller
        view.pixelSizeOverride = pixelSize
        view.isSecondary = isSecondary
        if context.coordinator.lastImage !== image {
            context.coordinator.lastImage = image
            view.setImage(image)
        }
        view.applyTransform()
        view.setAnimation(animation, playing: isPlaying)
        view.window?.invalidateCursorRects(for: view)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var lastImage: CGImage?
    }
}
