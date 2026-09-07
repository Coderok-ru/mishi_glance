//
//  DuplicatesView.swift
//  Mishi Glance
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DuplicatesController {
    private(set) var groups: [DuplicateGroup] = []
    private(set) var isScanning = false
    private(set) var progress = 0.0
    private(set) var message: String?
    /// Насколько похожими считать кадры: 0 — только неотличимые.
    var threshold = 6

    @ObservationIgnored weak var viewer: ViewerController?

    var reclaimable: Int64 { groups.reduce(0) { $0 + $1.reclaimableBytes } }

    func scan() {
        guard let entries = viewer?.folder.entries, entries.count > 1 else {
            message = "В папке меньше двух изображений"
            return
        }
        isScanning = true
        progress = 0
        message = nil
        groups = []
        let limit = threshold

        Task {
            let found = await Task.detached(priority: .userInitiated) {
                DuplicateFinder.find(in: entries, threshold: limit) { done, total in
                    Task { @MainActor [weak self] in
                        self?.progress = Double(done) / Double(max(total, 1))
                    }
                }
            }.value
            self.isScanning = false
            self.progress = 1
            self.groups = found
            self.message = found.isEmpty
                ? "Повторов не найдено"
                : "Групп: \(found.count) · можно освободить \(ByteFormat.string(self.reclaimable))"
        }
    }

    /// Оставляет в каждой группе первый файл, остальные — в Корзину.
    func trashExtras() {
        var trashed = 0
        for group in groups {
            for entry in group.entries.dropFirst() {
                if (try? FileManager.default.trashItem(at: entry.url,
                                                       resultingItemURL: nil)) != nil {
                    trashed += 1
                }
            }
        }
        groups = []
        message = "Перемещено в Корзину: \(trashed)"
    }
}

struct DuplicatesView: View {
    @Bindable var controller: DuplicatesController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Поиск повторов")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Находит и точные копии, и пережатые или уменьшенные версии.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $controller.threshold) {
                    Text("Строго").tag(0)
                    Text("Обычно").tag(6)
                    Text("Свободно").tag(12)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
                Button("Найти") { controller.scan() }
                    .disabled(controller.isScanning)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)

            if controller.isScanning {
                ProgressView(value: controller.progress).padding(.horizontal, 16)
            }
            Divider()

            if controller.groups.isEmpty {
                ContentUnavailableView(
                    controller.message ?? "Повторы не искали",
                    systemImage: "square.on.square.dashed",
                    description: Text("Нажмите «Найти», чтобы просмотреть папку.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(controller.groups) { group in
                        Section {
                            ForEach(group.entries) { entry in
                                HStack(spacing: 10) {
                                    Text(entry.name)
                                        .font(.system(size: 12))
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    if entry.url == group.entries.first?.url {
                                        Text("оставим")
                                            .font(.system(size: 10, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    Text(ByteFormat.string(entry.fileSize))
                                        .font(.system(size: 11).monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { controller.viewer?.show(entry: entry) }
                            }
                        } header: {
                            Text("Похожих файлов: \(group.entries.count) · освободится "
                                 + ByteFormat.string(group.reclaimableBytes))
                                .font(.system(size: 11))
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                if let message = controller.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Оставить по одному, остальные в Корзину") { confirmTrash() }
                    .disabled(controller.groups.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 560, height: 520)
    }

    private func confirmTrash() {
        let alert = NSAlert()
        alert.messageText = "Переместить повторы в Корзину?"
        alert.informativeText = "В каждой группе останется самый крупный файл. "
            + "Освободится \(ByteFormat.string(controller.reclaimable)). "
            + "Из Корзины файлы можно вернуть."
        alert.addButton(withTitle: "Переместить")
        alert.addButton(withTitle: "Отмена")
        if alert.runModal() == .alertFirstButtonReturn { controller.trashExtras() }
    }
}
