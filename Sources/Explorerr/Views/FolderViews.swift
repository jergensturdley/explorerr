import SwiftUI
import AppKit

// MARK: - Details view (default Windows view)

struct DetailsView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    headerRow(p)
                    Rectangle().fill(p.divider).frame(height: 1)
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tab.sortedItems.enumerated()), id: \.element.id) { index, item in
                            DetailsRow(item: item, index: index, tab: tab, app: app, p: p)
                                .id(item.id)
                                .modifier(ReportsBandFrame(id: item.id))
                        }
                    }
                    Color.clear.frame(height: 400).allowsHitTesting(false) // bottom padding + click space
                }
                .modifier(BandSelectable(tab: tab))
            }
            .onChange(of: tab.selection) { sel in
                // Minimal reveal (nil anchor): no jump when the row is already visible,
                // and never during a rubber-band drag.
                if !tab.isBandSelecting, sel.count == 1, let id = sel.first {
                    proxy.scrollTo(id)
                }
            }
        }
    }

    // MARK: header

    // Header cells mirror the row cells exactly (same widths + 8pt padding, no extra
    // divider views in the layout) so column labels line up with the data below them.
    @ViewBuilder
    private func headerRow(_ p: Win11.Palette) -> some View {
        HStack(spacing: 0) {
            headerCell(.name, p, width: nil)
            headerCell(.modified, p, width: tab.columnWidths["modified"] ?? 150, resizeKey: "modified", defaultWidth: 150)
            headerCell(.type, p, width: tab.columnWidths["type"] ?? 150, resizeKey: "type", defaultWidth: 150)
            headerCell(.size, p, width: tab.columnWidths["size"] ?? 96, alignTrailing: true, resizeKey: "size", defaultWidth: 96)
        }
        .frame(height: 30)
        .padding(.horizontal, 12)
    }

    private func headerCell(_ key: SortKey, _ p: Win11.Palette, width: CGFloat?,
                            alignTrailing: Bool = false, resizeKey: String? = nil,
                            defaultWidth: CGFloat = 150) -> some View {
        Button {
            tab.toggleSort(key)
        } label: {
            HStack(spacing: 4) {
                if alignTrailing { Spacer(minLength: 0) }
                Text(key.title)
                    .font(.system(size: 12))
                    .foregroundStyle(tab.sortKey == key ? p.textPrimary : p.textSecondary)
                if tab.sortKey == key {
                    Image(systemName: tab.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(p.textSecondary)
                }
            }
            .frame(width: width, alignment: alignTrailing ? .trailing : .leading)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .overlay(alignment: .leading) {
            // Resize handle floats over the column boundary so it adds no layout width.
            if let rk = resizeKey {
                resizeHandle(p, key: rk, defaultWidth: defaultWidth)
                    .offset(x: -4.5)
            }
        }
    }

    private func resizeHandle(_ p: Win11.Palette, key: String, defaultWidth: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 9)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .overlay(Rectangle().fill(p.divider).frame(width: 1).padding(.vertical, 6))
            .onTapGesture(count: 2) { autoFitColumn(key) }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if dragStartWidth == nil { dragStartWidth = tab.columnWidths[key] ?? defaultWidth }
                        // Columns are right-anchored: dragging right shrinks this column so the
                        // boundary follows the cursor.
                        let proposed = (dragStartWidth ?? defaultWidth) - value.translation.width
                        tab.columnWidths[key] = min(460, max(62, proposed))
                    }
                    .onEnded { _ in dragStartWidth = nil }
            )
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
    }

    /// Dolphin-style double-click on a column divider: auto-fit to contents.
    private func autoFitColumn(_ key: String) {
        let body = NSFont.systemFont(ofSize: 13)
        let secondary = NSFont.systemFont(ofSize: 12.5)
        func width(_ text: String, _ font: NSFont) -> CGFloat {
            (text as NSString).size(withAttributes: [.font: font]).width
        }
        let header: String
        switch key {
        case "modified": header = SortKey.modified.title
        case "type": header = SortKey.type.title
        case "size": header = SortKey.size.title
        default: header = SortKey.name.title
        }
        var maxWidth = width(header, secondary)
        for item in tab.sortedItems.prefix(500) {
            let text: String
            switch key {
            case "modified": text = Fmt.dateTime.string(from: item.modified ?? .distantPast)
            case "type": text = item.kind
            case "size": text = item.isDirectory ? "" : Fmt.size(item.sizeBytes)
            default: text = item.displayName
            }
            maxWidth = max(maxWidth, width(text, key == "name" ? body : secondary))
        }
        let extra: CGFloat = key == "name" ? 58 : 34
        tab.columnWidths[key] = min(460, max(62, maxWidth + extra))
    }

}

