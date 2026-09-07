//
//  ViewerWindowController.swift
//  Mishi Glance
//
//  One window per folder. The NSWindow subclass intercepts the plain
//  (non-Command) navigation keys before SwiftUI can swallow them.
//

import AppKit
import SwiftUI

final class ViewerWindow: NSWindow {
    /// Returns true when the key was consumed.
    var keyHandler: ((NSEvent) -> Bool)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        // Command combinations belong to the main menu; everything else that
        // we recognise is handled here so it never reaches the hosting view.
        if event.type == .keyDown,
           !event.modifierFlags.contains(.command),
           keyHandler?(event) == true {
            return
        }
        super.sendEvent(event)
    }
}

@MainActor
final class ViewerWindowController: NSWindowController, NSWindowDelegate {
    let controller = ViewerController()

    private var canvasHost: NSHostingView<ViewerView>?
    private var settingsObserver: NSObjectProtocol?
    private var browser: BrowserWindowController?

    init() {
        let window = ViewerWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.minSize = NSSize(width: 420, height: 320)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed

        super.init(window: window)

        window.delegate = self
        controller.window = window
        controller.onCurrentChanged = { [weak self] in
            self?.updateTitle()
            self?.browser?.updateTitle()
        }
        controller.onToggleBrowser = { [weak self] in self?.toggleBrowser() }

        let host = NSHostingView(rootView: ViewerView(controller: controller))
        host.frame = window.contentLayoutRect
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        canvasHost = host

        window.backgroundColor = AppSettings.background.nsColor

        if AppSettings.rememberWindowFrame {
            window.setFrameAutosaveName("MishiGlanceViewer")
        } else {
            window.center()
        }

        window.keyHandler = { [weak self] event in
            self?.handleKey(event) ?? false
        }

        settingsObserver = NotificationCenter.default.addObserver(
            forName: .viewerSettingsChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applySettings()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        if let settingsObserver {
            NotificationCenter.default.removeObserver(settingsObserver)
        }
    }

    // MARK: - Content

    func open(url: URL) {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        Task { await controller.open(url: url) }
    }

    func showEmpty() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        updateTitle()
    }

    private func updateTitle() {
        guard let window else { return }
        if let entry = controller.folder.current {
            window.title = entry.name
            window.representedURL = entry.url
            window.standardWindowButton(.documentIconButton)?.image = NSWorkspace.shared.icon(forFile: entry.url.path)
        } else {
            window.title = "Mishi Glance"
            window.representedURL = nil
        }
    }

    /// Opens or closes the companion grid of the folder's images.
    func toggleBrowser() {
        if browser == nil {
            browser = BrowserWindowController(controller: controller)
        }
        browser?.toggle()
    }

    var isBrowserVisible: Bool { browser?.isVisible ?? false }

    private func applySettings() {
        window?.backgroundColor = AppSettings.background.nsColor
        controller.folder.sortOrder = AppSettings.sortOrder
        controller.folder.sortAscending = AppSettings.sortAscending
        if controller.isFitMode {
            controller.applyFit()
        }
        // Re-reads smooth scaling and the transparency backdrop.
        findCanvas()?.applyTransform()
    }

    // MARK: - Keyboard

    private enum KeyCode {
        static let leftArrow: UInt16 = 123
        static let rightArrow: UInt16 = 124
        static let space: UInt16 = 49
        static let pageUp: UInt16 = 116
        static let pageDown: UInt16 = 121
        static let home: UInt16 = 115
        static let end: UInt16 = 119
        static let escape: UInt16 = 53
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let shift = event.modifierFlags.contains(.shift)
        let control = event.modifierFlags.contains(.control)

        switch event.keyCode {
        case KeyCode.rightArrow, KeyCode.pageDown:
            controller.next()
            return true
        case KeyCode.leftArrow, KeyCode.pageUp:
            controller.previous()
            return true
        case KeyCode.space:
            shift ? controller.previous() : controller.next()
            return true
        case KeyCode.home:
            controller.first()
            return true
        case KeyCode.end:
            controller.last()
            return true
        case KeyCode.escape:
            handleEscape()
            return true
        default:
            break
        }

        // Цифры 0…5 — рейтинг, P и X — отбор. Все без модификаторов, чтобы
        // отбраковка шла одной рукой.
        if let characters = event.charactersIgnoringModifiers?.lowercased(), !control {
            if let digit = Int(characters), (0 ... 5).contains(digit) {
                controller.setRating(digit)
                return true
            }
            switch characters {
            case "p", "з": controller.setFlag(.picked); return true
            case "x", "ч": controller.setFlag(.rejected); return true
            case "u", "г": controller.setFlag(nil); return true
            default: break
            }
        }

        // `F` toggles fullscreen; `Ctrl+F` is handled by the menu equivalent.
        if !control, event.charactersIgnoringModifiers?.lowercased() == "f" {
            window?.toggleFullScreen(nil)
            return true
        }
        return false
    }

    private func handleEscape() {
        if window?.styleMask.contains(.fullScreen) == true {
            window?.toggleFullScreen(nil)
        } else {
            window?.performClose(nil)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidEnterFullScreen(_ notification: Notification) {
        findCanvas()?.showCursorAndScheduleHide()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        findCanvas()?.cancelCursorHiding()
    }

    func windowWillClose(_ notification: Notification) {
        findCanvas()?.cancelCursorHiding()
        browser?.close()
        browser = nil
        AppDelegate.shared?.viewerWindowWillClose(self)
    }

    private func findCanvas() -> ImageCanvasNSView? {
        func search(_ view: NSView) -> ImageCanvasNSView? {
            if let canvas = view as? ImageCanvasNSView { return canvas }
            for subview in view.subviews {
                if let found = search(subview) { return found }
            }
            return nil
        }
        guard let contentView = window?.contentView else { return nil }
        return search(contentView)
    }
}
