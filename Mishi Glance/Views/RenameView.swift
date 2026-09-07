//
//  RenameView.swift
//  Mishi Glance
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class RenameController {
    var template = "{дата}_{nnn}"
    var startIndex = 1
    var onlyPicked = false
    private(set) var plans: [RenamePlan] = []
    private(set) var message: String?

    @ObservationIgnored weak var viewer: ViewerController?

    var sources: [ImageEntry] {
        guard let entries = viewer?.folder.entries else { return [] }
        return onlyPicked
            ? entries.filter { ImageMarks.flag(of: $0.url) == .picked }
            : entries
    }

    var conflictCount: Int { plans.filter(\.isConflicting).count }
    var changedCount: Int { plans.filter { !$0.isUnchanged && !$0.isConflicting }.count }

    func refresh() {
        plans = BatchRenamer.plan(for: sources, template: template, startIndex: startIndex)
        message = nil
    }

    func apply() {
        let outcome = BatchRenamer.apply(plans)
        message = outcome.failed.isEmpty
            ? "Переименовано: \(outcome.renamed)"
            : "Переименовано \(outcome.renamed), не удалось: "
                + outcome.failed.prefix(3).joined(separator: ", ")
        plans = []
        // Папка отслеживается, но подтолкнём обновление сразу.
        Task { await viewer?.reloadCurrent() }
    }
}

struct RenameView: View {
    @Bindable var controller: RenameController

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Шаблон")
                    TextField("{дата}_{nnn}", text: $controller.template)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: controller.template) { controller.refresh() }
                    Text("с номера")
                    TextField("", value: $controller.startIndex, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .onChange(of: controller.startIndex) { controller.refresh() }
                }
                Toggle("Только отобранные", isOn: $controller.onlyPicked)
                    .onChange(of: controller.onlyPicked) { controller.refresh() }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(BatchRenamer.tokens, id: \.token) { token, meaning in
                            Button {
                                controller.template += token
                                controller.refresh()
                            } label: {
                                Text(token)
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help(meaning)
                        }
                    }
                }
            }
            .padding(16)

            Divider()

            if controller.plans.isEmpty {
                ContentUnavailableView("Нечего переименовывать",
                                       systemImage: "textformat",
                                       description: Text("Задайте шаблон выше."))
                    .frame(maxHeight: .infinity)
            } else {
                List(controller.plans) { plan in
                    HStack(spacing: 8) {
                        Text(plan.oldName)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Text(plan.newName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(plan.isConflicting ? Color.red : .primary)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if plan.isConflicting {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .help("Такое имя уже занято другим файлом")
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Переименовать") { controller.apply() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(controller.changedCount == 0)
            }
            .padding(14)
        }
        .frame(width: 620, height: 480)
        .onAppear { controller.refresh() }
    }

    private var statusText: String {
        if let message = controller.message { return message }
        var parts = ["Будет переименовано: \(controller.changedCount)"]
        if controller.conflictCount > 0 {
            parts.append("конфликтов: \(controller.conflictCount)")
        }
        return parts.joined(separator: " · ")
    }
}
