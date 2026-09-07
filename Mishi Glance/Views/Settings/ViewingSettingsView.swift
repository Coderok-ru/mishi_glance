//
//  ViewingSettingsView.swift
//  Mishi Glance
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ViewingSettingsView: View {
    @AppStorage(SettingsKey.sortOrder) private var sortOrder = ImageSortOrder.name.rawValue
    @AppStorage(SettingsKey.sortAscending) private var sortAscending = true
    @AppStorage(SettingsKey.background) private var background = ViewerBackground.black.rawValue
    @AppStorage(SettingsKey.transparencyMode) private var transparency = TransparencyMode.checkerboard.rawValue
    @AppStorage(SettingsKey.preloadBufferMB) private var preloadBufferMB = 300
    @AppStorage(SettingsKey.externalEditorPath) private var externalEditorPath = ""

    @State private var statistics: ImageLoader.Statistics?

    var body: some View {
        Form {
            Section("Порядок листания") {
                Picker("Сортировать по", selection: $sortOrder) {
                    ForEach(ImageSortOrder.allCases) { order in
                        Text(order.title).tag(order.rawValue)
                    }
                }
                .onChange(of: sortOrder) { notifyViewersOfSettingsChange() }

                Picker("Направление", selection: $sortAscending) {
                    Text(currentOrder.ascendingLabel).tag(true)
                    Text(currentOrder.descendingLabel).tag(false)
                }
                .pickerStyle(.inline)
                .onChange(of: sortAscending) { notifyViewersOfSettingsChange() }

                Text("Стрелки листают файлы в этом порядке. Значения совпадают с "
                     + "колонками Finder — выберите то же, что стоит в окне Finder, "
                     + "и следующим будет ровно тот файл, что идёт там ниже.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Фон") {
                Picker("Фон окна", selection: $background) {
                    ForEach(ViewerBackground.allCases) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .onChange(of: background) { notifyViewersOfSettingsChange() }

                Picker("Прозрачность", selection: $transparency) {
                    ForEach(TransparencyMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .onChange(of: transparency) { notifyViewersOfSettingsChange() }
                Text("Что показывать под прозрачными участками изображения.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Предзагрузка") {
                HStack {
                    Text("Буфер (МБ)")
                    Spacer()
                    TextField("", value: $preloadBufferMB, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: preloadBufferMB) {
                            preloadBufferMB = min(max(preloadBufferMB, 64), 8192)
                            Task { await ImageLoader.shared.applyBudget(); await refresh() }
                        }
                    Button("Очистить") {
                        Task {
                            await ImageLoader.shared.clear()
                            await ImageLoader.thumbnails.clear()
                            await refresh()
                        }
                    }
                }
                Text(usageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Section("Внешний редактор") {
                Picker("Открывать в", selection: $externalEditorPath) {
                    ForEach(editorCandidates, id: \.path) { url in
                        Text(FileManager.default.displayName(atPath: url.path)).tag(url.path)
                    }
                    Divider()
                    Text("Выбрать программу…").tag("__choose__")
                }
                .onChange(of: externalEditorPath) {
                    if externalEditorPath == "__choose__" {
                        chooseEditor()
                    }
                    notifyViewersOfSettingsChange()
                }
            }
        }
        .formStyle(.grouped)
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private var currentOrder: ImageSortOrder {
        ImageSortOrder(rawValue: sortOrder) ?? .name
    }

    private var usageText: String {
        guard let statistics else { return "Использовано —" }
        return "Использовано \(ByteFormat.string(Int64(statistics.bytes)))"
            + " / \(ByteFormat.string(Int64(statistics.budget)))"
            + " (\(statistics.count) изобр.)"
    }

    private func refresh() async {
        statistics = await ImageLoader.shared.statistics()
    }

    /// Applications the system offers for images, so the picker is not empty.
    private var editorCandidates: [URL] {
        var urls = NSWorkspace.shared.urlsForApplications(toOpen: .jpeg)
            .filter { $0.standardizedFileURL != Bundle.main.bundleURL.standardizedFileURL }
        if !externalEditorPath.isEmpty, externalEditorPath != "__choose__" {
            let chosen = URL(fileURLWithPath: externalEditorPath)
            if !urls.contains(where: { $0.path == chosen.path }) {
                urls.insert(chosen, at: 0)
            }
        }
        return urls
    }

    private func chooseEditor() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Выбрать"

        if panel.runModal() == .OK, let url = panel.url {
            externalEditorPath = url.path
        } else {
            externalEditorPath = AppSettings.externalEditorURL?.path ?? ""
        }
    }
}
