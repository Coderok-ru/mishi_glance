//
//  ImageLoader.swift
//  Mishi Glance
//
//  Decode cache. Guarantees a single in-flight decode per (file, size) and
//  keeps an LRU bounded by both entry count and a user-configurable byte
//  budget. Shared across windows so the same file is never decoded twice.
//

import CoreGraphics
import Foundation

actor ImageLoader {
    /// Full-size decodes for the viewer. Budget follows the Settings slider.
    static let shared = ImageLoader(
        maxEntries: 64,
        budget: { AppSettings.preloadBufferBytes }
    )

    /// Small previews for the folder browser, kept separate so browsing a
    /// large folder cannot evict the images the viewer is showing.
    static let thumbnails = ImageLoader(
        maxEntries: 600,
        budget: { 96 * 1024 * 1024 }
    )

    struct Statistics: Sendable {
        let bytes: Int
        let count: Int
        let budget: Int
    }

    /// `maxPixel == 0` means full resolution.
    private struct Key: Hashable {
        let url: URL
        let maxPixel: Int
    }

    private let maxEntries: Int
    private let budget: @Sendable () -> Int

    private var cache: [Key: DecodedImage] = [:]
    /// Least-recently-used first.
    private var lru: [Key] = []
    private var cachedBytes = 0
    private var inFlight: [Key: Task<DecodedImage?, Never>] = [:]

    private init(maxEntries: Int, budget: @escaping @Sendable () -> Int) {
        self.maxEntries = maxEntries
        self.budget = budget
    }

    // MARK: - Loading

    /// Returns a decoded frame, reusing the cache and coalescing concurrent
    /// requests for the same key.
    func image(for url: URL, maxPixel: Int) async -> DecodedImage? {
        let key = Key(url: url, maxPixel: maxPixel)

        if let hit = cache[key] {
            touch(key)
            return hit
        }
        // A full-resolution entry already satisfies any downscaled request.
        if maxPixel != 0, let full = cache[Key(url: url, maxPixel: 0)] {
            touch(Key(url: url, maxPixel: 0))
            return full
        }
        if let running = inFlight[key] {
            return await running.value
        }

        let task = Task.detached(priority: .userInitiated) {
            ImageDecoder.decode(url: url, maxPixelSize: maxPixel == 0 ? nil : maxPixel)
        }
        inFlight[key] = task
        let decoded = await task.value
        inFlight[key] = nil

        if let decoded {
            store(key, decoded)
        }
        return decoded
    }

    /// Warms the cache for neighbouring files without blocking the caller.
    func prefetch(urls: [URL], maxPixel: Int) {
        for url in urls {
            let key = Key(url: url, maxPixel: maxPixel)
            guard cache[key] == nil,
                  cache[Key(url: url, maxPixel: 0)] == nil,
                  inFlight[key] == nil
            else { continue }

            let task = Task.detached(priority: .utility) {
                ImageDecoder.decode(url: url, maxPixelSize: maxPixel == 0 ? nil : maxPixel)
            }
            inFlight[key] = task
            Task {
                let decoded = await task.value
                self.finishPrefetch(key: key, decoded: decoded)
            }
        }
    }

    private func finishPrefetch(key: Key, decoded: DecodedImage?) {
        inFlight[key] = nil
        if let decoded {
            store(key, decoded)
        }
    }

    // MARK: - Maintenance

    func statistics() -> Statistics {
        Statistics(bytes: cachedBytes, count: cache.count, budget: budget())
    }

    /// Drops every variant of a file — used when the folder watcher reports
    /// that it changed on disk.
    func invalidate(url: URL) {
        for key in cache.keys where key.url == url {
            remove(key)
        }
    }

    func clear() {
        cache.removeAll()
        lru.removeAll()
        cachedBytes = 0
    }

    /// Re-applies the budget after the user changes it in Settings.
    func applyBudget() {
        evictIfNeeded(keeping: nil)
    }

    private func store(_ key: Key, _ image: DecodedImage) {
        if cache[key] != nil {
            remove(key)
        }
        cache[key] = image
        lru.append(key)
        cachedBytes += image.byteCount
        evictIfNeeded(keeping: key)
    }

    private func touch(_ key: Key) {
        guard let index = lru.firstIndex(of: key) else { return }
        lru.remove(at: index)
        lru.append(key)
    }

    private func remove(_ key: Key) {
        guard let image = cache.removeValue(forKey: key) else { return }
        cachedBytes -= image.byteCount
        if let index = lru.firstIndex(of: key) {
            lru.remove(at: index)
        }
    }

    private func evictIfNeeded(keeping protected: Key?) {
        let limit = budget()
        while lru.count > maxEntries || cachedBytes > limit {
            guard let oldest = lru.first, oldest != protected else { break }
            remove(oldest)
        }
    }
}
