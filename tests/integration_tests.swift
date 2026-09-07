import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
AppSettings.registerDefaults()

var failures = 0
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print((ok ? "  ok   " : "  FAIL ") + label + (detail.isEmpty ? "" : "  → \(detail)"))
    if !ok { failures += 1 }
}
func pump(_ seconds: Double) {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
}

let dir = URL(fileURLWithPath: CommandLine.arguments[1])

print("\n[A] Окно просмотра")
let viewer = ViewerWindowController()
viewer.open(url: dir.appendingPathComponent("img2.jpg"))
pump(3)
check("изображение декодировано", viewer.controller.displayed != nil)
check("папка прочитана", viewer.controller.folder.count == 5, "\(viewer.controller.folder.count)")
check("окно видимо", viewer.window?.isVisible == true)
check("заголовок = имя файла", viewer.window?.title == "img2.jpg", viewer.window?.title ?? "nil")
check("канва в иерархии", viewer.window?.contentView != nil)

print("\n[B] Окно со списком изображений папки")
check("изначально закрыто", !viewer.isBrowserVisible)
viewer.toggleBrowser()
pump(2)
check("открывается по команде", viewer.isBrowserVisible)
let browserWindow = NSApp.windows.first { $0.title == "Список файлов" }
check("заголовок окна", browserWindow != nil, browserWindow?.title ?? "nil")
let contentSize = browserWindow?.contentView?.frame.size ?? .zero
check("вертикальное окно, не полоска", contentSize.width >= 440 && contentSize.height >= 700,
      "\(Int(contentSize.width))×\(Int(contentSize.height))")
check("выше, чем шире (как в референсе)", contentSize.height > contentSize.width)
check("режим по умолчанию — список", AppSettings.browserViewMode == .list)
viewer.toggleBrowser()
pump(1)
check("закрывается повторной командой", !viewer.isBrowserVisible)

print("\n[C] Миниатюры для сетки")
let thumb = await ImageLoader.thumbnails.image(for: dir.appendingPathComponent("img1.jpg"), maxPixel: 320)
check("миниатюра построена", thumb != nil)
check("ограничена 320 px", max(thumb?.image.width ?? 0, thumb?.image.height ?? 0) == 320,
      "\(thumb?.image.width ?? -1)×\(thumb?.image.height ?? -1)")
let mainStats = await ImageLoader.shared.statistics()
let thumbStats = await ImageLoader.thumbnails.statistics()
check("кеши раздельные", thumbStats.budget != mainStats.budget,
      "основной \(mainStats.budget / 1048576) МБ, миниатюры \(thumbStats.budget / 1048576) МБ")
check("бюджет основного = настройке", mainStats.budget == AppSettings.preloadBufferBytes)

print("\n[D] Статистика и очистка буфера")
check("в основном кеше есть кадры", mainStats.count > 0, "\(mainStats.count) шт, \(mainStats.bytes) байт")
await ImageLoader.shared.clear()
let cleared = await ImageLoader.shared.statistics()
check("Очистить обнуляет", cleared.count == 0 && cleared.bytes == 0, "\(cleared.count)/\(cleared.bytes)")

print("\n[E] Файловые ассоциации")
check("типов в списке: 19 (11 обычных + 8 RAW)", ImageFormat.all.count == 19,
      "\(ImageFormat.all.count)")
let unresolved = ImageFormat.all.filter { $0.type == nil }.map(\.name)
check("все UTI распознаны системой", unresolved.isEmpty, unresolved.joined(separator: ", "))
let jpeg = ImageFormat.all.first { $0.name == "JPEG" }!
let handler = FileAssociations.currentHandler(for: jpeg)
check("текущий обработчик JPEG читается", handler != nil, handler?.name ?? "nil")
// Preview owns JPEG on a stock system, so isSelf must be false here.
check("чужой обработчик не считается своим", handler?.isSelf == false,
      "isSelf=\(handler?.isSelf.description ?? "nil")")
let missing = ImageFormat(name: "X", extensions: ".x", identifier: "invalid.type.zzz")
check("неизвестный UTI не ломает чтение", FileAssociations.currentHandler(for: missing) == nil)

print("\n[F] Настройки")
let settings = NSHostingController(rootView: SettingsView())
let settingsWindow = NSWindow(contentViewController: settings)
settingsWindow.makeKeyAndOrderFront(nil)
pump(2)
check("окно настроек строится", settingsWindow.contentView != nil)
check("размер вкладок задан", settings.view.fittingSize.width >= 520,
      "\(Int(settings.view.fittingSize.width))×\(Int(settings.view.fittingSize.height))")

