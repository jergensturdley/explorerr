import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The Shelf: a staging strip docked above the status/terminal area. Files sit here
/// in limbo while the user browses, then get copied or moved into the active folder.
/// Shown whenever it has content, or while an internal drag is in flight so it can
/// act as a drop target even when empty.
struct ShelfBar: View {
    @ObservedObject var app: AppModel
    let windowModel: WindowModel

    @EnvironmentObject var theme: Theme
    @State private var dropTargeted = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Image(systemName: "tray.full")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(p.accentText)
                Text("Shelf")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                if !app.shelf.isEmpty {
                    Text("\(app.shelf.count)")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(p.accentText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(p.selectionBG))
                }
            }

            if app.shelf.isEmpty {
                Text("Drop files here to keep them handy while you browse")
                    .font(Win11.Fonts.bodySecondary)
                    .foregroundStyle(p.textSecondary)
                Spacer(minLength: 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(app.shelf, id: \.self) { path in
                            ShelfChip(path: path, app: app, windowModel: windowModel)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button("Copy here") { place(move: false) }
                    .buttonStyle(WinStandardButtonStyle())
                    .help("Copy every shelved item into the current folder")

                Button("Move here") { place(move: true) }
                    .buttonStyle(WinStandardButtonStyle())
                    .help("Move every shelved item into the current folder (clears the Shelf)")

                Button {
                    app.shelf = []
                } label: {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 13))
                }
                .buttonStyle(WinIconButtonStyle())
                .help("Clear the Shelf (files stay where they are)")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(dropTargeted ? p.selectionBG.opacity(0.55) : p.sidebarTint)
        .overlay(alignment: .top) { Rectangle().fill(p.divider).frame(height: 1) }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTargeted) { providers in
            Task {
                let urls = await FolderContentView.loadURLs(from: providers)
                guard !urls.isEmpty else { return }
                app.addToShelf(urls)
                app.draggingURLs = []
            }
            return true
        }
    }

    /// Copy or move everything on the Shelf into the active tab's folder.
    private func place(move: Bool) {
        let tab = windowModel.activeTab
        guard let dest = tab.currentFolderURL else {
            app.toast("Navigate to a folder first")
            return
        }
        let existing = app.shelf.filter { FileManager.default.fileExists(atPath: $0) }
        let urls = existing.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else {
            app.shelf = []
            return
        }
        Task {
            await FileOps.transfer(urls, to: dest, move: move, app: app, tab: tab)
            if move { app.shelf = [] } else { app.shelf = existing }
        }
    }
}

private struct ShelfChip: View {
    let path: String
    @ObservedObject var app: AppModel
    let windowModel: WindowModel

    @EnvironmentObject var theme: Theme
    @State private var hovering = false
    @State private var lastClickAt = Date.distantPast

    var body: some View {
        let p = Win11.palette(theme.scheme)
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        let item = FSItem.virtual(url, name: url.lastPathComponent, kind: "", isDirectory: isDir.boolValue)

        HStack(spacing: 6) {
            FileIconView(item: item, size: 16)
            Text(url.lastPathComponent)
                .font(Win11.Fonts.bodySecondary)
                .foregroundStyle(exists ? p.textPrimary : p.textDisabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 150)
            Button {
                app.removeFromShelf(path)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(p.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove from Shelf")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .fill(hovering ? p.controlFillHover : p.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusControl, style: .continuous)
                .strokeBorder(p.stroke, lineWidth: 1)
        )
        .opacity(exists ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        // Drag a chip out: drop into any pane (or another app) to copy it there.
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture {
            // Double-click reveals the file in its parent folder.
            let now = Date()
            if now.timeIntervalSince(lastClickAt) < NSEvent.doubleClickInterval {
                let tab = windowModel.activeTab
                tab.pendingRevealID = path
                tab.navigate(.folder(url.deletingLastPathComponent()))
            }
            lastClickAt = now
        }
        .help(path)
    }
}
