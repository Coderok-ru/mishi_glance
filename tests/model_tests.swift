import Foundation
import AppKit

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ok   " : "  FAIL ") + label + (detail.isEmpty ? "" : "  → \(detail)"))
    if !ok { failures += 1 }
}

@MainActor func run() async {
    AppSettings.registerDefaults()
    let dir = URL(fileURLWithPath: CommandLine.arguments[1])
    let start = dir.appendingPathComponent("img2.jpg")

    print("\n[1] Сканирование папки и natural sort")
    let model = FolderModel()
    model.sortOrder = .name
    await model.open(url: start)
    let names = model.entries.map(\.name)
    check("найдено 5 изображений", model.entries.count == 5, "\(model.entries.count)")
    check("natural sort", names == ["img1.jpg","img2.jpg","img10.jpg","photo.png","shot.png"], "\(names)")
    check("курсор на открытом файле", model.current?.name == "img2.jpg", model.current?.name ?? "nil")

    print("\n[2] Навигация")
    model.goNext();  check("→ img10.jpg", model.current?.name == "img10.jpg", model.current?.name ?? "nil")
    model.goPrevious(); check("← img2.jpg", model.current?.name == "img2.jpg", model.current?.name ?? "nil")
    model.goFirst(); check("Home → img1.jpg", model.current?.name == "img1.jpg", model.current?.name ?? "nil")
    model.goLast();  check("End → shot.png", model.current?.name == "shot.png", model.current?.name ?? "nil")
    model.goNext();  check("цикл после последнего → img1.jpg", model.current?.name == "img1.jpg", model.current?.name ?? "nil")

    print("\n[3] Сортировка по размеру файла")
    model.sortAscending = true
    model.sortOrder = .fileSize
    check("по возрастанию — самый мелкий первым", model.entries.first?.name == "photo.png",
          model.entries.first?.name ?? "nil")
    model.sortAscending = false
    check("по убыванию — самый крупный первым", model.entries.first?.name == "img1.jpg",
          model.entries.first?.name ?? "nil")
    check("курсор держится за файлом", model.current?.name == "img1.jpg", model.current?.name ?? "nil")
    model.sortAscending = true
    model.sortOrder = .name

    print("\n[4] Префетч соседей")
    let neighbours = model.neighbourURLs(radius: 2).map { $0.lastPathComponent }
    check("±2 соседа", neighbours.count == 4, "\(neighbours)")

    print("\n[5] Декодирование")
    let big = dir.appendingPathComponent("img1.jpg")
    let full = ImageDecoder.decode(url: big, maxPixelSize: nil)
    check("полное разрешение 4032×3024",
          full?.image.width == 4032 && full?.image.height == 3024,
          "\(full?.image.width ?? -1)×\(full?.image.height ?? -1)")
    check("помечено как full", full?.isFullResolution == true)
    let thumb = ImageDecoder.decode(url: big, maxPixelSize: 1000)
    check("ограничение по длинной стороне 1000", max(thumb?.image.width ?? 0, thumb?.image.height ?? 0) == 1000,
          "\(thumb?.image.width ?? -1)×\(thumb?.image.height ?? -1)")
    check("thumb не full", thumb?.isFullResolution == false)
    check("pixelSize остаётся исходным", thumb?.pixelSize == CGSize(width: 4032, height: 3024))

    print("\n[6] Кеш загрузчика (дедупликация и повтор)")
    let loader = ImageLoader.shared
    let t0 = Date()
    _ = await loader.image(for: big, maxPixel: 1200)
    let cold = Date().timeIntervalSince(t0)
    let t1 = Date()
    _ = await loader.image(for: big, maxPixel: 1200)
    let warm = Date().timeIntervalSince(t1)
    check("повторный запрос из кеша быстрее", warm < cold, String(format: "cold %.0f мс / warm %.2f мс", cold*1000, warm*1000))
    check("холодный декод < 300 мс (норматив ТЗ)", cold < 0.3, String(format: "%.0f мс", cold*1000))

    print("\n[7] Метаданные")
    let meta = ImageDecoder.metadata(url: big)
    check("размеры", meta?.pixelWidth == 4032 && meta?.pixelHeight == 3024)
    check("размер файла > 0", (meta?.fileSize ?? 0) > 0)
    check("формат распознан", (meta?.formatDescription.isEmpty == false), meta?.formatDescription ?? "nil")

    print("\n[8] Математика зума")
    let vc = ViewerController()
    await vc.open(url: big)
    vc.viewportSize = CGSize(width: 1000, height: 1000)
    vc.applyFit()
    check("fit вписывает по ширине", abs(vc.scale - 1000.0/4032.0) < 0.001, "\(vc.scale)")
    check("режим fit", vc.isFitMode)
    vc.zoomToActualSize()
    check("100 % = scale 1", vc.scale == 1)
    check("вышли из fit", !vc.isFitMode)
    check("панорамирование доступно", vc.canPan)
    vc.pan(by: CGSize(width: 100000, height: 0))
    let maxSlack = (4032.0 - 1000.0)/2
    check("offset ограничен краем", abs(vc.offset.width - maxSlack) < 0.5, "\(vc.offset.width) vs \(maxSlack)")
    vc.rotate(clockwise: true)
    check("поворот 90°", vc.rotation == 90)
    check("после поворота стороны меняются", vc.orientedPixelSize == CGSize(width: 3024, height: 4032))
    check("поворот возвращает в fit", vc.isFitMode)

    print("\n[9] Битый файл")
    let broken = dir.appendingPathComponent("broken.jpg")
    try? Data("не картинка".utf8).write(to: broken)
    check("декодер возвращает nil", ImageDecoder.decode(url: broken, maxPixelSize: nil) == nil)
    try? FileManager.default.removeItem(at: broken)

    print("\n[10] Слежение за папкой (FSEvents)")
    let watch = FolderModel()
    await watch.open(url: dir.appendingPathComponent("img1.jpg"))
    let before = watch.count
    var changed = false
    watch.onFolderChanged = { changed = true }
    let added = dir.appendingPathComponent("zz_new.png")
    if let src = ImageDecoder.decode(url: dir.appendingPathComponent("photo.png"), maxPixelSize: nil) {
        let rep = NSBitmapImageRep(cgImage: src.image)
        try? rep.representation(using: .png, properties: [:])?.write(to: added)
    }
    for _ in 0..<60 where !changed { try? await Task.sleep(for: .milliseconds(100)) }
    check("новый файл замечен", changed && watch.count == before + 1, "было \(before), стало \(watch.count)")
    check("курсор остался на img1.jpg", watch.current?.name == "img1.jpg", watch.current?.name ?? "nil")

    let anchorName = watch.current?.name ?? ""
    changed = false
    try? FileManager.default.removeItem(at: added)
    for _ in 0..<60 where !changed { try? await Task.sleep(for: .milliseconds(100)) }
    check("удалённый файл исчез", changed && watch.count == before, "\(watch.count)")
    check("курсор пережил удаление", watch.current?.name == anchorName, watch.current?.name ?? "nil")

    print(failures == 0 ? "\n✅ Все проверки пройдены" : "\n❌ Провалено проверок: \(failures)")
    exit(failures == 0 ? 0 : 1)
}

await run()
