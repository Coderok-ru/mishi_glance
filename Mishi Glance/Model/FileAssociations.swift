//
//  FileAssociations.swift
//  Mishi Glance
//
//  Reads and sets the system's default application per image type, so the
//  Settings pane can make Mishi Glance the default viewer in one click.
//

import AppKit
import UniformTypeIdentifiers

struct ImageFormat: Identifiable, Sendable {
    let name: String
    let extensions: String
    /// Uniform type identifier, kept as a string so unsupported types on
    /// older systems simply resolve to nil instead of failing to build.
    let identifier: String

    var id: String { identifier }
    var type: UTType? { UTType(identifier) }

    static let all: [ImageFormat] = [
        ImageFormat(name: "PNG", extensions: ".png", identifier: "public.png"),
        ImageFormat(name: "JPEG", extensions: ".jpg, .jpeg, .jpe", identifier: "public.jpeg"),
        ImageFormat(name: "HEIC", extensions: ".heic", identifier: "public.heic"),
        ImageFormat(name: "HEIF", extensions: ".heif, .hif", identifier: "public.heif"),
        ImageFormat(name: "WebP", extensions: ".webp", identifier: "org.webmproject.webp"),
        ImageFormat(name: "AVIF", extensions: ".avif", identifier: "public.avif"),
        ImageFormat(name: "GIF", extensions: ".gif", identifier: "com.compuserve.gif"),
        ImageFormat(name: "TIFF", extensions: ".tiff, .tif", identifier: "public.tiff"),
        ImageFormat(name: "BMP", extensions: ".bmp, .dib", identifier: "com.microsoft.bmp"),
        ImageFormat(name: "ICO", extensions: ".ico", identifier: "com.microsoft.ico"),
        ImageFormat(name: "SVG", extensions: ".svg, .svgz", identifier: "public.svg-image"),
        ImageFormat(name: "PSD", extensions: ".psd", identifier: "com.adobe.photoshop-image"),
        ImageFormat(name: "DNG", extensions: ".dng", identifier: "com.adobe.raw-image"),
        ImageFormat(name: "CR2", extensions: ".cr2 · Canon", identifier: "com.canon.cr2-raw-image"),
        ImageFormat(name: "CR3", extensions: ".cr3 · Canon", identifier: "com.canon.cr3-raw-image"),
        ImageFormat(name: "NEF", extensions: ".nef · Nikon", identifier: "com.nikon.raw-image"),
        ImageFormat(name: "ARW", extensions: ".arw · Sony", identifier: "com.sony.arw-raw-image"),
        ImageFormat(name: "RAF", extensions: ".raf · Fujifilm", identifier: "com.fuji.raw-image"),
        ImageFormat(name: "ORF", extensions: ".orf · Olympus", identifier: "com.olympus.raw-image"),
        ImageFormat(name: "RW2", extensions: ".rw2 · Panasonic", identifier: "com.panasonic.rw2-raw-image"),
    ]
}

@MainActor
enum FileAssociations {
    static var ownBundleURL: URL { Bundle.main.bundleURL }

    /// The application currently registered to open `format`, if any.
    static func currentHandler(for format: ImageFormat) -> (name: String, icon: NSImage, isSelf: Bool)? {
        guard let type = format.type,
              let url = NSWorkspace.shared.urlForApplication(toOpen: type)
        else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return (FileManager.default.displayName(atPath: url.path),
                icon,
                url.standardizedFileURL == ownBundleURL.standardizedFileURL)
    }

    /// Makes this app the default viewer for `format`.
    /// macOS may ask the user to confirm the change.
    static func makeDefault(for format: ImageFormat) async throws {
        guard let type = format.type else {
            throw AssociationError.unsupportedType(format.name)
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.setDefaultApplication(at: ownBundleURL, toOpen: type) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Returns the formats that could not be claimed.
    static func makeDefaultForAll() async -> [String] {
        var failed: [String] = []
        for format in ImageFormat.all {
            do {
                try await makeDefault(for: format)
            } catch {
                failed.append(format.name)
            }
        }
        return failed
    }

    enum AssociationError: LocalizedError {
        case unsupportedType(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedType(let name):
                "Система не знает тип «\(name)»"
            }
        }
    }
}
