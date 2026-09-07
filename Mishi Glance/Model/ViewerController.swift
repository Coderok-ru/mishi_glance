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
    private(set) var histogram: ImageHistogram?
    /// Кадры анимации, если файл многокадровый.
    private(set) var animation: AnimatedImage?
    /// Ролик Live Photo рядом со снимком.
    private(set) var livePhotoVideo: URL?
    var isAnimationPlaying = true

    /// Points per image pixel. 1.0 means 100 %.
    private(set) var scale: CGFloat = 1
    private(set) var offset: CGSize = .zero
    /// Display-only rotation in degrees: 0, 90, 180 or 270.
    private(set) var rotation: Int = 0
    private(set) var isFitMode = true

    private(set) var rating = 0
    private(set) var flag: PickFlag?
    /// Второй снимок для сравнения бок о бок.
    private(set) var compareEntry: ImageEntry?
    private(set) var compareImage: DecodedImage?
    var compareMode: CompareMode = .sideBySide
    /// Прозрачность верхнего кадра при наложении.
    var compareOpacity = 0.5

    private(set) var isSlideshowRunning = false
    /// Режим пипетки: цвет читается под курсором.
    var isSamplingColor = false {
        didSet { if !isSamplingColor { sampledColor = nil } }
    }
    private(set) var sampledColor: SampledColor?

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
    @ObservationIgnored private var slideshowTask: Task<Void, Never>?
    @ObservationIgnored private var sampler: PixelSampler?

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

        rating = ImageMarks.rating(of: entry.url)
        flag = ImageMarks.flag(of: entry.url)
        metadata = nil
        histogram = nil
        animation = nil
        sampler = nil
        sampledColor = nil
        isAnimationPlaying = true
        livePhotoVideo = entry.livePhotoVideoURL

        let url = entry.url
        Task.detached(priority: .utility) { [weak self] in
            let meta = ImageDecoder.metadata(url: url)
            await self?.applyMetadata(meta, for: url, generation: generation)
        }

        if let decoded {
            let frame = decoded.image
            Task.detached(priority: .utility) { [weak self] in
                let computed = ImageDecoder.histogram(of: frame)
                await self?.applyHistogram(computed, for: url, generation: generation)
            }
        }

        // Анимацию разворачиваем в кадры отдельно: для обычных снимков
        // ImageDecoder сразу вернёт nil и работы не будет.
        if ImageDecoder.frameCount(url: url) > 1 {
            Task.detached(priority: .userInitiated) { [weak self] in
                let animated = ImageDecoder.decodeAnimation(url: url, maxPixelSize: target)
                await self?.applyAnimation(animated, for: url, generation: generation)
            }
        }

        await loader.prefetch(urls: folder.neighbourURLs(radius: 2), maxPixel: target)
    }

    private func applyHistogram(_ computed: ImageHistogram?, for url: URL, generation: Int) {
        guard generation == loadGeneration, folder.current?.url == url else { return }
        histogram = computed
    }

    private func applyAnimation(_ animated: AnimatedImage?, for url: URL, generation: Int) {
        guard generation == loadGeneration, folder.current?.url == url else { return }
        animation = animated
    }

    var isAnimated: Bool { (animation?.frames.count ?? 0) > 1 }
    var hasLivePhoto: Bool { livePhotoVideo != nil }

    func toggleAnimationPlayback() {
        guard isAnimated else { return }
        isAnimationPlaying.toggle()
        flashOverlay()
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

    // MARK: - Слайдшоу

    func toggleSlideshow() {
        isSlideshowRunning ? stopSlideshow() : startSlideshow()
    }

    func startSlideshow() {
        guard folder.count > 1 else { return }
        isSlideshowRunning = true
        flashOverlay()
        slideshowTask?.cancel()
        slideshowTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = AppSettings.slideshowInterval
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled, let self, self.isSlideshowRunning else { return }
                // Листаем напрямую, чтобы next() не остановил показ.
                if self.folder.goNext() { await self.reloadCurrent() } else { self.stopSlideshow() }
            }
        }
    }

    func stopSlideshow() {
        slideshowTask?.cancel()
        slideshowTask = nil
        guard isSlideshowRunning else { return }
        isSlideshowRunning = false
        flashOverlay()
    }

    // MARK: - Пипетка

    /// `point` — координата внутри изображения в его собственных пикселях.
    func sampleColor(atImagePoint point: CGPoint) {
        guard isSamplingColor, let displayed else { return }
        if sampler == nil { sampler = PixelSampler(image: displayed.image) }
        // Буфер строится по фактическому кадру, который может быть уменьшен
        // относительно оригинала, — приводим координату к его масштабу.
        let ratio = Double(displayed.image.width) / max(displayed.pixelSize.width, 1)
        sampledColor = sampler?.color(atX: Int(point.x * ratio), y: Int(point.y * ratio))
    }

    func copySampledColor() {
        guard let sampledColor else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sampledColor.hex, forType: .string)
        flashOverlay()
    }

    // MARK: - Печать

    func printCurrent() {
        guard let displayed, let window else { return }
        let info = NSPrintInfo.shared
        info.orientation = displayed.pixelSize.width > displayed.pixelSize.height
            ? .landscape : .portrait
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true

        let view = PrintableImageView(image: displayed.image, printInfo: info)
        let operation = NSPrintOperation(view: view, printInfo: info)
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.jobTitle = folder.current?.name ?? "Изображение"
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    // MARK: - Отбраковка

    func setRating(_ value: Int) {
        guard let entry = folder.current else { return }
        let next = (value == rating) ? 0 : value      // повторное нажатие снимает
        ImageMarks.setRating(next, at: entry.url)
        rating = next
        flashOverlay()
    }

    func setFlag(_ value: PickFlag?) {
        guard let entry = folder.current else { return }
        let next = (value == flag) ? nil : value
        ImageMarks.setFlag(next, at: entry.url)
        flag = next
        flashOverlay()
    }

    /// Сколько файлов папки помечено выбранным флагом.
    func count(of value: PickFlag) -> Int {
        folder.entries.reduce(0) { $0 + (ImageMarks.flag(of: $1.url) == value ? 1 : 0) }
    }

    /// Раскладывает отобранные снимки в выбранную папку.
    func movePicked(to directory: URL) -> (moved: Int, failed: Int) {
        var moved = 0, failed = 0
        for entry in folder.entries where ImageMarks.flag(of: entry.url) == .picked {
            let target = directory.appendingPathComponent(entry.name)
            do {
                try FileManager.default.moveItem(at: entry.url, to: target)
                moved += 1
            } catch { failed += 1 }
        }
        return (moved, failed)
    }

    /// Отправляет отклонённые в Корзину — оттуда их ещё можно вернуть.
    func trashRejected() -> Int {
        var count = 0
        for entry in folder.entries where ImageMarks.flag(of: entry.url) == .rejected {
            if (try? FileManager.default.trashItem(at: entry.url, resultingItemURL: nil)) != nil {
                count += 1
            }
        }
        return count
    }

    // MARK: - Сравнение

    var isComparing: Bool { compareEntry != nil }

    /// Ставит рядом следующий снимок папки. Повторный вызов выключает режим.
    func toggleCompareWithNext() {
        guard compareEntry == nil else {
            compareEntry = nil
            compareImage = nil
            flashOverlay()
            return
        }
        guard folder.count > 1 else { return }
        let next = (folder.currentIndex + 1) % folder.count
        compare(with: folder.entries[next])
    }

    func compare(with entry: ImageEntry) {
        compareEntry = entry
        compareImage = nil
        let target = decodeTargetPixels
        Task { [weak self] in
            let decoded = await ImageLoader.shared.image(for: entry.url, maxPixel: target)
            guard let self, self.compareEntry?.url == entry.url else { return }
            self.compareImage = decoded
            self.applyFit()
            self.flashOverlay()
        }
    }

    // MARK: - Navigation

    func next() { stopSlideshow(); if folder.goNext() { endCompare(); Task { await reloadCurrent() } } }
    func previous() { stopSlideshow(); if folder.goPrevious() { endCompare(); Task { await reloadCurrent() } } }
    func first() { stopSlideshow(); if folder.goFirst() { endCompare(); Task { await reloadCurrent() } } }
    func last() { stopSlideshow(); if folder.goLast() { endCompare(); Task { await reloadCurrent() } } }

    private func endCompare() {
        compareEntry = nil
        compareImage = nil
    }

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
        let available = (isComparing && compareMode == .sideBySide)
            ? CGSize(width: (viewportSize.width - 8) / 2, height: viewportSize.height)
            : viewportSize
        let raw = min(available.width / image.width, available.height / image.height)
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
        if let animation, animation.frames.count > 1 {
            parts.append("\(animation.frames.count) кадров")
        }
        if hasLivePhoto { parts.append("Live Photo") }
        if rating > 0 { parts.append(String(repeating: "★", count: rating)) }
        switch flag {
        case .picked: parts.append("отобрано")
        case .rejected: parts.append("отклонено")
        case nil: break
        }
        if let compareEntry {
            parts.append("\(compareMode.title.lowercased()) с \(compareEntry.name)")
        }
        if isSlideshowRunning { parts.append("слайдшоу") }
        if let sampledColor { parts.append("\(sampledColor.hex) · \(sampledColor.rgbText)") }
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
