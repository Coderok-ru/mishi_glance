//
//  ImageExporter.swift
//  Mishi Glance
//
//  Пересохранение в другой формат. Главный сценарий — HEIC с айфона в
//  JPEG, который открывается везде.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case jpeg
    case png
    case heic
    case tiff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: "JPEG"
        case .png: "PNG"
        case .heic: "HEIC"
        case .tiff: "TIFF"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: "jpg"
        case .png: "png"
        case .heic: "heic"
        case .tiff: "tiff"
        }
    }

    var type: UTType {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .heic: UTType("public.heic") ?? .jpeg
        case .tiff: .tiff
        }
    }

    /// PNG и TIFF без потерь — ползунок качества для них не имеет смысла.
    var supportsQuality: Bool {
        self == .jpeg || self == .heic
    }
}

enum ExportError: LocalizedError {
    case unreadable(String)
    case unwritable(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unreadable(let name): "Не удалось прочитать «\(name)»"
        case .unwritable(let name): "Не удалось записать «\(name)»"
        case .cancelled: "Экспорт отменён"
        }
    }
}

struct ExportOptions: Sendable {
    var format: ExportFormat = .jpeg
    /// 0…1, применяется только к форматам с потерями.
    var quality: Double = 0.9
    /// Ограничение длинной стороны в пикселях. nil — не уменьшать.
    var maxPixelSize: Int?
    /// Переносить ли EXIF, GPS и авторство в новый файл.
    var keepMetadata = true
}

enum ImageExporter {
    /// Пересохраняет один файл. Возвращает адрес созданного файла.
    static func export(source: URL, to directory: URL,
                       options: ExportOptions) throws -> URL {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { throw ExportError.unreadable(source.lastPathComponent) }

        // Через thumbnail-путь, потому что он же применяет EXIF-поворот:
        // иначе повёрнутые снимки с телефона легли бы набок.
        var decodeOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        let full = ImageDecoder.orientedPixelSize(source: imageSource)
        let longest = Int(max(full.width, full.height))
        decodeOptions[kCGImageSourceThumbnailMaxPixelSize] =
            min(options.maxPixelSize ?? longest, longest)

        guard let image = CGImageSourceCreateThumbnailAtIndex(
            imageSource, 0, decodeOptions as CFDictionary)
        else { throw ExportError.unreadable(source.lastPathComponent) }

        let destination = uniqueURL(in: directory,
                                    stem: source.deletingPathExtension().lastPathComponent,
                                    ext: options.format.fileExtension)

        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, options.format.type.identifier as CFString, 1, nil)
        else { throw ExportError.unwritable(destination.lastPathComponent) }

        var properties: [CFString: Any] = [:]
        if options.keepMetadata,
           let original = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil)
            as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary,
                        kCGImagePropertyTIFFDictionary, kCGImagePropertyIPTCDictionary] {
                if let value = original[key] { properties[key] = value }
            }
            // Поворот уже применён к пикселям — оставлять старый флаг нельзя,
            // иначе изображение повернётся второй раз.
            properties[kCGImagePropertyOrientation] = 1
        }
        if options.format.supportsQuality {
            properties[kCGImageDestinationLossyCompressionQuality] = options.quality
        }

        CGImageDestinationAddImage(output, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(output) else {
            throw ExportError.unwritable(destination.lastPathComponent)
        }
        return destination
    }

    /// Пересохраняет пачку файлов, сообщая о продвижении.
    /// Возвращает созданные файлы и имена тех, что не поддались.
    static func exportBatch(sources: [URL], to directory: URL, options: ExportOptions,
                            progress: @Sendable (Int, Int) -> Void)
        -> (written: [URL], failed: [String]) {
        var written: [URL] = []
        var failed: [String] = []
        for (index, source) in sources.enumerated() {
            do {
                written.append(try export(source: source, to: directory, options: options))
            } catch {
                failed.append(source.lastPathComponent)
            }
            progress(index + 1, sources.count)
        }
        return (written, failed)
    }

    /// Не затираем существующие файлы: добавляем номер, как это делает Finder.
    private static func uniqueURL(in directory: URL, stem: String, ext: String) -> URL {
        var candidate = directory.appendingPathComponent("\(stem).\(ext)")
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(stem) \(counter).\(ext)")
            counter += 1
        }
        return candidate
    }
}
