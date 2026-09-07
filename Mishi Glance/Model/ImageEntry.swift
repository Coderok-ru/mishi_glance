//
//  ImageEntry.swift
//  Mishi Glance
//

import Foundation
import UniformTypeIdentifiers

/// One image file in the current folder, with the attributes needed for
/// sorting and the status overlay already resolved.
struct ImageEntry: Identifiable, Hashable, Sendable {
    let url: URL
    let fileSize: Int64
    let modificationDate: Date
    let creationDate: Date
    /// When the file landed in this folder — Finder's "Date Added".
    let addedDate: Date
    /// Localized type name, matching Finder's "Kind" column.
    let kind: String

    var id: URL { url }
    var name: String { url.lastPathComponent }

    static let resourceKeys: Set<URLResourceKey> = [
        .contentTypeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .creationDateKey,
        .addedToDirectoryDateKey,
        .localizedTypeDescriptionKey,
        .isRegularFileKey,
    ]

    /// Builds an entry if `url` is a regular file that the system recognises
    /// as an image. Returns nil for anything else.
    init?(url: URL) {
        guard let values = try? url.resourceValues(forKeys: Self.resourceKeys),
              values.isRegularFile == true,
              let type = values.contentType,
              type.conforms(to: .image)
        else { return nil }

        self.url = url.resolvingSymlinksInPath().standardizedFileURL
        self.fileSize = Int64(values.fileSize ?? 0)
        self.modificationDate = values.contentModificationDate ?? .distantPast
        self.creationDate = values.creationDate ?? .distantPast
        self.addedDate = values.addedToDirectoryDate ?? values.creationDate ?? .distantPast
        self.kind = values.localizedTypeDescription ?? type.localizedDescription ?? ""
    }
}

enum ByteFormat {
    nonisolated(unsafe) private static let formatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useKB, .useMB, .useGB]
        return f
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
