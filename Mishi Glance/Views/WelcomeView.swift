//
//  WelcomeView.swift
//  Mishi Glance
//
//  Показывается один раз, при первом запуске.
//

import AppKit
import SwiftUI

struct WelcomeView: View {
    /// Закрыть окно и больше не показывать.
    let onFinish: () -> Void
    let onShowShortcuts: () -> Void

    @State private var isAssigning = false
    @State private var assignResult: String?

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text("Добро пожаловать")
                    .font(.system(size: 21, weight: .semibold))
                Text("Откройте любое изображение — и листайте всю папку\nстрелками, не возвращаясь в Finder.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 28)
            .padding(.bottom, 22)

            Divider()

            VStack(alignment: .leading, spacing: 11) {
                Text("Самое нужное")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(ShortcutCatalog.essentials) { item in
                    HStack(spacing: 9) {
                        HStack(spacing: 3) {
                            ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                KeyCap(label: key)
                            }
                        }
                        .frame(width: 74, alignment: .leading)
                        Text(item.title).font(.system(size: 12))
                        Spacer(minLength: 0)
                    }
                }
                Button("Все клавиши…") { onShowShortcuts() }
                    .buttonStyle(.link)
                    .font(.system(size: 12))
                    .padding(.top, 2)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 20)

            Divider()

            VStack(spacing: 10) {
                Text("Чтобы фотографии открывались здесь по двойному клику,\nназначьте Mishi Glance программой по умолчанию.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let assignResult {
                    Text(assignResult)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    Button("Назначить для всех форматов") { assignDefaults() }
                        .disabled(isAssigning)
                    Button("Начать") { onFinish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func assignDefaults() {
        isAssigning = true
        assignResult = nil
        Task {
            let failed = await FileAssociations.makeDefaultForAll()
            isAssigning = false
            assignResult = failed.isEmpty
                ? "Готово — теперь снимки открываются здесь."
                : "Назначено не всё. Осталось: \(failed.prefix(4).joined(separator: ", "))."
        }
    }

    private var appIcon: NSImage {
        NSImage(named: "AppIcon")
            ?? NSImage(contentsOf: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns"))
            ?? NSApp.applicationIconImage
    }
}
