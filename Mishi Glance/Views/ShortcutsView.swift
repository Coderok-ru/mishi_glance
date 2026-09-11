//
//  ShortcutsView.swift
//  Mishi Glance
//

import SwiftUI

/// Клавиша в рамке — как на настоящей клавиатуре.
struct KeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .medium))
            .frame(minWidth: 22)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.12)))
    }
}

struct ShortcutsView: View {
    private let columns = [GridItem(.flexible(), spacing: 24), GridItem(.flexible(), spacing: 24)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                ForEach(ShortcutCatalog.groups) { group in
                    VStack(alignment: .leading, spacing: 9) {
                        Label(group.title, systemImage: group.symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.items) { item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                HStack(spacing: 3) {
                                    ForEach(Array(item.keys.enumerated()), id: \.offset) { _, key in
                                        KeyCap(label: key)
                                    }
                                }
                                .frame(width: 92, alignment: .leading)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.title)
                                        .font(.system(size: 12))
                                        .fixedSize(horizontal: false, vertical: true)
                                    if let alternate = item.alternateLabel {
                                        Text("или \(alternate)")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    // Колонки разной длины — прижимаем группы к верху строки,
                    // иначе короткая повисает по центру с пустотой сверху.
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .padding(22)
        }
        .frame(width: 700, height: 520)
    }
}
