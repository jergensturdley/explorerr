import SwiftUI
import ImageIO

/// Windows 11-style details pane: preview + metadata for the selection
/// (or the current folder when nothing is selected). Shown in the active pane.
struct DetailsPaneView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    @State private var item: FSItem?
    @State private var stats: (bytes: Int64, files: Int, folders: Int) = (0, 0, 0)
    @State private var imageDims: String? = nil
    @State private var loadedURL: URL?

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                header(p)

                if let current = item {
                    preview(current)
                    metadata(current, p)
                    actions(current, p)
                } else {
                    Spacer(minLength: 12)
                    Text("Select an item to see details.")
                        .font(.system(size: 12))
                        .foregroundStyle(p.textSecondary)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 264)
        .background(p.contentBG)
        .overlay(alignment: .leading) {
            Rectangle().fill(p.divider).frame(width: 1)
        }
        .onAppear { refresh() }
        .onChange(of: tab.selection) { _ in refresh() }
        .onChange(of: tab.location) { _ in refresh() }
        .onChange(of: tab.items.count) { _ in refresh() }
    }

    // MARK: data

    private func refresh() {
        let selected = tab.selectedItems.first
        let fallbackFolder = tab.currentFolderURL.map {
            FSItem.virtual($0, name: $0.lastPathComponent, kind: "File folder", isDirectory: true)
        }
        let current = selected ?? fallbackFolder
        guard current?.url != loadedURL else { return }
        loadedURL = current?.url
        item = current
        stats = (0, 0, 0)
        imageDims = nil

        guard let url = current?.url else { return }
        let isDir = current?.isDirectory ?? false
        Task {
            if isDir {
                let s = await Task.detached(priority: .utility) {
                    DirectoryLoader.directoryStats(url)
                }.value
                stats = s
            } else {
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                stats = (Int64((attrs?[.size] as? NSNumber)?.intValue ?? 0), 0, 0)
                if current?.category == .image {
                    imageDims = await Task.detached(priority: .utility) { () -> String? in
                        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [String: Any],
                              let w = props[kCGImagePropertyPixelWidth as String] as? Int,
                              let h = props[kCGImagePropertyPixelHeight as String] as? Int else { return nil }
                        return "\(w) × \(h) px"
                    }.value
                }
            }
        }
    }

    // MARK: sections

    private func header(_ p: Win11.Palette) -> some View {
        Text(item.map { $0.isDirectory ? "Folder details" : "File details" } ?? "Details")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(p.textSecondary)
    }

    @ViewBuilder
    private func preview(_ current: FSItem) -> some View {
        if current.category == .image || current.category == .video
            || current.url.pathExtension.lowercased() == "pdf" {
            ThumbnailView(item: current, size: 232, cornerRadius: 8)
                .frame(maxWidth: .infinity)
        } else {
            HStack {
                Spacer()
                FileIconView(item: current, size: 96)
                Spacer()
            }
            .padding(.vertical, 10)
        }
    }

    private func metadata(_ current: FSItem, _ p: Win11.Palette) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(app.prefs.showExtensions || current.isDirectory ? current.displayName : current.nameWithoutExtension)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let dims = imageDims {
                row(p, "Dimensions:", dims)
            }
            row(p, "Type:", current.kind)
            if current.isDirectory {
                row(p, "Contains:", stats.files + stats.folders > 0 ? Fmt.counts(folders: stats.folders, files: stats.files) : "…")
                row(p, "Size:", stats.bytes > 0 ? stats.bytes.string : "…")
            } else {
                row(p, "Size:", stats.bytes.string)
            }
            if let modified = current.modified { row(p, "Modified:", Fmt.dateTime.string(from: modified)) }
            if let created = current.created { row(p, "Created:", Fmt.dateTime.string(from: created)) }
        }
    }

    private func actions(_ current: FSItem, _ p: Win11.Palette) -> some View {
        VStack(spacing: 8) {
            if !current.isDirectory {
                HStack(spacing: 8) {
                    Button {
                        QuickLook.toggle(items: tab.selectedItems.isEmpty ? [current] : tab.selectedItems)
                    } label: { Label("Preview", systemImage: "eye").frame(maxWidth: .infinity) }
                        .buttonStyle(WinStandardButtonStyle())

                    Button {
                        FileOps.open(current.url, app: app)
                    } label: { Label("Open", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity) }
                        .buttonStyle(WinStandardButtonStyle())
                }
            } else {
                Button {
                    tab.navigate(.folder(current.url))
                } label: { Label("Open", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity) }
                    .buttonStyle(WinStandardButtonStyle())
            }

            Button {
                app.activeSheet = .properties(current.url)
            } label: { Label("Properties", systemImage: "info.circle").frame(maxWidth: .infinity) }
                .buttonStyle(WinStandardButtonStyle())
        }
        .padding(.top, 4)
    }

    private func row(_ p: Win11.Palette, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(p.textSecondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.system(size: 11.5))
                .foregroundStyle(p.textPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
    }
}
