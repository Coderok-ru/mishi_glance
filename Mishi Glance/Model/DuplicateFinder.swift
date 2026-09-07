//
//  DuplicateFinder.swift
//  Mishi Glance
//
//  Поиск повторов по перцептивному хешу: находит не только точные копии,
//  но и пережатые, уменьшенные и слегка изменённые версии того же кадра.
//

import CoreGraphics
import Foundation

struct DuplicateGroup: Identifiable, Sendable {
    let entries: [ImageEntry]
    var id: URL { entries[0].url }

    /// Сколько места освободится, если оставить один файл из группы.
    var reclaimableBytes: Int64 {
        entries.dropFirst().reduce(0) { $0 + $1.fileSize }
    }
}

enum DuplicateFinder {
    /// dHash: кадр сжимается до 9×8 серых пикселей, каждый бит — ответ на
    /// вопрос «сосед слева светлее?». Устойчив к масштабу и пережатию.
    static func perceptualHash(of url: URL) -> UInt64? {
        guard let decoded = ImageDecoder.decode(url: url, maxPixelSize: 64) else { return nil }
        let width = 9, height = 8
        var gray = [UInt8](repeating: 0, count: width * height)
        guard let context = gray.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(data: raw.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(),
                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        }) else { return nil }
        context.interpolationQuality = .medium
        context.draw(decoded.image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var hash: UInt64 = 0
        var bit = 0
        for row in 0 ..< height {
            for column in 0 ..< (width - 1) {
                let left = gray[row * width + column]
                let right = gray[row * width + column + 1]
                if left > right { hash |= (1 << UInt64(bit)) }
                bit += 1
            }
        }
        return hash
    }

    /// Число различающихся битов. 0 — кадры неразличимы для глаза.
    static func distance(_ lhs: UInt64, _ rhs: UInt64) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    /// Группирует похожие файлы. `threshold` — допустимое число различий,
    /// 0 ищет только неотличимые, 10 захватывает заметно изменённые.
    static func find(in entries: [ImageEntry], threshold: Int = 6,
                     progress: @Sendable (Int, Int) -> Void = { _, _ in })
        -> [DuplicateGroup] {
        var hashes: [(entry: ImageEntry, hash: UInt64)] = []
        for (index, entry) in entries.enumerated() {
            if let hash = perceptualHash(of: entry.url) {
                hashes.append((entry, hash))
            }
            progress(index + 1, entries.count)
        }

        var used = Set<Int>()
        var groups: [DuplicateGroup] = []
        for i in hashes.indices where !used.contains(i) {
            var members = [hashes[i].entry]
            for j in hashes.indices where j > i && !used.contains(j) {
                if distance(hashes[i].hash, hashes[j].hash) <= threshold {
                    members.append(hashes[j].entry)
                    used.insert(j)
                }
            }
            if members.count > 1 {
                used.insert(i)
                // Крупный файл первым: обычно это оригинал, его и оставляют.
                groups.append(DuplicateGroup(
                    entries: members.sorted { $0.fileSize > $1.fileSize }))
            }
        }
        return groups.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }
}
