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

/// Многокадровое изображение: GIF, APNG, анимированные WebP и HEICS.
struct AnimatedImage: @unchecked Sendable {
    let frames: [CGImage]
    /// Длительность каждого кадра в секундах, той же длины, что frames.
    let delays: [Double]
    /// 0 — крутить бесконечно.
    let loopCount: Int

    var duration: Double { delays.reduce(0, +) }
    var byteCount: Int { frames.reduce(0) { $0 + $1.height * $1.bytesPerRow } }
}

/// Распределение яркостей по каналам, 256 корзин на канал.
struct ImageHistogram: Sendable {
    var red = [UInt32](repeating: 0, count: 256)
    var green = [UInt32](repeating: 0, count: 256)
    var blue = [UInt32](repeating: 0, count: 256)
    var luma = [UInt32](repeating: 0, count: 256)
    var meanRed = 0.0
    var meanGreen = 0.0
    var meanBlue = 0.0
    /// Наибольшее значение среди всех каналов — для нормировки при отрисовке.
    var peak: UInt32 = 1
}

struct ImageMetadata: Sendable {
    var pixelWidth: Int = 0
    var pixelHeight: Int = 0
    var fileSize: Int64 = 0
    var formatDescription: String = "—"
    var filePath: String = ""
    var bitDepth: Int = 0
    var hasAlpha = false
    var colorSpaceName: String?
    var orientationName: String?
    var colorModel: String?
    var cameraMake: String?
    var cameraModel: String?
    var lens: String?
    var captureDate: Date?
    var exposureTime: String?
    var aperture: String?
    var iso: String?
    var focalLength: String?
    var focalLength35mm: String?
    var lensMake: String?
    var exposureProgram: String?
    var meteringMode: String?
    var flash: String?
    var whiteBalance: String?
    var exposureBias: String?
    var software: String?
    var artist: String?
    var copyrightNotice: String?
    var dpi: String?
    var altitude: String?
    /// Координаты съёмки из EXIF, если камера их записала.
    var latitude: Double?
    var longitude: Double?

    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
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

