//
//  FolderModel.swift
//  Mishi Glance
//
//  The list of images in one folder, the cursor into it, sorting, and the
//  filesystem watcher that keeps the list live. One instance per window.
//

import Foundation
import Observation

@MainActor
@Observable
final class FolderModel {
    private(set) var entries: [ImageEntry] = []
    private(set) var currentIndex: Int = 0
    private(set) var folderURL: URL?
    private(set) var isScanning = false
    private(set) var errorMessage: String?

    var sortOrder: ImageSortOrder = AppSettings.sortOrder {
        didSet {
            guard sortOrder != oldValue else { return }
            AppSettings.sortOrder = sortOrder
            resort()
        }
    }

    var sortAscending: Bool = AppSettings.sortAscending {
        didSet {
            guard sortAscending != oldValue else { return }
            AppSettings.sortAscending = sortAscending
            resort()
        }
    }

    /// Called after the list changes on disk so the viewer can refresh.
    var onFolderChanged: (() -> Void)?

    @ObservationIgnored private var watcher: DispatchSourceFileSystemObject?
    @ObservationIgnored private var watchedDescriptor: CInt = -1
    @ObservationIgnored private var rescanWorkItem: DispatchWorkItem?
    @ObservationIgnored private var scanGeneration = 0

    var current: ImageEntry? {
        entries.indices.contains(currentIndex) ? entries[currentIndex] : nil
    }

    var count: Int { entries.count }
    var isEmpty: Bool { entries.isEmpty }

    deinit {
        rescanWorkItem?.cancel()
        watcher?.cancel()
    }

    // MARK: - Loading

    /// Opens `url`. A file selects that file inside its folder; a folder opens
    /// at its first image.
    func open(url rawURL: URL) async {
        // Приводим путь к каноническому виду: Finder и командная строка могут
        // дать /var/..., тогда как contentsOfDirectory вернёт /private/var/...,
        // и открытый файл не нашёлся бы в собственном списке папки.
        let url = rawURL.resolvingSymlinksInPath().standardizedFileURL
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let folder = isDirectory ? url : url.deletingLastPathComponent()
        let selection = isDirectory ? nil : url

        folderURL = folder
        errorMessage = nil
        isScanning = true

        scanGeneration += 1
        let generation = scanGeneration
        let order = sortOrder
        let ascending = sortAscending

        let scanned = await Task.detached(priority: .userInitiated) {
            Self.scan(folder: folder, sortedBy: order, ascending: ascending)
        }.value

        guard generation == scanGeneration else { return }

        entries = scanned
        isScanning = false

        if let selection, let index = scanned.firstIndex(where: { $0.url == selection }) {
            currentIndex = index
        } else if let selection, ImageEntry(url: selection) == nil {
            // Opened something the system does not treat as an image.
            errorMessage = "Файл «\(selection.lastPathComponent)» не является изображением"
            currentIndex = 0
        } else {
            currentIndex = 0
        }

        if scanned.isEmpty, errorMessage == nil, isDirectory {
            errorMessage = "В папке нет изображений"
        }

        startWatching(folder)
    }

    nonisolated private static func scan(folder: URL, sortedBy order: ImageSortOrder,
                                        ascending: Bool) -> [ImageEntry] {
        let manager = FileManager.default
        guard let urls = try? manager.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(ImageEntry.resourceKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return [] }

        var result: [ImageEntry] = []
        result.reserveCapacity(urls.count)
        for url in urls {
            if let entry = ImageEntry(url: url) {
                result.append(entry)
            }
        }
        return sorted(result, by: order, ascending: ascending)
    }

