//
//  main.swift
//  Mishi Glance
//
//  Explicit AppKit bootstrap. `@main` on an NSApplicationDelegate does not
//  install the delegate here, which left AppKit falling back to
//  NSDocumentController and refusing every file the app was asked to open.
//

import AppKit

@MainActor
enum Bootstrap {
    /// NSApplication.delegate is weak, so the delegate needs an owner.
    private static var delegate: AppDelegate?

    static func run() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        delegate = appDelegate
        application.delegate = appDelegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

// Top-level code in main.swift already runs on the main thread.
MainActor.assumeIsolated { Bootstrap.run() }
