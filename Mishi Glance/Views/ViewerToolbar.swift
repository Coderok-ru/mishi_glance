//
//  ViewerToolbar.swift
//  Mishi Glance
//
//  Floating capsule toolbar. It shares the status overlay's idle timer, so
//  the viewer still goes fully chrome-free the moment the mouse settles.
//

import AppKit
import SwiftUI

struct ViewerToolbar: View {
    let controller: ViewerController

    var body: some View {
        HStack(spacing: 10) {
            group {
                ToolbarButton(symbol: "square.grid.2x2", help: "Изображения в папке (⌘B)") {
                    controller.toggleBrowser()
                }
                ToolbarButton(symbol: "info.circle", help: "Информация (⌘I)",
                              isActive: controller.showInfoPanel) {
                    controller.showInfoPanel.toggle()
                }
            }

            group {
                ToolbarButton(symbol: controller.isSlideshowRunning ? "pause.fill" : "play.fill",
                              help: controller.isSlideshowRunning
                                    ? "Остановить слайдшоу (S)" : "Слайдшоу (S)",
                              isActive: controller.isSlideshowRunning) {
                    controller.toggleSlideshow()
                }
                ToolbarButton(symbol: "eyedropper",
                              help: "Пипетка: цвет под курсором (⌥⌘C)",
                              isActive: controller.isSamplingColor) {
                    controller.isSamplingColor.toggle()
                    controller.flashOverlay()
                }
            }

            group {
                ToolbarButton(symbol: "rotate.left", help: "Повернуть влево (⌘L)") {
                    controller.rotate(clockwise: false)
                }
                ToolbarButton(symbol: "rotate.right", help: "Повернуть вправо (⌘R)") {
                    controller.rotate(clockwise: true)
                }
            }

            group {
                ToolbarButton(symbol: "folder", help: "Показать в Finder (⇧⌘R)") {
                    controller.revealInFinder()
                }
                ToolbarButton(symbol: "square.and.arrow.up", help: "Поделиться") {
                    controller.share()
                }
            }

            if let editor = AppSettings.externalEditorURL {
                group {
                    Button {
                        controller.openInExternalEditor()
                    } label: {
                        HStack(spacing: 6) {
                            Image(nsImage: applicationIcon(editor))
                                .resizable()
                                .frame(width: 17, height: 17)
                            Text(FileManager.default.displayName(atPath: editor.path))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 4)
                        .frame(height: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Открыть в редакторе")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 4)
    }

    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 2) {
            content()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }

    private func applicationIcon(_ url: URL) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 17, height: 17)
        return icon
    }
}

private struct ToolbarButton: View {
    let symbol: String
    let help: String
    var isActive = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 30)
                .background(
                    Capsule().fill(.white.opacity(isActive ? 0.22 : (isHovering ? 0.12 : 0)))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { isHovering = $0 }
    }
}
