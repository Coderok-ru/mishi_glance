//
//  PixelSampler.swift
//  Mishi Glance
//
//  Чтение цвета отдельного пикселя. Кадр разворачивается в буфер один раз,
//  дальше выборка идёт без обращения к Core Graphics на каждое движение мыши.
//

import AppKit
import CoreGraphics

struct SampledColor: Equatable, Sendable {
    let red: Int
    let green: Int
    let blue: Int
    let alpha: Int

    var hex: String { String(format: "#%02X%02X%02X", red, green, blue) }
    var rgbText: String { "\(red), \(green), \(blue)" }

    var color: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255,
                blue: CGFloat(blue) / 255, alpha: 1)
    }
}

final class PixelSampler: @unchecked Sendable {
    private let width: Int
    private let height: Int
    private let pixels: [UInt8]

    /// Разворачивает изображение в RGBA8. Возвращает nil, если кадр пуст.
    init?(image: CGImage) {
        // Размеры держим в локальных до конца инициализации: иначе замыкание
        // ниже захватило бы ещё не готовый self.
        let w = image.width
        let h = image.height
        guard w > 0, h > 0, w * h < 120_000_000 else { return nil }

        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = buffer.withUnsafeMutableBytes({ raw -> CGContext? in
            CGContext(data: raw.baseAddress, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info)
        }) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        width = w
        height = h
        pixels = buffer
    }

    /// `point` — координаты в пикселях изображения, начало отсчёта сверху слева.
    func color(atX x: Int, y: Int) -> SampledColor? {
        guard x >= 0, y >= 0, x < width, y < height else { return nil }
        let index = (y * width + x) * 4
        let alpha = Int(pixels[index + 3])
        // Буфер premultiplied — возвращаем исходный цвет, иначе полупрозрачные
        // участки читались бы темнее, чем выглядят.
        func straighten(_ value: UInt8) -> Int {
            guard alpha > 0, alpha < 255 else { return Int(value) }
            return min(255, Int(Double(value) * 255.0 / Double(alpha)))
        }
        return SampledColor(red: straighten(pixels[index]),
                            green: straighten(pixels[index + 1]),
                            blue: straighten(pixels[index + 2]),
                            alpha: alpha)
    }
}
