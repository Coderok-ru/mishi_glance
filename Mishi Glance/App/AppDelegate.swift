//
//  AppDelegate.swift
//  Mishi Glance
//
//  Application entry point: file opening, window lifecycle and the main menu.
//  Menu actions use a nil target so they travel the responder chain and land
//  here, where they are forwarded to the frontmost viewer.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static private(set) var shared: AppDelegate?

    private var viewerControllers: [ViewerWindowController] = []
    private var settingsWindow: NSWindow?
    private var aboutWindow: NSWindow?
    private var openWithMenu: NSMenu?

    // MARK: - Lifecycle

    /// Runs before the open-documents Apple Event, unlike didFinishLaunching,
    /// so preferences are registered before any folder is scanned.
    func applicationWillFinishLaunching(_ notification: Notification) {
        Self.shared = self
        AppSettings.registerDefaults()
        NSApp.mainMenu = buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let path = commandLineImagePath() {
            openFiles([URL(fileURLWithPath: path)])
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        AppSettings.quitOnLastWindowClose
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppSettings.lastSessionURLs = viewerControllers.compactMap { $0.controller.folder.current?.url }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openFiles(urls)
    }

    /// Called only when the app launches without any document.
    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        if AppSettings.restoreSession {
            let urls = AppSettings.lastSessionURLs
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            if !urls.isEmpty {
                urls.forEach { openFiles([$0]) }
                return true
            }
        }
        presentEmptyViewer()
        return true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            presentEmptyViewer()
        }
        return true
    }

    private func commandLineImagePath() -> String? {
        CommandLine.arguments
            .dropFirst()
            .first { !$0.hasPrefix("-") && FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Windows

    /// Shows the first file and navigates its whole folder, per the spec.
    /// A folder already on screen is reused instead of opening a second window.
    private func openFiles(_ urls: [URL]) {
        guard let url = urls.first else { return }
        let folder = ((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false)
            ? url
            : url.deletingLastPathComponent()

        if let existing = viewerControllers.first(where: { $0.controller.folder.folderURL == folder }) {
            existing.open(url: url)
            return
        }
        if !AppSettings.separateWindows,
           let front = viewerControllers.first(where: { $0.window === NSApp.keyWindow }) ?? viewerControllers.first {
            front.open(url: url)
            return
        }
        makeViewer().open(url: url)
    }

    private func presentEmptyViewer() {
        if let idle = viewerControllers.first(where: { $0.controller.folder.folderURL == nil }) {
            idle.showEmpty()
            return
        }
        makeViewer().showEmpty()
    }

    @discardableResult
    private func makeViewer() -> ViewerWindowController {
        let controller = ViewerWindowController()
        viewerControllers.append(controller)
        return controller
    }

    func viewerWindowWillClose(_ controller: ViewerWindowController) {
        viewerControllers.removeAll { $0 === controller }
    }

    private var activeViewer: ViewerController? {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow,
           let controller = viewerControllers.first(where: { $0.window === window }) {
            return controller.controller
        }
        return viewerControllers.first?.controller
    }

    // MARK: - File actions

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.prompt = "Открыть"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        openFiles([url])
    }

    @objc func revealInFinder(_ sender: Any?) { activeViewer?.revealInFinder() }
    @objc func shareImage(_ sender: Any?) { activeViewer?.share() }
    @objc func openInEditor(_ sender: Any?) { activeViewer?.openInExternalEditor() }
    @objc func toggleBrowserWindow(_ sender: Any?) { activeViewer?.toggleBrowser() }
    @objc func moveToTrash(_ sender: Any?) { activeViewer?.moveCurrentToTrash() }
    @objc func copyImage(_ sender: Any?) { activeViewer?.copyToPasteboard() }

    @objc private func openWithApplication(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        activeViewer?.open(with: url)
    }

    // MARK: - Navigation

    @objc func goNextImage(_ sender: Any?) { activeViewer?.next() }
    @objc func goPreviousImage(_ sender: Any?) { activeViewer?.previous() }
    @objc func goFirstImage(_ sender: Any?) { activeViewer?.first() }
    @objc func goLastImage(_ sender: Any?) { activeViewer?.last() }

    // MARK: - View

    @objc func zoomToFit(_ sender: Any?) { activeViewer?.applyFit() }

    @objc func zoomToActualSize(_ sender: Any?) {
        activeViewer?.zoomToActualSize()
        Task { await activeViewer?.ensureFullResolutionIfNeeded() }
    }

    @objc func zoomImageIn(_ sender: Any?) {
        activeViewer?.zoomIn()
        Task { await activeViewer?.ensureFullResolutionIfNeeded() }
    }

    @objc func zoomImageOut(_ sender: Any?) { activeViewer?.zoomOut() }

    @objc func rotateClockwise(_ sender: Any?) { activeViewer?.rotate(clockwise: true) }
    @objc func rotateCounterClockwise(_ sender: Any?) { activeViewer?.rotate(clockwise: false) }

    @objc func toggleInfoPanel(_ sender: Any?) {
        guard let viewer = activeViewer else { return }
        viewer.showInfoPanel.toggle()
    }

    @objc private func setSortOrder(_ sender: NSMenuItem) {
        guard let order = ImageSortOrder(rawValue: sender.representedObject as? String ?? "") else { return }
        AppSettings.sortOrder = order
        activeViewer?.setSortOrder(order)
    }

    @objc private func setSortDirection(_ sender: NSMenuItem) {
        guard let ascending = sender.representedObject as? Bool else { return }
        AppSettings.sortAscending = ascending
        activeViewer?.setSortAscending(ascending)
    }

    // MARK: - About

    @objc func showAbout(_ sender: Any?) {
        if let aboutWindow {
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(contentViewController: NSHostingController(rootView: AboutView()))
        window.title = "О программе"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    // MARK: - Settings

    @objc func showSettings(_ sender: Any?) {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let hosting = NSHostingController(rootView: SettingsView())
        let window = NSWindow(contentViewController: hosting)
        window.title = "Настройки"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    // MARK: - Menu validation

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let viewer = activeViewer
        let hasImage = viewer?.displayed != nil
        let hasFile = viewer?.folder.current != nil
        let manyImages = (viewer?.folder.count ?? 0) > 1

        switch menuItem.action {
        case #selector(goNextImage), #selector(goPreviousImage),
             #selector(goFirstImage), #selector(goLastImage):
            return manyImages
        case #selector(revealInFinder), #selector(moveToTrash), #selector(copyImage),
             #selector(shareImage), #selector(openInEditor), #selector(toggleBrowserWindow):
            return hasFile
        case #selector(zoomToFit), #selector(zoomToActualSize),
             #selector(zoomImageIn), #selector(zoomImageOut),
             #selector(rotateClockwise), #selector(rotateCounterClockwise),
             #selector(toggleInfoPanel):
            return hasImage
        case #selector(setSortOrder(_:)):
            menuItem.state = (menuItem.representedObject as? String) == AppSettings.sortOrder.rawValue ? .on : .off
            return hasFile
        case #selector(setSortDirection(_:)):
            let ascending = menuItem.representedObject as? Bool ?? true
            menuItem.title = ascending
                ? AppSettings.sortOrder.ascendingLabel
                : AppSettings.sortOrder.descendingLabel
            menuItem.state = (ascending == AppSettings.sortAscending) ? .on : .off
            return hasFile
        default:
            return true
        }
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        // Application
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "О программе Mishi Glance",
                        action: #selector(showAbout(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Настройки…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())

        let servicesItem = appMenu.addItem(withTitle: "Службы", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu()
        servicesItem.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть Mishi Glance", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Скрыть остальные",
                                         action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Показать все",
                        action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Завершить Mishi Glance",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(appMenu, titled: "Mishi Glance", to: mainMenu)

        // File
        let fileMenu = NSMenu(title: "Файл")
        fileMenu.addItem(withTitle: "Открыть…", action: #selector(openDocument(_:)), keyEquivalent: "o")

        let openWithItem = fileMenu.addItem(withTitle: "Открыть в программе", action: nil, keyEquivalent: "")
        let openWith = NSMenu(title: "Открыть в программе")
        openWith.delegate = self
        openWithItem.submenu = openWith
        openWithMenu = openWith

        fileMenu.addItem(.separator())
        let reveal = fileMenu.addItem(withTitle: "Показать в Finder",
                                      action: #selector(revealInFinder(_:)), keyEquivalent: "r")
        reveal.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Поделиться…", action: #selector(shareImage(_:)), keyEquivalent: "")
        let editor = fileMenu.addItem(withTitle: "Открыть в редакторе",
                                      action: #selector(openInEditor(_:)), keyEquivalent: "e")
        editor.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        let trash = fileMenu.addItem(withTitle: "Переместить в Корзину",
                                     action: #selector(moveToTrash(_:)), keyEquivalent: "\u{8}")
        trash.keyEquivalentModifierMask = [.command]
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Закрыть окно",
                         action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(fileMenu, titled: "Файл", to: mainMenu)

        // Edit
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Копировать", action: #selector(copyImage(_:)), keyEquivalent: "c")
        addSubmenu(editMenu, titled: "Правка", to: mainMenu)

        // View
        let viewMenu = NSMenu(title: "Вид")
        viewMenu.addItem(withTitle: "Вписать в окно", action: #selector(zoomToFit(_:)), keyEquivalent: "0")
        viewMenu.addItem(withTitle: "Реальный размер", action: #selector(zoomToActualSize(_:)), keyEquivalent: "1")
        viewMenu.addItem(withTitle: "Увеличить", action: #selector(zoomImageIn(_:)), keyEquivalent: "+")
        viewMenu.addItem(withTitle: "Уменьшить", action: #selector(zoomImageOut(_:)), keyEquivalent: "-")
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Повернуть вправо", action: #selector(rotateClockwise(_:)), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Повернуть влево", action: #selector(rotateCounterClockwise(_:)), keyEquivalent: "l")
        viewMenu.addItem(.separator())

        let sortItem = viewMenu.addItem(withTitle: "Сортировка", action: nil, keyEquivalent: "")
        let sortMenu = NSMenu(title: "Сортировка")
        for order in ImageSortOrder.allCases {
            let item = sortMenu.addItem(withTitle: order.title,
                                        action: #selector(setSortOrder(_:)), keyEquivalent: "")
            item.representedObject = order.rawValue
        }
        sortMenu.addItem(.separator())
        let ascending = sortMenu.addItem(withTitle: "По возрастанию",
                                         action: #selector(setSortDirection(_:)), keyEquivalent: "")
        ascending.representedObject = true
        let descending = sortMenu.addItem(withTitle: "По убыванию",
                                          action: #selector(setSortDirection(_:)), keyEquivalent: "")
        descending.representedObject = false
        sortItem.submenu = sortMenu

        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Изображения в папке",
                         action: #selector(toggleBrowserWindow(_:)), keyEquivalent: "b")
        viewMenu.addItem(withTitle: "Информация", action: #selector(toggleInfoPanel(_:)), keyEquivalent: "i")
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Во весь экран",
                                          action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        addSubmenu(viewMenu, titled: "Вид", to: mainMenu)

        // Go
        let goMenu = NSMenu(title: "Переход")
        addNavigationItem(to: goMenu, title: "Следующее изображение",
                          action: #selector(goNextImage(_:)), key: NSRightArrowFunctionKey)
        addNavigationItem(to: goMenu, title: "Предыдущее изображение",
                          action: #selector(goPreviousImage(_:)), key: NSLeftArrowFunctionKey)
        goMenu.addItem(.separator())
        addNavigationItem(to: goMenu, title: "Первое изображение",
                          action: #selector(goFirstImage(_:)), key: NSHomeFunctionKey)
        addNavigationItem(to: goMenu, title: "Последнее изображение",
                          action: #selector(goLastImage(_:)), key: NSEndFunctionKey)
        addSubmenu(goMenu, titled: "Переход", to: mainMenu)

        // Window
        let windowMenu = NSMenu(title: "Окно")
        windowMenu.addItem(withTitle: "Свернуть",
                           action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Масштаб", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowMenu.addItem(.separator())
        addSubmenu(windowMenu, titled: "Окно", to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private func addSubmenu(_ menu: NSMenu, titled title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        menu.title = title
        mainMenu.addItem(item)
    }

    /// Navigation keys carry no modifier, matching the spec's arrow/Home/End
    /// bindings. The viewer window also handles Space and Page keys directly.
    private func addNavigationItem(to menu: NSMenu, title: String, action: Selector, key: Int) {
        let item = menu.addItem(withTitle: title, action: action,
                                keyEquivalent: String(UnicodeScalar(key)!))
        item.keyEquivalentModifierMask = []
    }
}

// MARK: - Open With submenu

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === openWithMenu else { return }
        menu.removeAllItems()

        let candidates = activeViewer?.openWithCandidates() ?? []
        guard !candidates.isEmpty else {
            let empty = menu.addItem(withTitle: "Нет доступных программ", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            return
        }

        let workspace = NSWorkspace.shared
        for application in candidates {
            let name = FileManager.default.displayName(atPath: application.path)
            let item = menu.addItem(withTitle: name,
                                    action: #selector(openWithApplication(_:)), keyEquivalent: "")
            item.representedObject = application
            item.target = self
            let icon = workspace.icon(forFile: application.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
    }
}
