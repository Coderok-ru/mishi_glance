//
//  InfoPanelView.swift
//  Mishi Glance
//

import SwiftUI

struct InfoPanelView: View {
    let metadata: ImageMetadata?
    let fileName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let fileName {
                Text(fileName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if let metadata {
                Divider()
                VStack(alignment: .leading, spacing: 5) {
                    row("Размеры", "\(metadata.pixelWidth) × \(metadata.pixelHeight)")
                    row("Размер файла", ByteFormat.string(metadata.fileSize))
                    row("Формат", metadata.formatDescription)
                    if let colorModel = metadata.colorModel {
                        row("Цвет", colorModel)
                    }
                }

                let camera = cameraRows
                if !camera.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(camera, id: \.0) { row($0.0, $0.1) }
                    }
                }
            } else {
                Text("Метаданные недоступны")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 268, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.1))
        )
        .shadow(color: .black.opacity(0.35), radius: 16, y: 4)
    }

    private var cameraRows: [(String, String)] {
        guard let metadata else { return [] }
        var rows: [(String, String)] = []

        let camera = [metadata.cameraMake, metadata.cameraModel]
            .compactMap { $0 }
            .joined(separator: " ")
        if !camera.isEmpty { rows.append(("Камера", camera)) }

        if let lens = metadata.lens { rows.append(("Объектив", lens)) }
        if let date = metadata.captureDate {
            rows.append(("Снято", date.formatted(date: .abbreviated, time: .shortened)))
        }

        let exposure = [metadata.exposureTime, metadata.aperture, metadata.iso, metadata.focalLength]
            .compactMap { $0 }
            .joined(separator: " · ")
        if !exposure.isEmpty { rows.append(("Экспозиция", exposure)) }

        return rows
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }
}
