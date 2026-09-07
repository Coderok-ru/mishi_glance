//
//  BrowserView.swift
//  Mishi Glance
//
//  Every image in the current folder, as a compact list or a grid.
//  Thumbnails come from a cache of their own so browsing a big folder never
//  evicts the frames the viewer is showing.
//

import SwiftUI

struct BrowserView: View {
    let controller: ViewerController

    @AppStorage(SettingsKey.browserViewMode) private var modeRaw = BrowserViewMode.list.rawValue
    @State private var query = ""

    private var mode: BrowserViewMode {
        BrowserViewMode(rawValue: modeRaw) ?? .list
    }

    private var shown: [ImageEntry] {
        ImageEntry.filter(controller.folder.entries, query: query)
    }

    private let gridColumns = [GridItem(.adaptive(minimum: 108, maximum: 168), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    switch mode {
                    case .list: listContent
                    case .grid: gridContent
                    }
                }
                .onChange(of: controller.folder.currentIndex) { scroll(proxy) }
                .onChange(of: modeRaw) { scroll(proxy) }
                .onAppear { scroll(proxy) }
            }
        }
        .frame(minWidth: 320, idealWidth: 460, maxWidth: .infinity,
               minHeight: 280, idealHeight: 720, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay {
            if controller.folder.isEmpty {
                ContentUnavailableView(
                    "Нет изображений",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("Откройте изображение, чтобы увидеть содержимое папки.")
                )
            } else if shown.isEmpty {
                ContentUnavailableView(
                    "Ничего не найдено",
                    systemImage: "magnifyingglass",
                    description: Text("В папке нет файлов с «\(query)» в имени.")
                )
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy) {
        guard let current = controller.folder.current else { return }
        withAnimation { proxy.scrollTo(current.id, anchor: .center) }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
        HStack(spacing: 12) {
            Text(query.isEmpty
                 ? imageCountText(controller.folder.count)
                 : "Найдено: \(shown.count) из \(controller.folder.count)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            Picker("", selection: $modeRaw) {
                Image(systemName: "list.bullet")
                    .tag(BrowserViewMode.list.rawValue)
                Image(systemName: "square.grid.2x2")
                    .tag(BrowserViewMode.grid.rawValue)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)
            .help("Списком или сеткой")
        }

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            TextField("Поиск по имени", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Очистить")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Russian needs three plural forms: 1 изображение, 2 изображения, 5 изображений.
    private func imageCountText(_ count: Int) -> String {
        let remainder100 = count % 100
        let remainder10 = count % 10
        let word: String
        if (11...14).contains(remainder100) {
            word = "изображений"
        } else if remainder10 == 1 {
            word = "изображение"
        } else if (2...4).contains(remainder10) {
            word = "изображения"
        } else {
            word = "изображений"
        }
        return "\(count) \(word)"
    }

    // MARK: - List

    private var listContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(shown) { entry in
                BrowserListRow(
                    entry: entry,
                    isCurrent: entry.url == controller.folder.current?.url
                )
                .onTapGesture { controller.show(entry: entry) }
                .id(entry.id)
            }
        }
    }

    // MARK: - Grid

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(shown) { entry in
                let isCurrent = entry.url == controller.folder.current?.url
                VStack(spacing: 5) {
                    ThumbnailImage(url: entry.url, maxPixel: 320, cornerRadius: 7,
                                   width: nil, height: 104, contentMode: .fit)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 3)
                        )
                    Text(entry.name)
                        .font(.system(size: 10))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture { controller.show(entry: entry) }
                .help("\(entry.name) · \(ByteFormat.string(entry.fileSize))")
                .id(entry.id)
            }
        }
        .padding(14)
    }
}

/// One row of the file list: fixed-height, thumbnail then name.
struct BrowserListRow: View {
    let entry: ImageEntry
    let isCurrent: Bool

    static let thumbnailSide: CGFloat = 38
    static let verticalPadding: CGFloat = 7

    var body: some View {
        HStack(spacing: 10) {
            ThumbnailImage(url: entry.url, maxPixel: 160, cornerRadius: 4,
                           width: Self.thumbnailSide, height: Self.thumbnailSide,
                           contentMode: .fill)
            Text(entry.name)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Self.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isCurrent ? Color.primary.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .help("\(entry.name) · \(ByteFormat.string(entry.fileSize))")
    }
}

/// Async thumbnail, shared by both layouts.
///
/// The frame is applied *inside*, before clipping: a `.clipShape` placed after
/// an outer `.frame` clips to the image's natural size instead, which let wide
/// pictures spill over the filename and stretch the row.
struct ThumbnailImage: View {
    let url: URL
    let maxPixel: Int
    let cornerRadius: CGFloat
    let width: CGFloat?
    let height: CGFloat
    let contentMode: ContentMode

    @State private var image: CGImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black.opacity(0.22))
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: url) {
            image = await ImageLoader.thumbnails.image(for: url, maxPixel: maxPixel)?.image
        }
    }
}