print("\n[G] Прозрачность и режимы перетаскивания")
check("режим по умолчанию — шахматка", AppSettings.transparencyMode == .checkerboard)
check("перетаскивание по умолчанию — панорамирование", AppSettings.dragBehavior == .pan)
check("сглаживание включено", AppSettings.smoothScaling)
let alphaImage = ImageDecoder.decode(url: dir.appendingPathComponent("photo.png"), maxPixelSize: nil)
check("PNG декодирован", alphaImage != nil)
check("внешний редактор определён", AppSettings.externalEditorURL != nil,
      AppSettings.externalEditorURL?.lastPathComponent ?? "nil")

print("\n[H] Порядок листания против колонки Finder «Имя»")
let sortDir = URL(fileURLWithPath: CommandLine.arguments[2])
let sortModel = FolderModel()
sortModel.sortOrder = .name
sortModel.sortAscending = true
await sortModel.open(url: sortDir.appendingPathComponent("1.jpg"))
let order = sortModel.entries.map(\.name)
print("   порядок: " + order.joined(separator: " · "))

func before(_ a: String, _ b: String) -> Bool {
    guard let i = order.firstIndex(of: a), let j = order.firstIndex(of: b) else { return false }
    return i < j
}
check("числа natural: 2 < 10", before("2.jpg", "10.jpg"))
check("числа natural: 1 < 2", before("1.jpg", "2.jpg"))
check("регистр игнорируется: Foto 2 < foto 10", before("Foto 2.jpg", "foto 10.jpg"))
check("ведущие нули: IMG_001 < img_2", before("IMG_001.jpg", "img_2.jpg"))
// Collation follows the system locale, exactly as Finder's does: in ru_RU
// Cyrillic precedes Latin, so this asserts we track the locale, not a guess.
check("порядок алфавитов = системной локали (\(Locale.current.identifier))",
      before("Апельсин.jpg", "zebra.png"),
      "кириллица перед латиницей")
check("совпадает с системным компаратором Finder",
      order == order.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
check("кириллица по алфавиту: Апельсин < банан", before("Апельсин.jpg", "банан.jpg"))

sortModel.sortAscending = false
check("убывание — точный разворот", sortModel.entries.map(\.name) == order.reversed(),
      sortModel.entries.map(\.name).prefix(3).joined(separator: " · "))

sortModel.sortAscending = true
sortModel.sortOrder = .dateAdded
let added = sortModel.entries.map(\.name)
check("«Дата добавления» работает", added.count == order.count && added != order,
      added.prefix(3).joined(separator: " · "))
sortModel.sortOrder = .kind
let kinds = Set(sortModel.entries.map(\.kind))
check("«Вид» читается из системы", !kinds.contains(""), kinds.sorted().joined(separator: ", "))
// Настоящий признак группировки: каждый вид встречается одним сплошным
// отрезком, а не вразбивку.
let kindRuns = sortModel.entries.map(\.kind).reduce(into: [String]()) { acc, k in
    if acc.last != k { acc.append(k) }
}
check("«Вид» группирует форматы без разрывов",
      kindRuns.count == Set(kindRuns).count, kindRuns.joined(separator: " → "))
sortModel.sortOrder = .name
check("возврат к имени восстанавливает порядок", sortModel.entries.map(\.name) == order)

print("\n[J] Строка списка не расползается от пропорций картинки")
func rowSize(_ name: String) -> CGSize {
    guard let entry = ImageEntry(url: sortDir.appendingPathComponent(name)) else { return .zero }
    let host = NSHostingView(rootView: BrowserListRow(entry: entry, isCurrent: false))
    host.frame = NSRect(x: 0, y: 0, width: 420, height: 300)
    let w = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                     backing: .buffered, defer: false)
    w.contentView = host
    w.orderFront(nil)
    pump(1.2)
    let size = host.fittingSize
    w.orderOut(nil)
    return size
}
let expected = BrowserListRow.thumbnailSide + BrowserListRow.verticalPadding * 2
let wide = rowSize("wide.jpg"), tall = rowSize("tall.jpg"), square = rowSize("square.jpg")
print("   высоты: широкая \(Int(wide.height)) · высокая \(Int(tall.height)) · квадрат \(Int(square.height)), ожидается \(Int(expected))")
check("широкая картинка (1600×200) не раздувает строку", abs(wide.height - expected) < 1,
      "\(wide.height)")
