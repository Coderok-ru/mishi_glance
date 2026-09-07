//
//  GeneralSettingsView.swift
//  Mishi Glance
//

import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(SettingsKey.separateWindows) private var separateWindows = true
    @AppStorage(SettingsKey.restoreSession) private var restoreSession = false
    @AppStorage(SettingsKey.quitOnLastWindowClose) private var quitOnLastWindowClose = false
    @AppStorage(SettingsKey.rememberWindowFrame) private var rememberWindowFrame = true
    @AppStorage(SettingsKey.dragBehavior) private var dragBehavior = DragBehavior.pan.rawValue

    @AppStorage(SettingsKey.doubleClickActualSize) private var doubleClickActualSize = true
    @AppStorage(SettingsKey.smoothScaling) private var smoothScaling = true
    @AppStorage(SettingsKey.allowUpscale) private var allowUpscale = false

    @AppStorage(SettingsKey.swipeNavigation) private var swipeNavigation = true
    @AppStorage(SettingsKey.wrapAround) private var wrapAround = true
    @AppStorage(SettingsKey.confirmDelete) private var confirmDelete = true

    var body: some View {
        Form {
            Section("Окно") {
                Picker("Перетаскивание", selection: $dragBehavior) {
                    ForEach(DragBehavior.allCases) { behavior in
                        Text(behavior.title).tag(behavior.rawValue)
                    }
                }
                .onChange(of: dragBehavior) { notifyViewersOfSettingsChange() }

                Toggle("Открывать файлы в отдельных окнах", isOn: $separateWindows)
                Text("Если выключено, новый файл заменяет изображение в текущем окне.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Восстанавливать открытые изображения при запуске", isOn: $restoreSession)
                Toggle("Завершать программу при закрытии последнего окна", isOn: $quitOnLastWindowClose)
                Toggle("Запоминать размер и положение окна", isOn: $rememberWindowFrame)
            }

            Section("Масштаб") {
                Toggle("Двойной клик переключает реальный размер", isOn: $doubleClickActualSize)

                Toggle("Сглаживание при масштабировании", isOn: $smoothScaling)
                    .onChange(of: smoothScaling) { notifyViewersOfSettingsChange() }
                Text("Включено: пиксели смешиваются, края мягкие — лучше для фотографий. "
                     + "Выключено: чёткие пиксели без смешивания — для pixel art, скриншотов "
                     + "интерфейса и разглядывания отдельных пикселей при большом увеличении.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Увеличивать мелкие изображения до размера окна", isOn: $allowUpscale)
                    .onChange(of: allowUpscale) { notifyViewersOfSettingsChange() }
            }

            Section("Трекпад и навигация") {
                Toggle("Свайп влево/вправо листает изображения", isOn: $swipeNavigation)
                Toggle("Циклическая навигация", isOn: $wrapAround)
                Text("После последнего изображения переходить к первому.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Спрашивать подтверждение при удалении", isOn: $confirmDelete)
            }
        }
        .formStyle(.grouped)
    }
}
