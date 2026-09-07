//
//  FileTypesSettingsView.swift
//  Mishi Glance
//
//  Makes Mishi Glance the default viewer per image type — the association
//  setting Finder otherwise hides behind "Свойства → Открывать в программе".
//

import AppKit
import SwiftUI

struct FileTypesSettingsView: View {
    @State private var handlers: [String: HandlerInfo] = [:]
    @State private var busy = false
    @State private var message: String?

    private struct HandlerInfo {
        let name: String
        let icon: NSImage
        let isSelf: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            List {
                ForEach(ImageFormat.all) { format in
                    row(for: format)
                }
            }
            .listStyle(.inset)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task { reload() }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Программа по умолчанию")
                    .font(.system(size: 13, weight: .semibold))
                Text("Двойной клик по файлу в Finder будет открывать Mishi Glance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Назначить все") {
                Task {
                    busy = true
                    let failed = await FileAssociations.makeDefaultForAll()
                    busy = false
                    reload()
                    message = failed.isEmpty
                        ? "Все поддерживаемые типы назначены."
                        : "Не удалось назначить: \(failed.joined(separator: ", "))."
                }
            }
            .disabled(busy)
        }
        .padding(16)
    }

    private func row(for format: ImageFormat) -> some View {
        let handler = handlers[format.identifier]

        return HStack(spacing: 12) {
            Text(format.name)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 54, alignment: .leading)
            Text(format.extensions)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let handler {
                HStack(spacing: 5) {
                    Image(nsImage: handler.icon)
                        .resizable()
                        .frame(width: 15, height: 15)
                    Text(handler.name)
                        .font(.system(size: 11))
                        .foregroundStyle(handler.isSelf ? Color.accentColor : .secondary)
                        .lineLimit(1)
                }
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Button(handler?.isSelf == true ? "Назначено" : "Назначить") {
                Task {
                    busy = true
                    do {
                        try await FileAssociations.makeDefault(for: format)
                        message = nil
                    } catch {
                        message = "\(format.name): \(error.localizedDescription)"
                    }
                    busy = false
                    reload()
                }
            }
            .disabled(busy || handler?.isSelf == true)
            .frame(width: 96)
        }
        .padding(.vertical, 3)
    }

    private func reload() {
        var result: [String: HandlerInfo] = [:]
        for format in ImageFormat.all {
            if let current = FileAssociations.currentHandler(for: format) {
                result[format.identifier] = HandlerInfo(
                    name: current.name, icon: current.icon, isSelf: current.isSelf
                )
            }
        }
        handlers = result
    }
}
