//
//  UpdateView.swift
//  Mishi Glance
//

import AppKit
import SwiftUI

struct UpdateView: View {
    let controller: UpdateController

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(heading)
                        .font(.system(size: 15, weight: .semibold))
                    Text(subheading)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            if case .available(let release) = controller.state, !release.notes.isEmpty {
                Divider()
                ScrollView {
                    ReleaseNotesView(markdown: release.notes)
                        .padding(14)
                }
                .frame(height: 230)
            }

            if case .downloading(let fraction) = controller.state {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: fraction)
                    Text("\(Int(fraction * 100)) %")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }

            Divider()
            HStack {
                if case .available(let release) = controller.state {
                    Link("Что нового", destination: release.pageURL)
                        .font(.system(size: 12))
                }
                Spacer()
                buttons
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var buttons: some View {
        switch controller.state {
        case .available:
            Button("Позже") { controller.dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Обновить") { controller.installAvailableUpdate() }
                .keyboardShortcut(.defaultAction)
        case .checking, .downloading, .installing:
            Button("Отмена") { controller.dismiss() }
                .keyboardShortcut(.cancelAction)
        default:
            Button("Закрыть") { controller.dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }

    private var heading: String {
        switch controller.state {
        case .checking: "Проверяю обновления…"
        case .upToDate: "У вас последняя версия"
        case .available(let release): "Доступна версия \(release.version)"
        case .downloading: "Загружаю обновление"
        case .installing: "Устанавливаю"
        case .failed: "Не удалось проверить обновления"
        case .idle: "Обновления"
        }
    }

    private var subheading: String {
        let current = UpdateChecker.currentVersion
        switch controller.state {
        case .checking:
            return "Запрашиваю последний релиз на GitHub."
        case .upToDate:
            return "Установлена \(current) — это самая свежая версия."
        case .available:
            return "Установлена \(current). Обновление будет проверено по подписи "
                + "и установлено автоматически, приложение перезапустится."
        case .downloading:
            return "Скачиваю образ с GitHub."
        case .installing:
            return "Проверяю подпись и заменяю приложение."
        case .failed(let message):
            return message
        case .idle:
            return ""
        }
    }

    private var appIcon: NSImage {
        NSImage(named: "AppIcon")
            ?? NSImage(contentsOf: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns"))
            ?? NSApp.applicationIconImage
    }
}


/// Заметки к релизу: разбираем Markdown на блоки и рисуем их,
/// иначе в окне видны сами знаки разметки.
struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    Text(AttributedString.inlineMarkdown(text))
                        .font(.system(size: level <= 2 ? 13 : 12, weight: .semibold))
                        .padding(.top, 4)
                case .paragraph(let text):
                    Text(AttributedString.inlineMarkdown(text))
                        .font(.system(size: 11))
                        .fixedSize(horizontal: false, vertical: true)
                case .bullet(let text):
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text(AttributedString.inlineMarkdown(text))
                            .font(.system(size: 11))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .quote(let text):
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(Color.accentColor.opacity(0.6)).frame(width: 2)
                        Text(AttributedString.inlineMarkdown(text))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .rule:
                    Divider().padding(.vertical, 2)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