check("высокая картинка (200×1600) не раздувает строку", abs(tall.height - expected) < 1,
      "\(tall.height)")
check("квадратная — та же высота", abs(square.height - expected) < 1, "\(square.height)")
check("все строки одной высоты", wide.height == tall.height && tall.height == square.height)
check("широкая не растягивает строку вширь", wide.width <= 420 + 1, "\(wide.width)")

print("\n[I] Окно «О программе»")
let about = NSHostingController(rootView: AboutView())
let aboutWindow = NSWindow(contentViewController: about)
aboutWindow.makeKeyAndOrderFront(nil)
pump(1.5)
check("окно строится", aboutWindow.contentView != nil)
check("ширина как задумано", Int(about.view.fittingSize.width) == 380,
      "\(Int(about.view.fittingSize.width))×\(Int(about.view.fittingSize.height))")
check("иконка приложения доступна", NSApp.applicationIconImage != nil)
for link in ["https://t.me/coderok_official", "https://coderok.ru", "mailto:info@coderok.ru"] {
    check("ссылка разбирается: \(link)", URL(string: link) != nil)
}

print("\n[K] Обновление с GitHub")
check("1.0 < 1.0.1", AppVersion("1.0") < AppVersion("1.0.1"))
check("1.0.1 < 1.1", AppVersion("1.0.1") < AppVersion("1.1"))
check("1.9 < 1.10 (не лексикографически)", AppVersion("1.9") < AppVersion("1.10"))
check("1.1 < 2.0", AppVersion("1.1") < AppVersion("2.0"))
check("префикс v срезается", AppVersion("v1.2.3").description == "1.2.3",
      AppVersion("v1.2.3").description)
check("1.0 и 1.0.0 равны", !(AppVersion("1.0") < AppVersion("1.0.0"))
      && !(AppVersion("1.0.0") < AppVersion("1.0")))
check("текущая версия читается", UpdateChecker.currentVersion.parts.first != nil,
      UpdateChecker.currentVersion.description)

print("\n[L] Проверка подписи обновления")
let ownDMG = URL(fileURLWithPath: CommandLine.arguments[3])
if FileManager.default.fileExists(atPath: ownDMG.path) {
    do {
        try UpdateChecker.verifySignature(at: ownDMG, expectApplication: false)
        check("свой образ принимается", true)
    } catch {
        check("свой образ принимается", false, error.localizedDescription)
    }
} else {
    print("   образ не собран, пропускаю")
}
// Preview подписан Apple, а не нашей командой — обязан быть отвергнут.
do {
    try UpdateChecker.verifySignature(at: URL(fileURLWithPath: "/System/Applications/Preview.app"),
                                      expectApplication: true)
    check("чужая подпись отвергается", false, "принял Preview.app!")
} catch {
    check("чужая подпись отвергается", true, "\(error.localizedDescription.prefix(46))")
}
// Ничем не подписанный файл.
let junk = FileManager.default.temporaryDirectory.appendingPathComponent("mg-unsigned.dmg")
try? Data(repeating: 0, count: 2048).write(to: junk)
do {
    try UpdateChecker.verifySignature(at: junk, expectApplication: false)
    check("неподписанный файл отвергается", false, "принял мусор!")
} catch {
    check("неподписанный файл отвергается", true)
}
try? FileManager.default.removeItem(at: junk)

print("\n[M] Живой запрос к GitHub")
do {
    let release = try await UpdateChecker.latestNewerRelease()
    check("запрос выполнен без ошибки", true,
          release.map { "предложена \($0.version)" } ?? "обновлений нет — версия свежая")
    if let release {
        check("ссылка ведёт на GitHub по https",
              release.downloadURL.scheme == "https"
              && (release.downloadURL.host ?? "").contains("github"),
              release.downloadURL.host ?? "nil")
    }
} catch {
    print("   сеть недоступна, пропускаю: \(error.localizedDescription.prefix(60))")
}

print("\n[N] Главное меню")
let menuDelegate = AppDelegate()
NSApp.delegate = menuDelegate
menuDelegate.applicationWillFinishLaunching(Notification(name: .init("probe")))
let mainMenu = NSApp.mainMenu
check("меню построено", mainMenu != nil)

