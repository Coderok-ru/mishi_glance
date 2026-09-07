//
//  ImageDecoder.swift
//  Mishi Glance
//
//  CGImageSource-based decoding. Everything here is pure and thread-safe so
//  it can run off the main actor.
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded frame plus the full pixel dimensions of the file it came from.
/// CGImage is immutable and safe to hand between threads.
struct DecodedImage: @unchecked Sendable {
    let image: CGImage
    /// Full size of the source in pixels, after EXIF orientation is applied.
    let pixelSize: CGSize
    /// True when `image` carries the source's full resolution.
    let isFullResolution: Bool

    var byteCount: Int { image.height * image.bytesPerRow }

    /// True when the file can show through — decides whether the viewer
    /// paints a checkerboard behind it.
    var hasAlpha: Bool {
        switch image.alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast: true
        default: false
        }
    }
}

struct ImageMetadata: Sendable {
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var fileSize: Int64 = 0
    var formatDescription: String = "—"
    var colorModel: String?
    var cameraMake: String?
    var cameraModel: String?
    var lens: String?
    var captureDate: Date?
    var exposureTime: String?
    var aperture: String?
    var iso: String?
    var focalLength: String?
    /// Координаты съёмки из EXIF, если камера их записала.
    var latitude: Double?
    var longitude: Double?

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

enum ImageDecoder {
    /// Decodes `url`. Passing nil for `maxPixelSize` yields full resolution.
    ///
    /// Uses the thumbnail API in both cases: with `FromImageAlways` and a max
    /// dimension equal to the source it returns the full image, and unlike
    /// `CGImageSourceCreateImageAtIndex` it applies EXIF orientation for us.
    static func decode(url: URL, maxPixelSize: Int?) -> DecodedImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        let full = orientedPixelSize(source: source)
        let longestEdge = Int(max(full.width, full.height))
        guard longestEdge > 0 else { return nil }

        let target = min(maxPixelSize ?? longestEdge, longestEdge)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(target, 1),
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let isFull = cgImage.width >= Int(full.width) && cgImage.height >= Int(full.height)
        return DecodedImage(image: cgImage, pixelSize: full, isFullResolution: isFull)
    }

    /// Pixel dimensions with EXIF orientation applied, without decoding pixels.
    static func orientedPixelSize(source: CGImageSource) -> CGSize {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return .zero
        }
        let width = props[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        let orientation = props[kCGImagePropertyOrientation] as? Int ?? 1
        // Orientations 5...8 swap the axes.
        return orientation >= 5
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }

    static func orientedPixelSize(url: URL) -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return .zero }
        return orientedPixelSize(source: source)
    }

    static func metadata(url: URL) -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }

        var meta = ImageMetadata()
        let size = orientedPixelSize(source: source)
        meta.pixelWidth = Int(size.width)
        meta.pixelHeight = Int(size.height)

        if let values = try? url.resourceValues(forKeys: [.fileSizeKey]) {
            meta.fileSize = Int64(values.fileSize ?? 0)
        }

        if let uti = CGImageSourceGetType(source) as String?,
           let type = UTType(uti) {
            meta.formatDescription = type.localizedDescription ?? uti
        } else {
            meta.formatDescription = url.pathExtension.uppercased()
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        meta.colorModel = props[kCGImagePropertyColorModel] as? String

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
        }

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            meta.lens = exif[kCGImagePropertyExifLensModel] as? String
            meta.captureDate = exifDate(exif[kCGImagePropertyExifDateTimeOriginal] as? String)

            if let seconds = exif[kCGImagePropertyExifExposureTime] as? Double, seconds > 0 {
                meta.exposureTime = seconds >= 1
                    ? String(format: "%.1f с", seconds)
                    : "1/\(Int((1 / seconds).rounded())) с"
            }
            if let fNumber = exif[kCGImagePropertyExifFNumber] as? Double, fNumber > 0 {
                meta.aperture = String(format: "ƒ/%.1f", fNumber)
            }
            if let isoValues = exif[kCGImagePropertyExifISOSpeedRatings] as? [Int], let iso = isoValues.first {
                meta.iso = "ISO \(iso)"
            }
            if let focal = exif[kCGImagePropertyExifFocalLength] as? Double, focal > 0 {
                meta.focalLength = String(format: "%.0f мм", focal)
            }
        }

        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
           let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
           let lon = gps[kCGImagePropertyGPSLongitude] as? Double {
            // EXIF хранит модуль величины, полушарие — отдельной буквой.
            let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
            let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
            meta.latitude = latRef == "S" ? -lat : lat
            meta.longitude = lonRef == "W" ? -lon : lon
        }

        return meta
    }

    private static func exifDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
