//
//  InfoPanelView.swift
//  Mishi Glance
//

import CoreLocation
import MapKit
import SwiftUI

struct InfoPanelView: View {
    let metadata: ImageMetadata?
    let histogram: ImageHistogram?
    let fileName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if let metadata {
                    section("Файл") {
                        row("Имя", fileName ?? "—")
                        row("Папка", metadata.filePath, truncateMiddle: true)
                        row("Размер", ByteFormat.string(metadata.fileSize))
                        row("Формат", metadata.formatDescription)
                    }

                    section("Изображение") {
                        row("Размеры", "\(metadata.pixelWidth) × \(metadata.pixelHeight)")
                        if metadata.bitDepth > 0 { row("Глубина", "\(metadata.bitDepth) бит") }
                        row("Альфа-канал", metadata.hasAlpha ? "Есть" : "Нет")
                        if let space = metadata.colorSpaceName ?? metadata.colorModel {
                            row("Цветовой профиль", space, truncateMiddle: true)
                        }
                        if let orientation = metadata.orientationName {
                            row("Ориентация", orientation)
                        }
                        if let dpi = metadata.dpi { row("Разрешение", dpi) }
                    }

                    if let histogram {
                        section("Гистограмма") { HistogramView(histogram: histogram) }
                    }

                    rows(cameraRows, title: "Камера")
                    rows(shotRows, title: "Параметры съёмки")

                    if let latitude = metadata.latitude, let longitude = metadata.longitude {
                        section("Место съёмки") {
                            if let altitude = metadata.altitude { row("Высота", altitude) }
                            CaptureMapView(latitude: latitude, longitude: longitude)
                        }
                    }

                    rows(authorRows, title: "Авторство")
                } else {
                    Text("Метаданные недоступны")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
        }
        .frame(width: 340)
        .frame(maxHeight: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
    }

    // MARK: - Наборы строк

    /// Камера и объектив — то, чем снято.
    private var cameraRows: [(String, String)] {
        guard let metadata else { return [] }
        var result: [(String, String)] = []
        let body = [metadata.cameraMake, metadata.cameraModel]
            .compactMap { $0 }.joined(separator: " ")
        if !body.isEmpty { result.append(("Камера", body)) }
        let lens = [metadata.lensMake, metadata.lens]
            .compactMap { $0 }.joined(separator: " ")
        if !lens.isEmpty { result.append(("Объектив", lens)) }
        if let software = metadata.software { result.append(("Обработано в", software)) }
        return result
    }

    /// Как снято: выдержка, диафрагма, ISO и режимы.
    private var shotRows: [(String, String)] {
        guard let metadata else { return [] }
        var result: [(String, String)] = []
        if let date = metadata.captureDate {
            result.append(("Снято", date.formatted(date: .abbreviated, time: .shortened)))
        }
        if let value = metadata.exposureTime { result.append(("Выдержка", value)) }
        if let value = metadata.aperture { result.append(("Диафрагма", value)) }
        if let value = metadata.iso { result.append(("Чувствительность", value)) }
        let focal = [metadata.focalLength, metadata.focalLength35mm]
            .compactMap { $0 }.joined(separator: " · ")
        if !focal.isEmpty { result.append(("Фокусное расстояние", focal)) }
        if let value = metadata.exposureBias { result.append(("Экспокоррекция", value)) }
        if let value = metadata.exposureProgram { result.append(("Режим", value)) }
        if let value = metadata.meteringMode { result.append(("Замер", value)) }
        if let value = metadata.flash { result.append(("Вспышка", value)) }
        if let value = metadata.whiteBalance { result.append(("Баланс белого", value)) }
        return result
    }

    private var authorRows: [(String, String)] {
        guard let metadata else { return [] }
        var result: [(String, String)] = []
        if let value = metadata.artist { result.append(("Автор", value)) }
        if let value = metadata.copyrightNotice { result.append(("Права", value)) }
        return result
    }

    // MARK: - Составные части

    @ViewBuilder
    private func rows(_ items: [(String, String)], title: String) -> some View {
        if !items.isEmpty {
            section(title) {
                ForEach(items, id: \.0) { row($0.0, $0.1) }
            }
        }
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) { content() }
        }
    }

    private func row(_ label: String, _ value: String,
                     truncateMiddle: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 122, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .lineLimit(1)
                .truncationMode(truncateMiddle ? .middle : .tail)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(value)
        }
    }
}

/// Карта места съёмки. Показывается, только если камера записала координаты.
private struct CaptureMapView: View {
    let latitude: Double
    let longitude: Double

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))) {
                Marker("", coordinate: coordinate).tint(.red)
            }
            .frame(height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .allowsHitTesting(false)

            HStack(spacing: 8) {
                Text(String(format: "%.5f, %.5f", latitude, longitude))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
                Button("Открыть в Картах") { openInMaps() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
            }
        }
    }

    private func openInMaps() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = "Место съёмки"
        item.openInMaps()
    }
}
