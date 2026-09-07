//
//  AboutView.swift
//  Mishi Glance
//
//  Replaces the stock About panel, which cannot show tappable links.
//

import AppKit
import SwiftUI

struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Версия \(short) (\(build))"
    }

    /// Read straight from the asset catalog: NSApp.applicationIconImage goes
    /// through LaunchServices, which can still be serving a stale cache entry.
    private var appIcon: NSImage {
        NSImage(named: "AppIcon")
            ?? NSImage(contentsOf: Bundle.main.bundleURL
                .appendingPathComponent("Contents/Resources/AppIcon.icns"))
            ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 96, height: 96)

                Text("Mishi Glance")
                    .font(.system(size: 21, weight: .semibold))
                Text(version)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Просмотрщик изображений для macOS")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 26)
            .padding(.bottom, 20)

            Divider()

            VStack(alignment: .leading, spacing: 9) {
                row("Разработчик", text: "Андрей Любиченко")
                row("Студия", text: "Coderok")
                row("Telegram", link: "@coderok_official",
                    url: "https://t.me/coderok_official")
                row("Сайт", link: "coderok.ru", url: "https://coderok.ru")
                row("Почта", link: "info@coderok.ru", url: "mailto:info@coderok.ru")
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()

            Text("© 2026 Coderok. Все права защищены.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .padding(.vertical, 10)
        }
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func row(_ label: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(text)
                .font(.system(size: 12))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func row(_ label: String, link: String, url: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            if let destination = URL(string: url) {
                Link(link, destination: destination)
                    .font(.system(size: 12))
            } else {
                Text(link).font(.system(size: 12))
            }
            Spacer(minLength: 0)
        }
    }
}
