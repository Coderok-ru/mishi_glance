//
//  ExportView.swift
//  Mishi Glance
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class ExportController {
    enum Scope: String, CaseIterable, Identifiable {
        case current
        case folder
        case picked

        var id: String { rawValue }
        var title: String {
            switch self {
            case .current: "Текущий снимок"
            case .folder: "Всю папку"
            case .picked: "Только отобранные"
            }
        }
    }

    var scope: Scope = .current
    var format: ExportFormat = .jpeg
    var quality = 0.9
    var limitSize = false
    var maxPixelSize = 2048
    var keepMetadata = true

    private(set) var isRunning = false
    private(set) var progress = 0.0
    private(set) var result: String?

    @ObservationIgnored weak var viewer: ViewerController?

    var sources: [URL] {
        guard let viewer else { return [] }
        switch scope {
        case .current: return viewer.folder.current.map { [$0.url] } ?? []
        case .folder: return viewer.folder.entries.map(\.url)
        case .picked: return viewer.folder.entries
            .filter { ImageMarks.flag(of: $0.url) == .picked }.map(\.url)
        }
    }

    var options: ExportOptions {
        ExportOptions(format: format, quality: quality,
                      maxPixelSize: limitSize ? maxPixelSize : nil,
                      keepMetadata: keepMetadata)
    }

    /// Спрашивает папку назначения и пересохраняет в неё выбранное.
    func run() {
        let files = sources
        guard !files.isEmpty else { result = "Нечего экспортировать"; return }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Экспортировать сюда"
        panel.message = "Куда сохранить \(files.count) файл(ов)"
        guard panel.runModal() == .OK, let directory = panel.url else { return }

        isRunning = true
        progress = 0
        result = nil
        let settings = options

        Task {
            let outcome = await Task.detached(priority: .userInitiated) {
                ImageExporter.exportBatch(sources: files, to: directory, options: settings) { done, total in
                    Task { @MainActor [weak self] in
                        self?.progress = Double(done) / Double(max(total, 1))
                    }
                }
            }.value

            self.isRunning = false
            self.progress = 1
            if outcome.failed.isEmpty {
                self.result = "Готово: \(outcome.written.count) файл(ов)"
            } else {
                self.result = "Сохранено \(outcome.written.count), "
                    + "не удалось \(outcome.failed.count): "
                    + outcome.failed.prefix(3).joined(separator: ", ")
            }
            if let first = outcome.written.first {
                NSWorkspace.shared.activateFileViewerSelecting([first])
            }
        }
    }
}

struct ExportView: View {
    @Bindable var controller: ExportController

    var body: some View {
        Form {
            Section("Что экспортировать") {
                Picker("Объём", selection: $controller.scope) {
                    ForEach(ExportController.Scope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Формат") {
                Picker("Сохранить как", selection: $controller.format) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                if controller.format.supportsQuality {
                    HStack {
                        Text("Качество")
                        Slider(value: $controller.quality, in: 0.3 ... 1.0)
                        Text("\(Int(controller.quality * 100)) %")
                            .font(.caption.monospacedDigit())
                            .frame(width: 44, alignment: .trailing)
                    }
                } else {
                    Text("Формат без потерь — качество не настраивается.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Размер и метаданные") {
                Toggle("Уменьшить длинную сторону", isOn: $controller.limitSize)
                if controller.limitSize {
                    HStack {
                        Text("Не больше")
                        TextField("", value: $controller.maxPixelSize, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 90)
                        Text("пикселей")
                    }
                }
                Toggle("Сохранять EXIF, геометку и авторство", isOn: $controller.keepMetadata)
            }

            Section {
                if controller.isRunning {
                    ProgressView(value: controller.progress)
                }
                if let result = controller.result {
                    Text(result).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Экспортировать…") { controller.run() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(controller.isRunning || controller.sources.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 470)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var countText: String {
        let count = controller.sources.count
        return count == 0 ? "Нечего экспортировать" : "Будет обработано файлов: \(count)"
    }
}
