//
//  AppSettings.swift
//  Mishi Glance
//
//  User preferences backed by UserDefaults. Views read them through
//  @AppStorage; the model layer reads them through the static accessors.
//

import AppKit
import SwiftUI

/// Mirrors the columns Finder can sort a folder by, so arrow-key order can
/// be made to match whatever the user sees in the Finder window.
enum ImageSortOrder: String, CaseIterable, Identifiable, Sendable {
    case name
    case dateModified
    case dateCreated
    case dateAdded
    case fileSize
    case kind

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: "Имя"
        case .dateModified: "Дата изменения"
        case .dateCreated: "Дата создания"
        case .dateAdded: "Дата добавления"
        case .fileSize: "Размер"
        case .kind: "Вид"
        }
    }

    /// Wording for the direction toggle, which flips meaning per column
    /// exactly as Finder's does.
    var ascendingLabel: String {
        switch self {
        case .name, .kind: "А → Я"
        case .dateModified, .dateCreated, .dateAdded: "Сначала старые"
        case .fileSize: "Сначала мелкие"
        }
    }

    var descendingLabel: String {
        switch self {
        case .name, .kind: "Я → А"
        case .dateModified, .dateCreated, .dateAdded: "Сначала новые"
        case .fileSize: "Сначала крупные"
        }
    }
}

enum ViewerBackground: String, CaseIterable, Identifiable, Sendable {
    case black
    case darkGray

    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: "Чёрный"
        case .darkGray: "Тёмно-серый"
        }
    }

    var nsColor: NSColor {
        switch self {
        case .black: .black
        case .darkGray: NSColor(white: 0.13, alpha: 1)
        }
    }

    var color: Color { Color(nsColor: nsColor) }
}

/// Layout of the folder browser window.
enum BrowserViewMode: String, CaseIterable, Identifiable, Sendable {
    case list
    case grid

    var id: String { rawValue }
}

/// What to draw behind a PNG/HEIC that has an alpha channel.
enum TransparencyMode: String, CaseIterable, Identifiable, Sendable {
    case checkerboard
    case background
    case white
    case black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .checkerboard: "Шахматка"
        case .background: "Фон окна"
        case .white: "Белый"
        case .black: "Чёрный"
        }
    }
}

/// What a plain drag on the image does. Command inverts the choice.
enum DragBehavior: String, CaseIterable, Identifiable, Sendable {
    case pan
    case dragOut

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pan: "Панорамирование, ⌘+перетаскивание — вынести файл"
        case .dragOut: "Вынести файл, ⌘+перетаскивание — панорамирование"
        }
    }
}

enum SettingsKey {
    static let sortOrder = "sortOrder"
    static let sortAscending = "sortAscending"
    static let wrapAround = "wrapAround"
    static let allowUpscale = "allowUpscale"
    static let confirmDelete = "confirmDelete"
    static let rememberWindowFrame = "rememberWindowFrame"
    static let background = "background"

    static let separateWindows = "separateWindows"
    static let restoreSession = "restoreSession"
    static let quitOnLastWindowClose = "quitOnLastWindowClose"
    static let doubleClickActualSize = "doubleClickActualSize"
    static let smoothScaling = "smoothScaling"
    static let swipeNavigation = "swipeNavigation"
    static let dragBehavior = "dragBehavior"

    static let browserViewMode = "browserViewMode"
    static let transparencyMode = "transparencyMode"
    static let preloadBufferMB = "preloadBufferMB"
    static let externalEditorPath = "externalEditorPath"

    static let lastSessionURLs = "lastSessionURLs"
}

enum AppSettings {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.sortOrder: ImageSortOrder.name.rawValue,
            SettingsKey.sortAscending: true,
            SettingsKey.wrapAround: true,
            SettingsKey.allowUpscale: false,
            SettingsKey.confirmDelete: true,
            SettingsKey.rememberWindowFrame: true,
            SettingsKey.background: ViewerBackground.black.rawValue,

