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
                            histogram: controller.histogram,
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
                    if controller.isComparing {
                        CompareControls(controller: controller)
                            .onHover { controller.pinOverlay = $0 }
                    }
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
            if controller.isComparing, controller.compareMode != .sideBySide {
                canvas(for: displayed, secondary: false).ignoresSafeArea()
            } else if controller.isComparing {
                HStack(spacing: 8) {
                    canvas(for: displayed, secondary: false)
                    if let other = controller.compareImage {
                        canvas(for: other, secondary: true)
                    } else {
                        ProgressView().controlSize(.small).tint(.white)
                            .frame(maxWidth: .infinity)
                    }
                }
                .ignoresSafeArea()
            } else {
                canvas(for: displayed, secondary: false).ignoresSafeArea()
            }
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

    private func canvas(for image: DecodedImage, secondary: Bool) -> some View {
        let blended = controller.isComparing && controller.compareMode != .sideBySide
        return ImageCanvas(
            controller: controller,
            image: image.image,
            scale: controller.scale,
            offset: controller.offset,
            rotation: controller.rotation,
            animation: secondary ? nil : controller.animation,
            isPlaying: controller.isAnimationPlaying,
            pixelSize: image.pixelSize,
            isSecondary: secondary,
            overlayImage: blended ? controller.compareImage?.image : nil,
            overlayOpacity: controller.compareOpacity,
            overlayIsDifference: controller.compareMode == .difference,
            crossfade: controller.isSlideshowRunning && AppSettings.smoothSlideshow
        )
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


/// Переключатель режимов сравнения и ползунок прозрачности.
struct CompareControls: View {
    @Bindable var controller: ViewerController

    var body: some View {
        HStack(spacing: 12) {
            Picker("", selection: $controller.compareMode) {
                ForEach(CompareMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 240)

            if controller.compareMode == .overlay {
                Slider(value: $controller.compareOpacity, in: 0 ... 1)
                    .frame(width: 120)
                Text("\(Int(controller.compareOpacity * 100)) %")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 38, alignment: .trailing)
            }

            Button {
                controller.toggleCompareWithNext()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.8))
            .help("Закончить сравнение")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.black.opacity(0.55), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }
}
