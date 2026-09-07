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
check("«Вид» группирует форматы", sortModel.entries.first?.kind == sortModel.entries[1].kind,
      "\(sortModel.entries.first?.kind ?? "") / \(sortModel.entries[1].kind)")
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
check("разделы верхнего меню", top == ["Mishi Glance", "Файл", "Правка", "Вид", "Переход", "Окно"],
      top.joined(separator: " · "))

let appItems = titles(of: "Mishi Glance")
check("«Проверить обновления…» в меню программы",
      appItems.contains("Проверить обновления…"), appItems.joined(separator: " · "))
check("стоит выше «Настройки…»",
      (appItems.firstIndex(of: "Проверить обновления…") ?? 99)
        < (appItems.firstIndex(of: "Настройки…") ?? 0))

for (menu, item) in [("Файл","Поделиться…"), ("Файл","Открыть в программе"),
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

print(failures == 0 ? "\n✅ Все проверки пройдены" : "\n❌ Провалено: \(failures)")
exit(failures == 0 ? 0 : 1)