            SettingsKey.separateWindows: true,
            SettingsKey.restoreSession: false,
            SettingsKey.quitOnLastWindowClose: false,
            SettingsKey.doubleClickActualSize: true,
            SettingsKey.smoothScaling: true,
            SettingsKey.swipeNavigation: true,
            SettingsKey.dragBehavior: DragBehavior.pan.rawValue,

            SettingsKey.browserViewMode: BrowserViewMode.list.rawValue,
            SettingsKey.transparencyMode: TransparencyMode.checkerboard.rawValue,
            SettingsKey.preloadBufferMB: 300,
        ])
    }

    private static func string(_ key: String) -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static var sortOrder: ImageSortOrder {
        get { ImageSortOrder(rawValue: string(SettingsKey.sortOrder)) ?? .name }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: SettingsKey.sortOrder) }
    }

    static var sortAscending: Bool {
        get { UserDefaults.standard.bool(forKey: SettingsKey.sortAscending) }
        set { UserDefaults.standard.set(newValue, forKey: SettingsKey.sortAscending) }
    }

    static var wrapAround: Bool { UserDefaults.standard.bool(forKey: SettingsKey.wrapAround) }
    static var allowUpscale: Bool { UserDefaults.standard.bool(forKey: SettingsKey.allowUpscale) }
    static var confirmDelete: Bool { UserDefaults.standard.bool(forKey: SettingsKey.confirmDelete) }
    static var rememberWindowFrame: Bool { UserDefaults.standard.bool(forKey: SettingsKey.rememberWindowFrame) }
    static var separateWindows: Bool { UserDefaults.standard.bool(forKey: SettingsKey.separateWindows) }
    static var restoreSession: Bool { UserDefaults.standard.bool(forKey: SettingsKey.restoreSession) }
    static var quitOnLastWindowClose: Bool { UserDefaults.standard.bool(forKey: SettingsKey.quitOnLastWindowClose) }
    static var doubleClickActualSize: Bool { UserDefaults.standard.bool(forKey: SettingsKey.doubleClickActualSize) }
    static var smoothScaling: Bool { UserDefaults.standard.bool(forKey: SettingsKey.smoothScaling) }
    static var swipeNavigation: Bool { UserDefaults.standard.bool(forKey: SettingsKey.swipeNavigation) }

    static var background: ViewerBackground {
        ViewerBackground(rawValue: string(SettingsKey.background)) ?? .black
    }

    static var browserViewMode: BrowserViewMode {
        BrowserViewMode(rawValue: string(SettingsKey.browserViewMode)) ?? .list
    }

    static var transparencyMode: TransparencyMode {
        TransparencyMode(rawValue: string(SettingsKey.transparencyMode)) ?? .checkerboard
    }

    static var dragBehavior: DragBehavior {
        DragBehavior(rawValue: string(SettingsKey.dragBehavior)) ?? .pan
    }

    /// Decode-cache budget in bytes.
    static var preloadBufferBytes: Int {
        let megabytes = UserDefaults.standard.integer(forKey: SettingsKey.preloadBufferMB)
        return max(megabytes, 64) * 1024 * 1024
    }

    /// The app used by "Открыть в редакторе". Falls back to Preview.
    static var externalEditorURL: URL? {
        let path = string(SettingsKey.externalEditorPath)
        if !path.isEmpty, FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview")
    }

    static var lastSessionURLs: [URL] {
        get {
            (UserDefaults.standard.array(forKey: SettingsKey.lastSessionURLs) as? [String] ?? [])
                .map { URL(fileURLWithPath: $0) }
        }
        set {
            UserDefaults.standard.set(newValue.map(\.path), forKey: SettingsKey.lastSessionURLs)
        }
    }
}

extension Notification.Name {
    /// Posted when a preference that viewers must react to immediately changes.
    static let viewerSettingsChanged = Notification.Name("MishiGlance.viewerSettingsChanged")
}
