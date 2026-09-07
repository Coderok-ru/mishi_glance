//
//  HistogramView.swift
//  Mishi Glance
//

import SwiftUI

/// Что показывать: все каналы разом, яркость или отдельный канал.
enum HistogramChannel: String, CaseIterable, Identifiable {
    case rgb = "RGB"
    case luma = "L"
    case red = "R"
    case green = "G"
    case blue = "B"

    var id: String { rawValue }
}

struct HistogramView: View {
    let histogram: ImageHistogram

    @State private var channel: HistogramChannel = .rgb

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Canvas { context, size in
                switch channel {
                case .rgb:
                    // Каналы накладываются со смешиванием — там, где они
                    // совпадают, получается светлое, как в редакторах.
                    draw(histogram.red, in: context, size: size, color: .red, opacity: 0.55)
                    draw(histogram.green, in: context, size: size, color: .green, opacity: 0.55)
                    draw(histogram.blue, in: context, size: size, color: .blue, opacity: 0.55)
                case .luma:
                    draw(histogram.luma, in: context, size: size, color: .white, opacity: 0.75)
                case .red:
                    draw(histogram.red, in: context, size: size, color: .red, opacity: 0.8)
                case .green:
                    draw(histogram.green, in: context, size: size, color: .green, opacity: 0.8)
                case .blue:
                    draw(histogram.blue, in: context, size: size, color: .blue, opacity: 0.8)
                }
            }
            .frame(height: 88)
            .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) { marker(.blue, at: .leading) }
            .overlay(alignment: .topTrailing) { marker(.orange, at: .trailing) }

            HStack(spacing: 10) {
                Text(means)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer(minLength: 4)
                ForEach(HistogramChannel.allCases) { option in
                    Button {
                        channel = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 10, weight: channel == option ? .bold : .regular))
                            .foregroundStyle(tint(for: option, active: channel == option))
                    }
                    .buttonStyle(.plain)
                    .help("Показать канал \(option.rawValue)")
                }
            }
        }
    }

    private var means: String {
        String(format: "R̄:%.0f  Ḡ:%.0f  B̄:%.0f",
               histogram.meanRed, histogram.meanGreen, histogram.meanBlue)
    }

    private func tint(for option: HistogramChannel, active: Bool) -> Color {
        guard active else { return .secondary }
        switch option {
        case .rgb, .luma: return .primary
        case .red: return .red
        case .green: return .green
        case .blue: return .blue
        }
    }

    /// Треугольные отметки чёрной и белой точек, как в редакторах.
    private func marker(_ color: Color, at edge: HorizontalAlignment) -> some View {
        Triangle()
            .fill(color)
            .frame(width: 9, height: 6)
            .padding(edge == .leading ? .leading : .trailing, 2)
            .padding(.top, 2)
    }

    private func draw(_ bins: [UInt32], in context: GraphicsContext,
                      size: CGSize, color: Color, opacity: Double) {
        let peak = Double(max(histogram.peak, 1))
        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (index, value) in bins.enumerated() {
            let x = size.width * Double(index) / Double(bins.count - 1)
            // Логарифм: иначе один доминирующий тон прижимает всё остальное
            // к нулю и график читается как пустой.
            let normalized = log1p(Double(value)) / log1p(peak)
            path.addLine(to: CGPoint(x: x, y: size.height * (1 - normalized)))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(color.opacity(opacity)))
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
