import SwiftUI
import AppKit

// MARK: - Home (Win11 Home page: Quick access cards + Recent files)

struct HomeView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    private var quickAccess: [URL] {
        var urls: [URL] = []
        for pin in app.pins { urls.append(URL(fileURLWithPath: pin, isDirectory: true)) }
        let home = DirectoryLoader.homeURL
        for special in ["Desktop", "Downloads", "Documents", "Pictures", "Music", "Videos"] {
            let url = home.appendingPathComponent(special, isDirectory: true)
            if !app.isPinned(url.standardizedFileURL.path) { urls.append(url) }
        }
        return urls
    }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("Quick access", systemImage: "pin.fill")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 226), spacing: 8)], spacing: 8) {
                    ForEach(quickAccess, id: \.path) { url in
                        QuickAccessCard(url: url, tab: tab, app: app)
                    }
                }

                if !app.recents.isEmpty {
                    Rectangle().fill(p.divider).frame(height: 1)

                    sectionHeader("Recent files", systemImage: "clock.arrow.circlepath")
                    VStack(spacing: 0) {
                        ForEach(Array(app.recents.enumerated()), id: \.element.path) { index, recent in
                            RecentRow(recent: recent, index: index, tab: tab, app: app)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Win11.palette(theme.scheme).accentText)
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Win11.palette(theme.scheme).textPrimary)
        }
    }
}

struct QuickAccessCard: View {
    let url: URL
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 11) {
            FolderIconView(variant: FolderVariant.forFolderURL(url), size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(Win11.Fonts.body)
                    .foregroundStyle(p.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 60)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .fill(hovering ? p.controlFillHover : p.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .strokeBorder(p.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { tab.navigate(.folder(url)) }
        .onTapGesture { }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { tab.navigate(.folder(url)) }
            Button("Open in new tab") {
                NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: Location.folder(url))
            }
            Divider()
            Button(app.isPinned(url.standardizedFileURL.path) ? "Unpin from Quick access" : "Pin to Quick access") {
                app.togglePin(url)
            }
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.path, forType: .string)
            }
            Button("Properties") { app.activeSheet = .properties(url) }
        }
    }

    private var subtitle: String {
        let path = url.path
        if path.contains("/Desktop") { return "Desktop" }
        return (path as NSString).deletingLastPathComponent.replacingOccurrences(of: DirectoryLoader.homeURL.path, with: "~")
    }
}

struct RecentRow: View {
    let recent: RecentItem
    let index: Int
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        let url = URL(fileURLWithPath: recent.path)
        let item = FSItem.virtual(url, name: recent.name, kind: "", isDirectory: false)
        return HStack(spacing: 10) {
            FileIconView(item: item, size: 22)
            Text(recent.name)
                .font(Win11.Fonts.body)
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .frame(width: 240, alignment: .leading)
            Text(Fmt.dateTime.string(from: recent.date))
                .font(.system(size: 12.5))
                .foregroundStyle(p.textSecondary)
            Spacer(minLength: 8)
            Text((recent.path as NSString).deletingLastPathComponent.replacingOccurrences(of: DirectoryLoader.homeURL.path, with: "~"))
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(hovering ? p.hoverRow : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { FileOps.open(url, app: app) }
        .onTapGesture { }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { FileOps.open(url, app: app) }
            Button("Open file location") {
                tab.pendingRevealID = url.path
                tab.navigate(.folder(url.deletingLastPathComponent()))
            }
            Divider()
            Button("Copy path") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recent.path, forType: .string)
            }
            Button("Remove from Recent") {
                app.recents.removeAll { $0.path == recent.path }
            }
        }
    }
}

// MARK: - This PC (folders + devices and drives with usage bars)

struct ThisPCView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var drives: [DriveInfo] = []

    private var userFolders: [URL] {
        let home = DirectoryLoader.homeURL
        return ["Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Folders")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                    .padding(.leading, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 226), spacing: 8)], spacing: 8) {
                    ForEach(userFolders, id: \.path) { url in
                        QuickAccessCard(url: url, tab: tab, app: app)
                    }
                }

                Text("Devices and drives")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                    .padding(.leading, 4)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 226), spacing: 8)], spacing: 8) {
                    ForEach(drives) { drive in
                        DriveCard(drive: drive, tab: tab, app: app)
                    }
                }
            }
            .padding(16)
        }
        .task {
            drives = await Task.detached(priority: .userInitiated) { DirectoryLoader.volumes() }.value
        }
    }
}