    /// Reproduces Finder's ordering: the chosen column, natural-language name
    /// comparison as the tiebreaker, then the whole thing flipped for
    /// descending — which is what Finder's sort arrow does too.
    nonisolated private static func sorted(_ entries: [ImageEntry], by order: ImageSortOrder,
                                           ascending: Bool) -> [ImageEntry] {
        // localizedStandardCompare is Finder's Name column: case-insensitive
        // and number-aware, so "img2.jpg" sorts before "img10.jpg".
        func byName(_ lhs: ImageEntry, _ rhs: ImageEntry) -> Bool {
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        let result: [ImageEntry]
        switch order {
        case .name:
            result = entries.sorted(by: byName)
        case .kind:
            result = entries.sorted {
                let comparison = $0.kind.localizedStandardCompare($1.kind)
                return comparison == .orderedSame ? byName($0, $1) : comparison == .orderedAscending
            }
        case .dateModified:
            result = entries.sorted {
                $0.modificationDate == $1.modificationDate
                    ? byName($0, $1) : $0.modificationDate < $1.modificationDate
            }
        case .dateCreated:
            result = entries.sorted {
                $0.creationDate == $1.creationDate
                    ? byName($0, $1) : $0.creationDate < $1.creationDate
            }
        case .dateAdded:
            result = entries.sorted {
                $0.addedDate == $1.addedDate
                    ? byName($0, $1) : $0.addedDate < $1.addedDate
            }
        case .fileSize:
            result = entries.sorted {
                $0.fileSize == $1.fileSize ? byName($0, $1) : $0.fileSize < $1.fileSize
            }
        }
        return ascending ? result : result.reversed()
    }

    private func resort() {
        let anchor = current?.url
        entries = Self.sorted(entries, by: sortOrder, ascending: sortAscending)
        if let anchor, let index = entries.firstIndex(where: { $0.url == anchor }) {
            currentIndex = index
        } else {
            currentIndex = min(currentIndex, max(entries.count - 1, 0))
        }
        onFolderChanged?()
    }

    // MARK: - Navigation

    @discardableResult
    func goNext() -> Bool { advance(by: 1) }

    @discardableResult
    func goPrevious() -> Bool { advance(by: -1) }

    @discardableResult
    func goFirst() -> Bool {
        guard !entries.isEmpty, currentIndex != 0 else { return false }
        currentIndex = 0
        return true
    }

    @discardableResult
    func goLast() -> Bool {
        guard !entries.isEmpty, currentIndex != entries.count - 1 else { return false }
        currentIndex = entries.count - 1
        return true
    }

    func select(index: Int) {
        guard entries.indices.contains(index) else { return }
        currentIndex = index
    }

    private func advance(by step: Int) -> Bool {
        guard entries.count > 1 else { return false }
        let next = currentIndex + step
        if next < 0 || next >= entries.count {
            guard AppSettings.wrapAround else { return false }
            currentIndex = next < 0 ? entries.count - 1 : 0
        } else {
            currentIndex = next
        }
        return true
    }

    /// URLs to warm ahead of and behind the cursor.
    func neighbourURLs(radius: Int) -> [URL] {
        guard !entries.isEmpty else { return [] }
        var urls: [URL] = []
        for offset in 1...max(radius, 1) {
            for direction in [1, -1] {
                var index = currentIndex + offset * direction
                if AppSettings.wrapAround {
                    index = ((index % entries.count) + entries.count) % entries.count
                }
                guard entries.indices.contains(index), index != currentIndex else { continue }
                let url = entries[index].url
                if !urls.contains(url) {
                    urls.append(url)
                }
            }
        }
        return urls
    }

    // MARK: - Mutation

    /// Drops the current entry after it was trashed, leaving the cursor on the
    /// file that took its place.
    func removeCurrent() {
        guard entries.indices.contains(currentIndex) else { return }
        entries.remove(at: currentIndex)
        currentIndex = min(currentIndex, max(entries.count - 1, 0))
    }

    // MARK: - Folder watching

    private func startWatching(_ folder: URL) {
        stopWatching()

        let descriptor = Darwin.open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleRescan()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }

        watchedDescriptor = descriptor
        watcher = source
        source.resume()
    }

    private func stopWatching() {
        rescanWorkItem?.cancel()
        rescanWorkItem = nil
        watcher?.cancel()
        watcher = nil
        watchedDescriptor = -1
    }

    /// Directory writes arrive in bursts (a copy of 50 files fires many
    /// events); coalesce them into one rescan.
    private func scheduleRescan() {
        rescanWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            Task { await self.rescan() }
        }
        rescanWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func rescan() async {
        guard let folder = folderURL else { return }

        guard FileManager.default.fileExists(atPath: folder.path) else {
            entries = []
            currentIndex = 0
            errorMessage = "Папка недоступна"
            stopWatching()
            onFolderChanged?()
            return
        }

        scanGeneration += 1
        let generation = scanGeneration
        let order = sortOrder
        let ascending = sortAscending
        let anchor = current?.url
        let previousIndex = currentIndex

        let scanned = await Task.detached(priority: .utility) {
            Self.scan(folder: folder, sortedBy: order, ascending: ascending)
        }.value

        guard generation == scanGeneration else { return }
        guard scanned != entries else { return }

        entries = scanned
        if let anchor, let index = scanned.firstIndex(where: { $0.url == anchor }) {
            currentIndex = index
        } else {
            // The current file vanished — stay in place, which now shows the
            // file that followed it.
            currentIndex = min(previousIndex, max(scanned.count - 1, 0))
        }
        if !scanned.isEmpty {
            errorMessage = nil
        }
        onFolderChanged?()
    }
}
