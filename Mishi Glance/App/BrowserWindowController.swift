//
//  BrowserWindowController.swift
//  Mishi Glance
//
//  Companion window listing every image in the viewer's folder as a grid.
//

import AppKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    private let controller: ViewerController

    init(controller: ViewerController) {
        self.controller = controller

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Список файлов"
        window.minSize = NSSize(width: 320, height: 280)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("MishiGlanceBrowser")

        super.init(window: window)

        window.delegate = self

        // NSHostingView collapses to its intrinsic size when handed straight to
        // contentView; give it the full content rect and let it follow resizes.
        let host = NSHostingView(rootView: BrowserView(controller: controller))
        host.frame = CGRect(origin: .zero, size: window.contentLayoutRect.size)
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.setContentSize(NSSize(width: 460, height: 760))
        window.center()
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The count lives in the view's own header, so the title stays short.
    func updateTitle() {
        window?.title = "Список файлов"
    }

    var isVisible: Bool { window?.isVisible ?? false }

    func toggle() {
        if isVisible {
            window?.performClose(nil)
        } else {
            updateTitle()
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}