struct DriveCard: View {
    let drive: DriveInfo
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var hovering = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 11) {
                DriveIconView(drive: drive, size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(drive.name + (drive.isBoot ? " (System)" : ""))
                        .font(Win11.Fonts.body)
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(1)
                    Text(drive.isNetwork ? "Network drive" : drive.isRemovable ? "Removable drive" : (drive.isInternal ? "Local disk" : "External drive"))
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.textSecondary)
                }
                Spacer(minLength: 0)
            }

            if drive.isReadable {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.controlFillPressed)
                        Capsule()
                            .fill(drive.usedFraction > 0.9 ? p.danger : p.accent)
                            .frame(width: max(4, geo.size.width * drive.usedFraction))
                    }
                }
                .frame(height: 6)

                Text("\(drive.freeBytes.string) free of \(drive.totalBytes.string)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.textSecondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .fill(hovering ? p.controlFillHover : p.controlFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Win11.Metrics.cornerRadiusTile, style: .continuous)
                .strokeBorder(p.stroke, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { tab.navigate(.folder(drive.url)) }
        .onTapGesture { }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { tab.navigate(.folder(drive.url)) }
            Button("Open in new tab") {
                NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: Location.folder(drive.url))
            }
            Divider()
            if drive.isRemovable {
                Button("Eject") {
                    try? NSWorkspace.shared.unmountAndEjectDevice(at: drive.url)
                }
            }
            Button("Properties") { app.activeSheet = .properties(drive.url) }
        }
    }
}

// MARK: - Gallery

struct GalleryView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var photos: [FSItem] = []
    @State private var loading = true

    var body: some View {
        let p = Win11.palette(theme.scheme)
        Group {
            if loading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.regular)
                    Text("Collecting photos…").font(Win11.Fonts.bodySecondary).foregroundStyle(p.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if photos.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(p.textSecondary.opacity(0.8))
                    Text("No photos found in your Pictures folder.")
                        .font(Win11.Fonts.body)
                        .foregroundStyle(p.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            ThumbnailView(item: photo, size: 148, cornerRadius: 8)
                                .modifier(ItemInteractions(item: photo, index: index, tab: tab, app: app))
                                .modifier(ReportsBandFrame(id: photo.id))
                        }
                    }
                    .padding(12)
                    .modifier(BandSelectable(tab: tab))
                }
            }
        }
        .task {
            let pics = DirectoryLoader.homeURL.appendingPathComponent("Pictures", isDirectory: true)
            photos = await Task.detached(priority: .userInitiated) {
                DirectoryLoader.images(root: pics, cap: 400)
            }.value
            loading = false
        }
    }
}

// MARK: - Trash

struct TrashView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TrashIconView(size: 22)
                Text("Recycle Bin")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(p.textPrimary)
                Spacer()
                Button {
                    if !tab.items.isEmpty { app.activeSheet = .emptyTrash }
                } label: {
                    Text("Empty Recycle Bin")
                }
                .buttonStyle(WinStandardButtonStyle(enabled: !tab.items.isEmpty))
                .disabled(tab.items.isEmpty)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(alignment: .bottom) { Rectangle().fill(p.divider).frame(height: 1) }

            if tab.loading && tab.items.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if tab.sortedItems.isEmpty {
                VStack(spacing: 12) {
                    TrashIconView(size: 54, full: false)
                    Text("The Recycle Bin is empty.")
                        .font(Win11.Fonts.body)
                        .foregroundStyle(p.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DetailsView(tab: tab, app: app)
            }
        }
        .onAppear {
            if tab.items.isEmpty { tab.reload() }
        }
    }
}

// MARK: - Network

struct NetworkView: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @State private var volumes: [DriveInfo] = []
    @State private var loading = true

    var body: some View {
        let p = Win11.palette(theme.scheme)
        Group {
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if volumes.isEmpty {
                VStack(spacing: 12) {
                    NavIcon(symbol: "point.3.connected.trianglepath.dotted", size: 44)
                    Text("No shared network folders are currently connected.")
                        .font(Win11.Fonts.body)
                        .foregroundStyle(p.textSecondary)
                    Text("Connect to a server in the Finder (⌘K) and it will appear here.")
                        .font(.system(size: 12))
                        .foregroundStyle(p.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 226), spacing: 8)], spacing: 8) {
                        ForEach(volumes) { drive in
                            DriveCard(drive: drive, tab: tab, app: app)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .task {
            volumes = await Task.detached(priority: .userInitiated) { DirectoryLoader.volumes().filter { $0.isNetwork } }.value
            loading = false
        }
    }
}
