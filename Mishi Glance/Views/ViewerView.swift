//
//  ViewerView.swift
//  Mishi Glance
//

import SwiftUI
import UniformTypeIdentifiers

struct ViewerView: View {
    let controller: ViewerController

    @AppStorage(SettingsKey.background) private var backgroundRaw = ViewerBackground.black.rawValue
    @State private var isTargetedForDrop = false

    private var background: ViewerBackground {
        ViewerBackground(rawValue: backgroundRaw) ?? .black
    }

    var body: some View {
        ZStack {
            background.color
                .ignoresSafeArea()

            content

            // Info panel, top trailing.
            VStack {
                HStack(alignment: .top) {
                    Spacer()
                    if controller.showInfoPanel {
                        InfoPanelView(
                            metadata: controller.metadata,
                            fileName: controller.folder.current?.name
                        )
                        .padding(16)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                Spacer()
            }

            // Toolbar and status, bottom centre. Both fade with the idle timer.
            VStack {
                Spacer()
                VStack(spacing: 10) {
                    if controller.displayed != nil {
                        ViewerToolbar(controller: controller)
                            .onHover { controller.pinOverlay = $0 }
                    }
                    if let status = controller.statusText {
                        StatusOverlayView(text: status)
                    }
                }
                .padding(.bottom, 22)
                .opacity(controller.overlayVisible ? 1 : 0)
                .allowsHitTesting(controller.overlayVisible)
                .animation(.easeInOut(duration: 0.25), value: controller.overlayVisible)
            }

            if isTargetedForDrop {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Color.accentColor, lineWidth: 3)
                    .padding(8)
                    .ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.18), value: controller.showInfoPanel)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first else { return false }
            Task { await controller.open(url: url) }
            return true
        } isTargeted: { isTargetedForDrop = $0 }
    }

    @ViewBuilder
    private var content: some View {
        if let displayed = controller.displayed {
            ImageCanvas(
                controller: controller,
                image: displayed.image,
                scale: controller.scale,
                offset: controller.offset,
                rotation: controller.rotation
            )
            .ignoresSafeArea()
        } else if let failure = controller.failureMessage {
            placeholder(icon: "exclamationmark.triangle", title: failure)
        } else if controller.isDecoding || controller.folder.isScanning {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
        } else {
            placeholder(icon: "photo.on.rectangle.angled", title: "Перетащите изображение")
        }
    }

    private func placeholder(icon: String, title: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 44, weight: .light))
            Text(title)
                .font(.system(size: 15))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.45))
        .padding(40)
    }
}

struct StatusOverlayView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.black.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.4), radius: 8, y: 2)
    }
}
