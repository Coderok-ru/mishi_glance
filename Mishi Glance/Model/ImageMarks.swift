//
//  ImageMarks.swift
//  Mishi Glance
//
//  Рейтинги и флаги отбраковки. Хранятся в расширенных атрибутах файла,
//  а не внутри снимка: пересохранять чужие фотографии ради пометки —
//  плохая идея, а xattr переживает копирование и виден Spotlight.
//

import Foundation

enum PickFlag: String, Sendable {
    case picked
    case rejected
}

enum ImageMarks {
    /// Стандартный ключ Spotlight: эту же оценку показывает Finder.
    private static let ratingKey = "com.apple.metadata:kMDItemStarRating"
    private static let flagKey = "ru.coderok.mishiglance.pick"

    // MARK: - Рейтинг

    static func rating(of url: URL) -> Int {
        guard let data = readAttribute(ratingKey, at: url) else { return 0 }
        if let number = try? PropertyListSerialization.propertyList(
            from: data, format: nil) as? NSNumber {
            return min(max(number.intValue, 0), 5)
        }
        // На случай, если кто-то записал обычной строкой.
        return Int(String(decoding: data, as: UTF8.self).trimmingCharacters(
            in: .whitespacesAndNewlines)) ?? 0
    }

    @discardableResult
    static func setRating(_ value: Int, at url: URL) -> Bool {
        let clamped = min(max(value, 0), 5)
        guard clamped > 0 else { return removeAttribute(ratingKey, at: url) }
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: NSNumber(value: clamped), format: .binary, options: 0)
        else { return false }
        return writeAttribute(ratingKey, data: data, at: url)
    }

    // MARK: - Флаг отбора

    static func flag(of url: URL) -> PickFlag? {
        guard let data = readAttribute(flagKey, at: url) else { return nil }
        return PickFlag(rawValue: String(decoding: data, as: UTF8.self))
    }

    @discardableResult
    static func setFlag(_ flag: PickFlag?, at url: URL) -> Bool {
        guard let flag else { return removeAttribute(flagKey, at: url) }
        return writeAttribute(flagKey, data: Data(flag.rawValue.utf8), at: url)
    }

    // MARK: - Работа с xattr

    private static func readAttribute(_ name: String, at url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = Data(count: size)
            let read = buffer.withUnsafeMutableBytes {
                getxattr(path, name, $0.baseAddress, size, 0, 0)
            }
            return read > 0 ? buffer : nil
        }
    }

    private static func writeAttribute(_ name: String, data: Data, at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return data.withUnsafeBytes {
                setxattr(path, name, $0.baseAddress, data.count, 0, 0) == 0
            }
        }
    }

    private static func removeAttribute(_ name: String, at url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            // ENOATTR — атрибута и не было, это не ошибка.
            return removexattr(path, name, 0) == 0 || errno == ENOATTR
        }
    }
}