func titles(of menuTitle: String) -> [String] {
    guard let sub = mainMenu?.items.first(where: { $0.title == menuTitle })?.submenu else { return [] }
    return sub.items.filter { !$0.isSeparatorItem }.map(\.title)
}
let top = mainMenu?.items.map(\.title) ?? []
check("разделы верхнего меню",
      top == ["Mishi Glance", "Файл", "Правка", "Вид", "Переход", "Отбор", "Справка", "Окно"],
      top.joined(separator: " · "))

let appItems = titles(of: "Mishi Glance")
check("«Проверить обновления…» в меню программы",
      appItems.contains("Проверить обновления…"), appItems.joined(separator: " · "))
check("стоит выше «Настройки…»",
      (appItems.firstIndex(of: "Проверить обновления…") ?? 99)
        < (appItems.firstIndex(of: "Настройки…") ?? 0))

for (menu, item) in [("Файл","Экспортировать…"), ("Вид","Сравнить со следующим"),
                     ("Отбор","Отобрать  (P)"), ("Отбор","Отклонить  (X)"),
                     ("Отбор","Переместить отобранные…"), ("Отбор","Отклонённые в Корзину…"),
                     ("Справка","Клавиши…"), ("Справка","Знакомство с программой…"),
                     ("Файл","Поделиться…"), ("Файл","Открыть в программе"),
                     ("Файл","Показать в Finder"), ("Вид","Изображения в папке"),
                     ("Вид","Информация"), ("Переход","Следующее изображение")] {
    check("«\(item)» в меню «\(menu)»", titles(of: menu).contains(item),
          titles(of: menu).joined(separator: " · "))
}
check("пункт обновления доступен", menuDelegate.validateMenuItem(
        NSMenuItem(title: "", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")))

print("\n[O] RAW, поиск и геометка")
let rawIDs = ["com.canon.cr2-raw-image","com.nikon.raw-image","com.sony.arw-raw-image","com.adobe.raw-image"]
let rawOK = rawIDs.allSatisfy { UTType($0)?.conforms(to: .image) == true }
check("система считает RAW изображениями", rawOK)
let rawInList = ImageFormat.all.filter { rawIDs.contains($0.identifier) }.count
check("RAW есть во вкладке форматов", rawInList == 4, "\(rawInList) из 4")
check("форматов в списке стало 19", ImageFormat.all.count == 19, "\(ImageFormat.all.count)")

let pool = sortModel.entries
let byFoto = ImageEntry.filter(pool, query: "foto")
check("поиск без учёта регистра", byFoto.count == 2, byFoto.map(\.name).joined(separator: " · "))
check("пустой запрос не фильтрует", ImageEntry.filter(pool, query: "   ").count == pool.count)
check("поиск по кириллице", ImageEntry.filter(pool, query: "апельсин").count == 1)
check("несуществующее — пусто", ImageEntry.filter(pool, query: "zzzz").isEmpty)
check("поиск по расширению", ImageEntry.filter(pool, query: ".png").count
      == pool.filter { $0.name.hasSuffix(".png") }.count)

// Записываем снимок с координатами и читаем их обратно.
let gpsURL = FileManager.default.temporaryDirectory.appendingPathComponent("mg-gps.jpg")
if let base = ImageDecoder.decode(url: sortDir.appendingPathComponent("square.jpg"), maxPixelSize: nil),
   let dest = CGImageDestinationCreateWithURL(gpsURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
    let gps: [CFString: Any] = [
        kCGImagePropertyGPSLatitude: 59.9386, kCGImagePropertyGPSLatitudeRef: "N",
        kCGImagePropertyGPSLongitude: 30.3141, kCGImagePropertyGPSLongitudeRef: "E",
    ]
    CGImageDestinationAddImage(dest, base.image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
    CGImageDestinationFinalize(dest)
    let meta = ImageDecoder.metadata(url: gpsURL)
    check("координаты прочитаны", meta?.hasCoordinate == true)
    check("широта Петербурга", abs((meta?.latitude ?? 0) - 59.9386) < 0.001, "\(meta?.latitude ?? 0)")
    check("долгота Петербурга", abs((meta?.longitude ?? 0) - 30.3141) < 0.001, "\(meta?.longitude ?? 0)")
    // Западное полушарие должно уходить в минус.
    let west = FileManager.default.temporaryDirectory.appendingPathComponent("mg-gps-w.jpg")
    if let d2 = CGImageDestinationCreateWithURL(west as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
        let g2: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 40.7128, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 74.0060, kCGImagePropertyGPSLongitudeRef: "W",
        ]
        CGImageDestinationAddImage(d2, base.image, [kCGImagePropertyGPSDictionary: g2] as CFDictionary)
        CGImageDestinationFinalize(d2)
        let m2 = ImageDecoder.metadata(url: west)
        check("западная долгота отрицательна", (m2?.longitude ?? 0) < 0, "\(m2?.longitude ?? 0)")
    }
    try? FileManager.default.removeItem(at: west)
} else {
    check("подготовка снимка с координатами", false)
}
try? FileManager.default.removeItem(at: gpsURL)
check("без координат карта не показывается",
      ImageDecoder.metadata(url: sortDir.appendingPathComponent("square.jpg"))?.hasCoordinate == false)

print("\n[P] Анимация")
let gif = sortDir.appendingPathComponent("anim.gif")
check("кадров в файле: 6", ImageDecoder.frameCount(url: gif) == 6,
      "\(ImageDecoder.frameCount(url: gif))")
if let anim = ImageDecoder.decodeAnimation(url: gif, maxPixelSize: 400) {
    check("развёрнуто 6 кадров", anim.frames.count == 6, "\(anim.frames.count)")
    check("задержек столько же", anim.delays.count == anim.frames.count)
    check("задержка около 80 мс", abs((anim.delays.first ?? 0) - 0.08) < 0.02,
          "\(anim.delays.first ?? 0)")
    check("длительность около 0,48 с", abs(anim.duration - 0.48) < 0.1,
          String(format: "%.2f", anim.duration))
    check("зациклен бесконечно", anim.loopCount == 0, "\(anim.loopCount)")
} else {
    check("анимация разобрана", false)
}
check("обычный снимок не считается анимацией",
      ImageDecoder.decodeAnimation(url: sortDir.appendingPathComponent("square.jpg"),
                                   maxPixelSize: 400) == nil)
check("одиночный кадр не даёт анимации", ImageDecoder.frameCount(url: sortDir.appendingPathComponent("wide.jpg")) == 1)

print("\n[Q] Гистограмма и подробные метаданные")
let flat = sortDir.appendingPathComponent("flat.png")
if let img = ImageDecoder.decode(url: flat, maxPixelSize: nil),
   let h = ImageDecoder.histogram(of: img.image) {
    check("средний красный = 64", abs(h.meanRed - 64) < 1.5, String(format: "%.1f", h.meanRed))
    check("средний зелёный = 128", abs(h.meanGreen - 128) < 1.5, String(format: "%.1f", h.meanGreen))
    check("средний синий = 192", abs(h.meanBlue - 192) < 1.5, String(format: "%.1f", h.meanBlue))
    check("256 корзин на канал", h.red.count == 256 && h.luma.count == 256)
    // Однотонная картинка: вся масса в одной корзине.
    let filled = h.red.filter { $0 > 0 }.count
    check("однотонный кадр — одна корзина", filled <= 2, "\(filled)")
    check("пик положителен", h.peak > 0)
    let sum = h.luma.reduce(0) { $0 + Int($1) }
    check("сумма корзин = числу пикселей выборки", sum > 0, "\(sum)")
} else {
    check("гистограмма посчитана", false)
}

let alphaMeta = ImageDecoder.metadata(url: sortDir.appendingPathComponent("alpha.png"))
check("альфа-канал распознан", alphaMeta?.hasAlpha == true)
check("глубина цвета прочитана", (alphaMeta?.bitDepth ?? 0) > 0, "\(alphaMeta?.bitDepth ?? 0)")
check("путь к папке заполнен", alphaMeta?.filePath.isEmpty == false)
check("ориентация названа", alphaMeta?.orientationName != nil, alphaMeta?.orientationName ?? "nil")
let jpegMeta = ImageDecoder.metadata(url: sortDir.appendingPathComponent("square.jpg"))
check("у JPEG альфы нет", jpegMeta?.hasAlpha == false)

print("\n[R] Экспорт и конвертация")
let outDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("mg-export-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
let bigSource = dir.appendingPathComponent("img1.jpg")   // 4032×3024

do {
    let jpeg = try ImageExporter.export(source: bigSource, to: outDir,
                                        options: ExportOptions(format: .jpeg, quality: 0.8))
    check("JPEG создан", FileManager.default.fileExists(atPath: jpeg.path))
    check("расширение .jpg", jpeg.pathExtension == "jpg", jpeg.lastPathComponent)
    check("размеры сохранены", ImageDecoder.orientedPixelSize(url: jpeg)
          == CGSize(width: 4032, height: 3024))

    let png = try ImageExporter.export(source: bigSource, to: outDir,
                                       options: ExportOptions(format: .png))
    check("PNG создан", png.pathExtension == "png")

    var shrink = ExportOptions(format: .jpeg, quality: 0.9)
    shrink.maxPixelSize = 800
    let small = try ImageExporter.export(source: bigSource, to: outDir, options: shrink)
    let smallSize = ImageDecoder.orientedPixelSize(url: small)
    check("уменьшение до 800 по длинной стороне",
          Int(max(smallSize.width, smallSize.height)) == 800,
          "\(Int(smallSize.width))×\(Int(smallSize.height))")

    // Повторный экспорт не должен затирать уже созданный файл.
    let again = try ImageExporter.export(source: bigSource, to: outDir,
                                         options: ExportOptions(format: .jpeg))
    check("второй файл получает свой номер", again.lastPathComponent != jpeg.lastPathComponent,
          again.lastPathComponent)

    // Перенос метаданных: берём снимок с координатами.
    let gpsSrc = FileManager.default.temporaryDirectory.appendingPathComponent("mg-src-gps.jpg")
    if let base = ImageDecoder.decode(url: sortDir.appendingPathComponent("square.jpg"), maxPixelSize: nil),
       let d = CGImageDestinationCreateWithURL(gpsSrc as CFURL, UTType.jpeg.identifier as CFString, 1, nil) {
        let gps: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 55.7558, kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 37.6173, kCGImagePropertyGPSLongitudeRef: "E"]
        CGImageDestinationAddImage(d, base.image, [kCGImagePropertyGPSDictionary: gps] as CFDictionary)
        CGImageDestinationFinalize(d)

        let kept = try ImageExporter.export(source: gpsSrc, to: outDir,
                                            options: ExportOptions(format: .jpeg, keepMetadata: true))
        check("геометка перенесена", ImageDecoder.metadata(url: kept)?.hasCoordinate == true)

        let stripped = try ImageExporter.export(source: gpsSrc, to: outDir,
                                                options: ExportOptions(format: .jpeg, keepMetadata: false))
        check("без метаданных геометки нет",
              ImageDecoder.metadata(url: stripped)?.hasCoordinate == false)
        try? FileManager.default.removeItem(at: gpsSrc)
    }

    let batch = ImageExporter.exportBatch(
        sources: [bigSource, dir.appendingPathComponent("img2.jpg")],
        to: outDir, options: ExportOptions(format: .png)) { _, _ in }
    check("пакетно записано 2", batch.written.count == 2, "\(batch.written.count)")
    check("ошибок нет", batch.failed.isEmpty, batch.failed.joined(separator: ", "))
} catch {
    check("экспорт без ошибок", false, error.localizedDescription)
}
try? FileManager.default.removeItem(at: outDir)

print("\n[S] Пометки отбраковки")
let markURL = sortDir.appendingPathComponent("square.jpg")
ImageMarks.setRating(0, at: markURL)
ImageMarks.setFlag(nil, at: markURL)
check("изначально без рейтинга", ImageMarks.rating(of: markURL) == 0)
check("изначально без флага", ImageMarks.flag(of: markURL) == nil)

ImageMarks.setRating(4, at: markURL)
check("рейтинг записан и прочитан", ImageMarks.rating(of: markURL) == 4,
      "\(ImageMarks.rating(of: markURL))")
ImageMarks.setRating(9, at: markURL)
check("рейтинг ограничен пятёркой", ImageMarks.rating(of: markURL) == 5,
      "\(ImageMarks.rating(of: markURL))")
ImageMarks.setRating(0, at: markURL)
check("нулевой рейтинг снимает атрибут", ImageMarks.rating(of: markURL) == 0)

ImageMarks.setFlag(.picked, at: markURL)
check("флаг «отобрано»", ImageMarks.flag(of: markURL) == .picked)
ImageMarks.setFlag(.rejected, at: markURL)
check("флаг меняется на «отклонено»", ImageMarks.flag(of: markURL) == .rejected)
ImageMarks.setFlag(nil, at: markURL)
check("флаг снимается", ImageMarks.flag(of: markURL) == nil)

// Пометка не должна менять сам файл.
let sizeBefore = (try? FileManager.default.attributesOfItem(atPath: markURL.path)[.size] as? Int) ?? 0
ImageMarks.setRating(3, at: markURL)
let sizeAfter = (try? FileManager.default.attributesOfItem(atPath: markURL.path)[.size] as? Int) ?? 0
check("снимок не переписывается", sizeBefore == sizeAfter, "\(sizeBefore ?? 0) vs \(sizeAfter ?? 0)")
ImageMarks.setRating(0, at: markURL)

print("\n[T] Шпаргалка по клавишам")
let allItems = ShortcutCatalog.groups.flatMap(\.items)
check("групп в шпаргалке: 4", ShortcutCatalog.groups.count == 4,
      "\(ShortcutCatalog.groups.count)")
check("подсказок больше двадцати", allItems.count > 20, "\(allItems.count)")
check("у каждой есть клавиши и описание",
      allItems.allSatisfy { !$0.keys.isEmpty && !$0.title.isEmpty })
check("описания не повторяются",
      Set(allItems.map(\.title)).count == allItems.count)
check("идентификаторы уникальны",
      Set(allItems.map(\.id)).count == allItems.count)
check("в кратком списке 4 пункта", ShortcutCatalog.essentials.count == 4)
// Ключевые сочетания обязаны быть описаны.
for keys in [["←", "→"], ["F"], ["⌘", "I"], ["P"], ["X"], ["⌘", "B"], ["⇧", "⌘", "E"]] {
    check("описано сочетание \(keys.joined(separator: "+"))",
          allItems.contains { $0.keys == keys })
}
// Знакомство: показывается один раз, но из меню доступно всегда.
let savedFlag = AppSettings.didShowWelcome
AppSettings.didShowWelcome = false
check("на первом запуске знакомство показывается", menuDelegate.shouldShowWelcome)
menuDelegate.showWelcome()
check("после показа флаг выставлен", AppSettings.didShowWelcome)
check("на следующем запуске уже не показывается", !menuDelegate.shouldShowWelcome)
menuDelegate.showWelcome()
check("повторный вызов из меню работает", AppSettings.didShowWelcome)
check("пункт меню «Знакомство» доступен", menuDelegate.validateMenuItem(
        NSMenuItem(title: "", action: #selector(AppDelegate.showWelcomeAgain(_:)),
                   keyEquivalent: "")))
check("пункт «Клавиши…» доступен", menuDelegate.validateMenuItem(
        NSMenuItem(title: "", action: #selector(AppDelegate.showShortcuts(_:)),
                   keyEquivalent: "")))
AppSettings.didShowWelcome = savedFlag

print("\n[U] Разбор заметок к релизу")
let notes = """
    Первая строка описания.

    ## Установка

    Скачайте `файл.dmg` и перетащите в «Программы».

    > Заверено у Apple.

    ---

    ## Что нового
    - **Отбраковка** кадров
    - Сравнение двух снимков
    1. Нумерованный пункт
    """
let blocks = MarkdownBlock.parse(notes)
check("заголовки распознаны",
      blocks.filter { if case .heading = $0 { return true }; return false }.count == 2,
      "\(blocks.count) блоков")
check("уровень заголовка прочитан",
      blocks.contains(.heading(level: 2, text: "Установка")))
check("маркированные пункты", blocks.contains(.bullet("**Отбраковка** кадров")))
check("нумерованные пункты", blocks.contains(.bullet("Нумерованный пункт")))
check("цитата", blocks.contains(.quote("Заверено у Apple.")))
check("горизонтальная черта", blocks.contains(.rule))
check("абзац собран целиком", blocks.contains(.paragraph("Первая строка описания.")))
check("знаки разметки не попали в текст",
      !blocks.contains { if case .paragraph(let t) = $0 { return t.hasPrefix("#") }; return false })
// Строчная разметка снимается уже при отрисовке.
let inline = AttributedString.inlineMarkdown("**жирный** и `код`")
check("строчная разметка разобрана", !String(inline.characters).contains("**"),
      String(inline.characters))
check("пустой текст не ломает разбор", MarkdownBlock.parse("").isEmpty)

print(failures == 0 ? "\n✅ Все проверки пройдены" : "\n❌ Провалено: \(failures)")
exit(failures == 0 ? 0 : 1)
