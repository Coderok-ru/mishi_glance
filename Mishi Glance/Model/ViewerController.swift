//
//  ViewerController.swift
//  Mishi Glance
//
//  Owns the folder cursor, the decode cache and the display transform for one
//  window. Views read from it and call into it; they hold no logic themselves.
//

import AppKit
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ViewerController {
    let folder = FolderModel()

    private(set) var displayed: DecodedImage?
    private(set) var isDecoding = false
    private(set) var failureMessage: String?
    private(set) var metadata: ImageMetadata?

    /// Points per image pixel. 1.0 means 100 %.
    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    /// Display-only rotation in degrees: 0, 90, 180 or 270.
    private(set) var rotation: Int = 0
    private(set) var isFitMode = true

    var showInfoPanel = false
    var overlayVisible = true
    /// Set while the pointer rests on the toolbar, so it does not fade away
    /// under the cursor.
    var pinOverlay = false {
        didSet {
            guard pinOverlay != oldValue else { return }
            if pinOverlay { overlayHideTask?.cancel() } else { flashOverlay() }
        }
    }

    /// Set by the canvas whenever it is laid out.
    var viewportSize: CGSize = .zero {
        didSet {
            guard viewportSize != oldValue, viewportSize.width > 0 else { return }
            if isFitMode { applyFit() } else { clampOffset() }
        }
    }

    @ObservationIgnored weak var window: NSWindow?
    /// Fires whenever the displayed file changes, so the window can retitle.
    @ObservationIgnored var onCurrentChanged: (() -> Void)?
    /// Opens or closes the folder browser window that belongs to this viewer.
    @ObservationIgnored var onToggleBrowser: (() -> Void)?
    @ObservationIgnored private let loader = ImageLoader.shared
    @ObservationIgnored private var loadGeneration = 0
    @ObservationIgnored private var overlayHideTask: Task<Void, Never>?

    init() {
        folder.onFolderChanged = { [weak self] in
            guard let self else { return }
            Task { await self.reloadCurrent() }
        }
    }

    // MARK: - Opening

    func open(url: URL) async {
        await folder.open(url: url)
        await reloadCurrent()
    }

    /// Decodes the file under the cursor, then warms its neighbours.
    func reloadCurrent() async {
        loadGeneration += 1
        let generation = loadGeneration

        guard let entry = folder.current else {
            displayed = nil
            metadata = nil
            failureMessage = folder.errorMessage
            onCurrentChanged?()
            return
        }

        failureMessage = nil
        isDecoding = true

        let target = decodeTargetPixels
        let decoded = await loader.image(for: entry.url, maxPixel: target)

        guard generation == loadGeneration else { return }

        isDecoding = false
        if let decoded {
            displayed = decoded
            rotation = 0
            applyFit()
            flashOverlay()
        } else {
            displayed = nil
            failureMessage = "Не удалось открыть «\(entry.name)»"
        }
        onCurrentChanged?()

        metadata = nil
        let url = entry.url
        Task.detached(priority: .utility) { [weak self] in
            let meta = ImageDecoder.metadata(url: url)
            await self?.applyMetadata(meta, for: url, generation: generation)
        }

        await loader.prefetch(urls: folder.neighbourURLs(radius: 2), maxPixel: target)
    }

    private func applyMetadata(_ meta: ImageMetadata?, for url: URL, generation: Int) {
        guard generation == loadGeneration, folder.current?.url == url else { return }
        metadata = meta
    }

    /// The spec's decode budget: the screen's longest edge in device pixels.
    private var decodeTargetPixels: Int {
        let screen = window?.screen ?? NSScreen.main
        let size = screen?.frame.size ?? CGSize(width: 1920, height: 1080)
        let backing = screen?.backingScaleFactor ?? 2
        return Int((max(size.width, size.height) * backing).rounded())
    }

    // MARK: - Navigation

    func next() { if folder.goNext() { Task { await reloadCurrent() } } }
    func previous() { if folder.goPrevious() { Task { await reloadCurrent() } } }
    func first() { if folder.goFirst() { Task { await reloadCurrent() } } }
    func last() { if folder.goLast() { Task { await reloadCurrent() } } }

    func setSortOrder(_ order: ImageSortOrder) {
        folder.sortOrder = order
    }

    func setSortAscending(_ ascending: Bool) {
        folder.sortAscending = ascending
    }

    /// Jumps to a file picked in the folder browser.
    func show(entry: ImageEntry) {
        guard let index = folder.entries.firstIndex(where: { $0.url == entry.url }),
              index != folder.currentIndex
        else { return }
        folder.select(index: index)
        Task { await reloadCurrent() }
    }

    func toggleBrowser() { onToggleBrowser?() }

    // MARK: - Zoom, pan, rotation

    /// Size of the image on screen at 100 %, accounting for rotation.
    var orientedPixelSize: CGSize {
        guard let displayed else { return .zero }
        let size = displayed.pixelSize
        return (rotation % 180 == 0) ? size : CGSize(width: size.height, height: size.width)
    }

    var fitScale: CGFloat {
        let image = orientedPixelSize
        guard image.width > 0, image.height > 0, viewportSize.width > 0, viewportSize.height > 0 else {
            return 1
        }
        let raw = min(viewportSize.width / image.width, viewportSize.height / image.height)
        return AppSettings.allowUpscale ? raw : min(raw, 1)
    }

    var zoomPercent: Int { Int((scale * 100).rounded()) }

    func applyFit() {
        scale = fitScale
        offset = .zero
        isFitMode = true
    }

    func zoomToActualSize() {
        setScale(1, anchor: nil)
    }

    func zoomIn() { setScale(scale * 1.25, anchor: nil) }
    func zoomOut() { setScale(scale / 1.25, anchor: nil) }

    /// `anchor` is a point in view coordinates that should stay put while the
    /// scale changes — used by pinch and Cmd+scroll.
    func setScale(_ newScale: CGFloat, anchor: CGPoint?) {
        guard displayed != nil else { return }
        let fit = fitScale
        let clamped = min(max(newScale, min(fit, 0.02)), 64)
        guard clamped != scale else { return }

        if let anchor {
            // Keep the image point under the cursor stationary.
            let centre = CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2)
            let fromCentre = CGSize(width: anchor.x - centre.x, height: anchor.y - centre.y)
            let ratio = clamped / scale
            offset = CGSize(
                width: fromCentre.width - (fromCentre.width - offset.width) * ratio,
                height: fromCentre.height - (fromCentre.height - offset.height) * ratio
            )
        }

        scale = clamped
        isFitMode = abs(clamped - fit) < 0.0001
        if isFitMode { offset = .zero } else { clampOffset() }
    }

    func pan(by delta: CGSize) {
        guard canPan else { return }
        offset = CGSize(width: offset.width + delta.width, height: offset.height + delta.height)
        clampOffset()
    }

    var canPan: Bool {
        let displaySize = scaledSize
        return displaySize.width > viewportSize.width + 0.5 || displaySize.height > viewportSize.height + 0.5
    }

    var scaledSize: CGSize {
        let image = orientedPixelSize
        return CGSize(width: image.width * scale, height: image.height * scale)
    }

    /// Keeps the image from being dragged off screen; axes that fit stay centred.
    private func clampOffset() {
        let displaySize = scaledSize
        let slackX = max((displaySize.width - viewportSize.width) / 2, 0)
        let slackY = max((displaySize.height - viewportSize.height) / 2, 0)
        offset = CGSize(
            width: min(max(offset.width, -slackX), slackX),
            height: min(max(offset.height, -slackY), slackY)
        )
    }

    func rotate(clockwise: Bool) {
        guard displayed != nil else { return }
        rotation = ((rotation + (clockwise ? 90 : -90)) % 360 + 360) % 360
        applyFit()
        flashOverlay()
    }

    /// Pulls the full-resolution decode once the user zooms past fit.
    func ensureFullResolutionIfNeeded() async {
        guard let entry = folder.current,
              let current = displayed,
              !current.isFullResolution,
              scale > fitScale + 0.0001
        else { return }

        let generation = loadGeneration
        guard let full = await loader.image(for: entry.url, maxPixel: 0) else { return }
        guard generation == loadGeneration, folder.current?.url == entry.url else { return }
        displayed = full
    }

    // MARK: - Overlay

    func flashOverlay() {
        overlayVisible = true
        overlayHideTask?.cancel()
        guard !pinOverlay else { return }
        overlayHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.pinOverlay == false else { return }
            self?.overlayVisible = false
        }
    }

    var statusText: String? {
        guard let entry = folder.current else { return nil }
        var parts = ["\(folder.currentIndex + 1) / \(folder.count)", entry.name]
        if let displayed {
            parts.append("\(Int(displayed.pixelSize.width))×\(Int(displayed.pixelSize.height))")
        }
        parts.append(ByteFormat.string(entry.fileSize))
        if !isFitMode {
            parts.append("\(zoomPercent) %")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - File actions

    func revealInFinder() {
        guard let url = folder.current?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyToPasteboard() {
        guard let entry = folder.current else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var objects: [NSPasteboardWriting] = [entry.url as NSURL]
        if let displayed {
            let rep = NSBitmapImageRep(cgImage: displayed.image)
            let image = NSImage(size: rep.size)
            image.addRepresentation(rep)
            objects.insert(image, at: 0)
        }
        pasteboard.writeObjects(objects)
    }

    func moveCurrentToTrash() {
        guard let entry = folder.current else { return }

        if AppSettings.confirmDelete {
            let alert = NSAlert()
            alert.messageText = "Переместить «\(entry.name)» в Корзину?"
            alert.informativeText = "Файл будет удалён из папки."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Переместить в Корзину")
            alert.addButton(withTitle: "Отмена")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Больше не спрашивать"

            let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
                guard let self else { return }
                if alert.suppressionButton?.state == .on {
                    UserDefaults.standard.set(false, forKey: SettingsKey.confirmDelete)
                }
                guard response == .alertFirstButtonReturn else { return }
                self.performTrash(entry.url)
            }

            if let window {
                alert.beginSheetModal(for: window, completionHandler: respond)
            } else {
                respond(alert.runModal())
            }
        } else {
            performTrash(entry.url)
        }
    }

    private func performTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            Task { await loader.invalidate(url: url) }
            folder.removeCurrent()
            Task { await reloadCurrent() }
        } catch {
            presentError("Не удалось переместить файл в Корзину", error.localizedDescription)
        }
    }

    /// Presents the system share sheet, anchored to the window.
    func share() {
        guard let url = folder.current?.url, let anchor = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: CGRect(x: anchor.bounds.midX, y: anchor.bounds.minY + 80, width: 1, height: 1),
                    of: anchor, preferredEdge: .maxY)
    }

    /// Opens the current file in the app chosen in Settings (Preview by default).
    func openInExternalEditor() {
        guard let url = folder.current?.url, let editor = AppSettings.externalEditorURL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Applications that can open the current file, for the Open With submenu.
    func openWithCandidates() -> [URL] {
        guard let url = folder.current?.url else { return [] }
        let bundleURL = Bundle.main.bundleURL
        return NSWorkspace.shared.urlsForApplications(toOpen: url).filter { $0 != bundleURL }
    }

    func open(with applicationURL: URL) {
        guard let url = folder.current?.url else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: applicationURL, configuration: configuration)
    }

    private func presentError(_ message: String, _ detail: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if let window {
            alert.beginSheetModal(for: window, completionHandler: nil)
        } else {
            alert.runModal()
        }
    }
}