struct DetailsRow: View {
    let item: FSItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    let p: Win11.Palette
    @State private var hovering = false

    private var selected: Bool { tab.selection.contains(item.id) }
    private var isCut: Bool { app.cutURLs.contains(item.url.path) }
    private var renaming: Bool { tab.renamingID == item.id }

    var body: some View {
        HStack(spacing: 0) {
            icon
                .frame(width: 24, alignment: .leading)

            nameCell
                .frame(maxWidth: .infinity, alignment: .leading)

            fixedCell(Fmt.dateTime.string(from: item.modified ?? Date.distantPast), width: tab.columnWidths["modified"] ?? 150)
            fixedCell(item.kind, width: tab.columnWidths["type"] ?? 150)
            fixedCell(item.isDirectory ? "" : Fmt.size(item.sizeBytes), width: tab.columnWidths["size"] ?? 96, trailing: true)
        }
        .frame(height: app.prefs.compactRows ? 26 : Win11.Metrics.rowHeightDetails)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(selected ? p.selectionBG : hovering ? p.hoverRow : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(selected && tab.selection.count == 1 ? p.selectionBorder : Color.clear, lineWidth: 1)
        )
        .opacity(isCut ? 0.5 : 1)
        .opacity(item.isHidden ? 0.55 : 1)
        .modifier(ItemInteractions(item: item, index: index, tab: tab, app: app))
        .onHover { hovering = $0 }
    }

    @ViewBuilder
    private var icon: some View {
        if item.category == .image || item.category == .video || item.url.pathExtension.lowercased() == "pdf" {
            ThumbnailView(item: item, size: 21, cornerRadius: 3)
        } else {
            FileIconView(item: item, size: 19)
        }
    }

    @ViewBuilder
    private var nameCell: some View {
        HStack(spacing: 6) {
            if renaming {
                InlineRenameField(initialName: item.displayName) { newName in
                    tab.renamingID = nil
                    FileOps.renameItem(item, to: newName, app: app)
                } onCancel: {
                    tab.renamingID = nil
                }
            } else {
                Text(displayName)
                    .font(Win11.Fonts.body)
                    .foregroundStyle(selected ? p.selectionText : p.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
        }
    }

    private var displayName: String {
        app.prefs.showExtensions || item.isDirectory ? item.displayName : item.nameWithoutExtension
    }

    private func fixedCell(_ text: String, width: CGFloat, trailing: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(p.textSecondary)
            .lineLimit(1)
            .frame(width: width, alignment: trailing ? .trailing : .leading)
            .padding(.horizontal, 8)
    }
}

// MARK: - Icons grid

struct IconsGridView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    private var iconSize: CGFloat { tab.viewMode.iconSize ?? 64 }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollViewReader { proxy in
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: max(100, iconSize + 46)), spacing: 6)],
                    spacing: 8
                ) {
                    ForEach(Array(tab.sortedItems.enumerated()), id: \.element.id) { index, item in
                        IconTile(item: item, index: index, tab: tab, app: app, iconSize: iconSize)
                            .id(item.id)
                            .modifier(ReportsBandFrame(id: item.id))
                    }
                }
                .padding(12)
                .modifier(BandSelectable(tab: tab))
                .onChange(of: tab.selection) { sel in
                    if !tab.isBandSelecting, sel.count == 1, let id = sel.first {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }
}

struct IconTile: View {
    let item: FSItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    let iconSize: CGFloat
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    private var selected: Bool { tab.selection.contains(item.id) }
    private var isCut: Bool { app.cutURLs.contains(item.url.path) }
    private var renaming: Bool { tab.renamingID == item.id }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 6) {
            ZStack {
                if item.category == .image || item.category == .video || item.url.pathExtension.lowercased() == "pdf" {
                    ThumbnailView(item: item, size: iconSize, cornerRadius: 6)
                } else {
                    FileIconView(item: item, size: iconSize)
                }
            }
            .frame(height: iconSize + 6)

            if renaming {
                InlineRenameField(initialName: item.displayName) { newName in
                    tab.renamingID = nil
                    FileOps.renameItem(item, to: newName, app: app)
                } onCancel: {
                    tab.renamingID = nil
                }
                .frame(width: iconSize + 40)
            } else {
                Text(app.prefs.showExtensions || item.isDirectory ? item.displayName : item.nameWithoutExtension)
                    .font(.system(size: 12))
                    .foregroundStyle(selected ? p.selectionText : p.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: iconSize + 40)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .fill(selected ? p.selectionBG : hovering ? p.hoverRow : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .strokeBorder(selected && tab.selection.count == 1 ? p.selectionBorder : Color.clear, lineWidth: 1)
        )
        .opacity(isCut ? 0.5 : 1)
        .opacity(item.isHidden ? 0.55 : 1)
        .modifier(ItemInteractions(item: item, index: index, tab: tab, app: app))
        .onHover { hovering = $0 }
    }
}