    /// Сколько кадров в файле. Больше одного — значит анимация.
    static func frameCount(url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return 0 }
        return CGImageSourceGetCount(source)
    }

    /// Читает все кадры анимации с их задержками.
    /// Возвращает nil для обычных однокадровых файлов.
    static func decodeAnimation(url: URL, maxPixelSize: Int?) -> AnimatedImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        // Ограничение на всякий случай: очень длинные GIF-ы способны съесть
        // всю память, если разворачивать их в кадры целиком.
        let limit = min(count, 400)
        var frames: [CGImage] = []
        var delays: [Double] = []
        frames.reserveCapacity(limit)

        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let maxPixelSize { options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize }

        for index in 0 ..< limit {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(
                source, index, options as CFDictionary) else { continue }
            frames.append(frame)
            delays.append(frameDelay(source: source, index: index))
        }
        guard frames.count > 1 else { return nil }

        return AnimatedImage(frames: frames, delays: delays,
                             loopCount: loopCount(source: source))
    }

    /// Задержка кадра. Разные форматы прячут её в свои словари, а нулевые
    /// значения браузеры исторически заменяют на 0,1 с — делаем так же.
    private static func frameDelay(source: CGImageSource, index: Int) -> Double {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any] else { return 0.1 }

        let containers: [(CFString, CFString, CFString)] = [
            (kCGImagePropertyGIFDictionary,
             kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
            (kCGImagePropertyPNGDictionary,
             kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
            (kCGImagePropertyWebPDictionary,
             kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
            (kCGImagePropertyHEICSDictionary,
             kCGImagePropertyHEICSUnclampedDelayTime, kCGImagePropertyHEICSDelayTime),
        ]
        for (dict, unclamped, clamped) in containers {
            guard let sub = props[dict] as? [CFString: Any] else { continue }
            let value = (sub[unclamped] as? Double) ?? (sub[clamped] as? Double) ?? 0
            return value < 0.011 ? 0.1 : value
        }
        return 0.1
    }

    private static func loopCount(source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
        else { return 0 }
        for (dict, key) in [(kCGImagePropertyGIFDictionary, kCGImagePropertyGIFLoopCount),
                            (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGLoopCount),
                            (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPLoopCount)] {
            if let sub = props[dict] as? [CFString: Any], let n = sub[key] as? Int { return n }
        }
        return 0
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

        meta.filePath = url.deletingLastPathComponent().path

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        meta.colorModel = props[kCGImagePropertyColorModel] as? String
        meta.bitDepth = props[kCGImagePropertyDepth] as? Int ?? 0
        meta.hasAlpha = props[kCGImagePropertyHasAlpha] as? Bool ?? false
        meta.colorSpaceName = props[kCGImagePropertyProfileName] as? String
        meta.orientationName = orientationTitle(props[kCGImagePropertyOrientation] as? Int ?? 1)

        if let width = props[kCGImagePropertyDPIWidth] as? Double, width > 0 {
            meta.dpi = "\(Int(width)) dpi"
        }

        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            meta.cameraMake = tiff[kCGImagePropertyTIFFMake] as? String
            meta.cameraModel = tiff[kCGImagePropertyTIFFModel] as? String
            meta.software = tiff[kCGImagePropertyTIFFSoftware] as? String
            meta.artist = (tiff[kCGImagePropertyTIFFArtist] as? String)?
                .trimmingCharacters(in: .whitespaces).nilIfEmpty
            meta.copyrightNotice = (tiff[kCGImagePropertyTIFFCopyright] as? String)?
                .trimmingCharacters(in: .whitespaces).nilIfEmpty
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
            if let eq = exif[kCGImagePropertyExifFocalLenIn35mmFilm] as? Int, eq > 0 {
                meta.focalLength35mm = "\(eq) мм экв."
            }
            meta.lensMake = exif[kCGImagePropertyExifLensMake] as? String
            if let bias = exif[kCGImagePropertyExifExposureBiasValue] as? Double {
                meta.exposureBias = bias == 0 ? "0 EV" : String(format: "%+.1f EV", bias)
            }
            if let program = exif[kCGImagePropertyExifExposureProgram] as? Int {
                meta.exposureProgram = exposureProgramTitle(program)
            }
            if let metering = exif[kCGImagePropertyExifMeteringMode] as? Int {
                meta.meteringMode = meteringTitle(metering)
            }
            if let flash = exif[kCGImagePropertyExifFlash] as? Int {
                // Младший бит — сработала ли вспышка, остальное про режим.
                meta.flash = (flash & 1) == 1 ? "Сработала" : "Не сработала"
            }
            if let balance = exif[kCGImagePropertyExifWhiteBalance] as? Int {
                meta.whiteBalance = balance == 0 ? "Автоматический" : "Ручной"
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

            if let altitude = gps[kCGImagePropertyGPSAltitude] as? Double {
                // Ref = 1 означает «ниже уровня моря».
                let below = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
                meta.altitude = String(format: "%.0f м%@", altitude, below ? " ниже уровня моря" : "")
            }
        }

        return meta
    }

    private static func exposureProgramTitle(_ value: Int) -> String {
        switch value {
        case 1: "Ручной"
        case 2: "Программный"
        case 3: "Приоритет диафрагмы"
        case 4: "Приоритет выдержки"
        case 5: "Творческий"
        case 6: "Спортивный"
        case 7: "Портрет"
        case 8: "Пейзаж"
        default: "Не указан"
        }
    }

    private static func meteringTitle(_ value: Int) -> String {
        switch value {
        case 1: "Средневзвешенный"
        case 2: "Центровзвешенный"
        case 3: "Точечный"
        case 4: "Многоточечный"
        case 5: "Матричный"
        case 6: "Частичный"
        default: "Не указан"
        }
    }

    /// Человекочитаемое название ориентации из EXIF.
    private static func orientationTitle(_ value: Int) -> String {
        switch value {
        case 1: "Обычная"
        case 2: "Отражена по горизонтали"
        case 3: "Поворот 180°"
        case 4: "Отражена по вертикали"
        case 5: "Отражена и повёрнута на 90° влево"
        case 6: "Поворот 90° вправо"
        case 7: "Отражена и повёрнута на 90° вправо"
        case 8: "Поворот 90° влево"
        default: "Неизвестна"
        }
    }

    /// Считает гистограмму по уменьшенной копии: на глаз результат тот же,
    /// а для снимка на 50 Мп это разница между миллисекундами и секундами.
    static func histogram(of image: CGImage, sampleSize: Int = 512) -> ImageHistogram? {
        let scale = min(1.0, Double(sampleSize) / Double(max(image.width, image.height)))
        let width = max(Int(Double(image.width) * scale), 1)
        let height = max(Int(Double(image.height) * scale), 1)

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = pixels.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(data: buffer.baseAddress, width: width, height: height,
                      bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var histogram = ImageHistogram()
        var sumR = 0.0, sumG = 0.0, sumB = 0.0
        let total = width * height

        for index in stride(from: 0, to: pixels.count, by: 4) {
            let r = Int(pixels[index]), g = Int(pixels[index + 1]), b = Int(pixels[index + 2])
            histogram.red[r] += 1
            histogram.green[g] += 1
            histogram.blue[b] += 1
            // Коэффициенты BT.601 — та же яркость, что видит глаз.
            let y = Int(0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b))
            histogram.luma[min(y, 255)] += 1
            sumR += Double(r); sumG += Double(g); sumB += Double(b)
        }

        guard total > 0 else { return nil }
        histogram.meanRed = sumR / Double(total)
        histogram.meanGreen = sumG / Double(total)
        histogram.meanBlue = sumB / Double(total)
        histogram.peak = max(1, [histogram.red, histogram.green, histogram.blue]
            .flatMap { $0 }.max() ?? 1)
        return histogram
    }

    private static func exifDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: string)
    }
}
