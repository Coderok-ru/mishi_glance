//
//  PrintableImageView.swift
//  Mishi Glance
//
//  Вид для печати: вписывает снимок в страницу с учётом полей и не режет
//  его на несколько листов.
//

import AppKit

final class PrintableImageView: NSView {
    private let image: CGImage

    init(image: CGImage, printInfo: NSPrintInfo) {
        self.image = image
        // Размер вида задаём равным печатаемой области страницы, тогда
        // NSPrintOperation не станет разбивать изображение на листы.
        let paper = printInfo.paperSize
        let printable = NSRect(
            x: printInfo.leftMargin,
            y: printInfo.bottomMargin,
            width: paper.width - printInfo.leftMargin - printInfo.rightMargin,
            height: paper.height - printInfo.topMargin - printInfo.bottomMargin
        )
        super.init(frame: NSRect(origin: .zero, size: printable.size))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .high

        let imageSize = CGSize(width: image.width, height: image.height)
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        // Вписываем без обрезки и без растягивания сверх оригинала по пропорции.
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: bounds.midX - drawn.width / 2,
                             y: bounds.midY - drawn.height / 2)
        context.draw(image, in: CGRect(origin: origin, size: drawn))
    }
}