// MARK: - List view (flowing columns)

struct ListView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        GeometryReader { geo in
            let rowsPerColumn = max(1, Int(geo.size.height / (app.prefs.compactRows ? 24 : 28)))
            ScrollView(.horizontal, showsIndicators: true) {
                ScrollViewReader { proxy in
                    HStack(alignment: .top, spacing: 28) {
                        let chunks = stride(from: 0, to: tab.sortedItems.count, by: rowsPerColumn).map {
                            Array(tab.sortedItems[$0..<min($0 + rowsPerColumn, tab.sortedItems.count)])
                        }
                        ForEach(Array(chunks.enumerated()), id: \.offset) { chunkIndex, chunk in
                            VStack(spacing: 0) {
                                ForEach(Array(chunk.enumerated()), id: \.element.id) { localIndex, item in
                                    ListRow(item: item, index: chunkIndex * rowsPerColumn + localIndex, tab: tab, app: app)
                                        .id(item.id)
                                        .modifier(ReportsBandFrame(id: item.id))
                                }
                            }
                            .frame(width: 240, alignment: .leading)
                        }
                    }
                    .padding(10)
                    .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                    .modifier(BandSelectable(tab: tab))
                    .onChange(of: tab.selection) { sel in
                        if !tab.isBandSelecting, sel.count == 1, let id = sel.first {
                            proxy.scrollTo(id)
                        }
                    }
                }
            }
        }
    }
}

struct ListRow: View {
    let item: FSItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 7) {
            FileIconView(item: item, size: 17)
            Text(app.prefs.showExtensions || item.isDirectory ? item.displayName : item.nameWithoutExtension)
                .font(Win11.Fonts.body)
                .foregroundStyle(tab.selection.contains(item.id) ? p.selectionText : p.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .frame(height: app.prefs.compactRows ? 24 : Win11.Metrics.rowHeightList)
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(tab.selection.contains(item.id) ? p.selectionBG : hovering ? p.hoverRow : Color.clear)
        )
        .opacity(app.cutURLs.contains(item.url.path) ? 0.5 : 1)
        .opacity(item.isHidden ? 0.55 : 1)
        .modifier(ItemInteractions(item: item, index: index, tab: tab, app: app))
        .onHover { hovering = $0 }
    }
}

// MARK: - Tiles view

struct TilesView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            ScrollViewReader { proxy in
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 8)], spacing: 6) {
                    ForEach(Array(tab.sortedItems.enumerated()), id: \.element.id) { index, item in
                        TileView(item: item, index: index, tab: tab, app: app)
                            .id(item.id)
                            .modifier(ReportsBandFrame(id: item.id))
                    }
                }
                .padding(10)
                .modifier(BandSelectable(tab: tab))
                .onChange(of: tab.selection) { sel in
                    if !tab.isBandSelecting, sel.count == 1, let id = sel.first {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
    }
}

struct TileView: View {
    let item: FSItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    private var selected: Bool { tab.selection.contains(item.id) }
    private var renaming: Bool { tab.renamingID == item.id }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 11) {
            ZStack {
                if item.category == .image || item.category == .video || item.url.pathExtension.lowercased() == "pdf" {
                    ThumbnailView(item: item, size: 46, cornerRadius: 4)
                } else {
                    FileIconView(item: item, size: 44)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    InlineRenameField(initialName: item.displayName) { newName in
                        tab.renamingID = nil
                        FileOps.renameItem(item, to: newName, app: app)
                    } onCancel: {
                        tab.renamingID = nil
                    }
                } else {
                    Text(app.prefs.showExtensions || item.isDirectory ? item.displayName : item.nameWithoutExtension)
                        .font(Win11.Fonts.body)
                        .foregroundStyle(selected ? p.selectionText : p.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(item.kind)\(item.isDirectory ? "" : " · \(Fmt.size(item.sizeBytes))")")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .fill(selected ? p.selectionBG : hovering ? p.hoverRow : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .strokeBorder(selected && tab.selection.count == 1 ? p.selectionBorder : Color.clear, lineWidth: 1)
        )
        .opacity(app.cutURLs.contains(item.url.path) ? 0.5 : 1)
        .opacity(item.isHidden ? 0.55 : 1)
        .modifier(ItemInteractions(item: item, index: index, tab: tab, app: app))
        .onHover { hovering = $0 }
    }
}
