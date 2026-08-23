import SwiftUI
import UniformTypeIdentifiers

// MARK: - Nav tree model

enum NavChildKind: Equatable {
    case nothing
    case folders(URL)          // lazy subfolders
    case drives                // This PC: user folders + volumes
    case networkVolumes
}

struct NavNode {
    let id: String
    let label: String
    let location: Location
    let children: NavChildKind
}

enum NavItemIcon {
    case folder(URL)
    case symbol(String)
    case pc
    case trash
    case gallery
    case home
    case cloud
    case drive(DriveInfo)
    case network
}

// MARK: - Navigation pane

struct NavigationPane: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rootNodes(), id: \.id) { node in
                    NavNodeRow(node: node, icon: icon(for: node), tab: tab, app: app, level: 0)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .frame(width: app.navWidth)
        .background(p.sidebarTint)
        .overlay(alignment: .trailing) {
            Rectangle().fill(p.divider).frame(width: 1)
        }
    }

    private func icon(for node: NavNode) -> NavItemIcon {
        switch node.id {
        case "home": return .home
        case "gallery": return .gallery
        case "thisPC": return .pc
        case "network": return .network
        case "trash": return .trash
        default:
            if node.id.hasPrefix("cloud:") { return .cloud }
            if node.id.hasPrefix("drive:") || node.id.hasPrefix("netdrive:") {
                return .symbol("externaldrive")
            }
            if case .folder(let url) = node.location { return .folder(url) }
            return .symbol("folder")
        }
    }

    private func rootNodes() -> [NavNode] {
        var nodes: [NavNode] = [
            NavNode(id: "home", label: "Home", location: .home, children: .nothing),
        ]
        if app.prefs.sidebarGallery {
            nodes.append(NavNode(id: "gallery", label: "Gallery", location: .gallery, children: .nothing))
        }

        let home = DirectoryLoader.homeURL
        for special in ["Desktop", "Downloads", "Documents", "Pictures", "Music", "Videos"] {
            let url = home.appendingPathComponent(special, isDirectory: true)
            if !app.isPinned(url.standardizedFileURL.path) {
                nodes.append(NavNode(id: "pin:\(url.path)", label: special, location: .folder(url), children: .folders(url)))
            }
        }
        for pin in app.pins {
            let url = URL(fileURLWithPath: pin, isDirectory: true)
            nodes.append(NavNode(id: "pin:\(pin)", label: url.lastPathComponent, location: .folder(url), children: .folders(url)))
        }

        // Cloud storage
        if app.prefs.sidebarCloud {
            let cloud = DirectoryLoader.cloudStorageFolders()
            let iCloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            var cloudURLs = cloud
            if FileManager.default.fileExists(atPath: iCloud.path) { cloudURLs.append(iCloud) }
            for url in cloudURLs {
                nodes.append(NavNode(id: "cloud:\(url.path)", label: cloudLabel(url), location: .folder(url), children: .folders(url)))
            }
        }

        nodes.append(NavNode(id: "thisPC", label: "This PC", location: .thisPC, children: .drives))
        if app.prefs.sidebarNetwork {
            nodes.append(NavNode(id: "network", label: "Network", location: .network, children: .networkVolumes))
        }
        if app.prefs.sidebarTrash {
            nodes.append(NavNode(id: "trash", label: "Recycle Bin", location: .trash, children: .nothing))
        }
        return nodes
    }

    private func cloudLabel(_ url: URL) -> String {
        let name = url.lastPathComponent
        if name.contains("iCloud") { return "iCloud Drive" }
        if name.contains("OneDrive") { return name.replacingOccurrences(of: "--", with: " ") }
        return name
    }
}

// MARK: - Row

struct NavNodeRow: View {
    let node: NavNode
    let icon: NavItemIcon
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    let level: Int

    @EnvironmentObject var theme: Theme
    @State private var childNodes: [NavNode]? = nil
    @State private var hovering = false
    @State private var dropTargeted = false

    private var expanded: Bool { app.navExpanded.contains(node.id) }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        let selected = tab.location == node.location

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                chevron(p)
                    .opacity(node.children == .nothing ? 0 : 1)

                NavIconView(icon: icon)

                Text(node.label)
                    .font(Win11.Fonts.body)
                    .foregroundStyle(selected ? p.selectionText : p.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(level) * 14 + 4)
            .padding(.trailing, 4)
            .frame(height: 31)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(selected ? p.selectionBG : (hovering || dropTargeted) ? p.hoverRow : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(dropTargeted ? p.selectionBorder : Color.clear, lineWidth: 1.5)
                    .allowsHitTesting(false)
            )
            .contentShape(Rectangle())
            .onTapGesture { tab.navigate(node.location) }
            .onHover { hovering = $0 }
            .modifier(NavFolderDropTarget(node: node, tab: tab, app: app, targeted: $dropTargeted))
            .modifier(NavLinkFrameReporter(node: node))
            .contextMenu {
                if case .folder(let url) = node.location {
                    Button(app.isPinned(url.standardizedFileURL.path) ? "Unpin from Quick access" : "Pin to Quick access") {
                        app.togglePin(url)
                    }
                    Button("Open in new tab") {
                        NotificationCenter.default.post(name: .explorerrOpenInNewTab, object: Location.folder(url))
                    }
                    Button("Copy path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                }
            }

            if expanded, let children = childNodes {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(children, id: \.id) { child in
                        NavNodeRow(node: child, icon: childIcon(child), tab: tab, app: app, level: level + 1)
                    }
                }
            } else if expanded && node.children != .nothing && childNodes == nil {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.small).frame(width: 14)
                    Text("Loading…").font(.system(size: 11)).foregroundStyle(p.textSecondary)
                }
                .padding(.leading, CGFloat(level) * 14 + 22)
                .frame(height: 24)
            }
        }
        .onAppear {
            if expanded && childNodes == nil { loadChildren() }
        }
        .onChange(of: expanded) { newValue in
            if newValue && childNodes == nil { loadChildren() }
        }
    }

    private func childIcon(_ child: NavNode) -> NavItemIcon {
        if child.id.hasPrefix("drive:") || child.id.hasPrefix("netdrive:") { return .symbol("externaldrive") }
        if child.id.hasPrefix("userfolder:") { return .folder(URL(fileURLWithPath: child.id.replacingOccurrences(of: "userfolder:", with: ""))) }
        if case .folder(let url) = child.location { return .folder(url) }
        return .symbol("folder")
    }

    private func chevron(_ p: Win11.Palette) -> some View {
        Button {
            toggleExpanded()
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(p.textSecondary)
                .frame(width: 16, height: 22)
                .contentShape(Rectangle())
                .rotationEffect(.degrees(expanded ? 90 : 0))
        }
        .buttonStyle(.plain)
        .disabled(node.children == .nothing)
    }

    private func toggleExpanded() {
        if app.navExpanded.contains(node.id) {
            app.navExpanded.remove(node.id)
        } else {
            app.navExpanded.insert(node.id)
            if childNodes == nil { loadChildren() }
        }
    }

    private func loadChildren() {
        switch node.children {
        case .nothing:
            return
        case .folders(let url):
            Task {
                let kids = await Task.detached(priority: .userInitiated) {
                    DirectoryLoader.childFolders(of: url, includeHidden: false)
                }.value
                let nodes = kids.prefix(40).map { child in
                    NavNode(id: "sub:\(child.url.path)", label: child.displayName, location: .folder(child.url), children: .folders(child.url))
                }
                childNodes = Array(nodes)
            }
        case .drives:
            Task {
                let drives = await Task.detached(priority: .userInitiated) {
                    DirectoryLoader.volumes()
                }.value
                let home = DirectoryLoader.homeURL
                var nodes: [NavNode] = []
                for special in ["Desktop", "Documents", "downloads", "music", "pictures", "videos"] {
                    let display = special.prefix(1).uppercased() + special.dropFirst()
                    let url = home.appendingPathComponent(display, isDirectory: true)
                    if FileManager.default.fileExists(atPath: url.path) {
                        nodes.append(NavNode(id: "userfolder:\(url.path)", label: display, location: .folder(url), children: .folders(url)))
                    }
                }
                for drive in drives where !drive.isNetwork {
                    let label = drive.isBoot ? "\(drive.name) (System)" : drive.name
                    nodes.append(NavNode(id: "drive:\(drive.url.path)", label: label, location: .folder(drive.url), children: .folders(drive.url)))
                }
                childNodes = nodes
            }
        case .networkVolumes:
            Task {
                let drives = await Task.detached(priority: .userInitiated) {
                    DirectoryLoader.volumes()
                }.value
                let nodes = drives.filter { $0.isNetwork }.map { drive in
                    NavNode(id: "netdrive:\(drive.url.path)", label: drive.name, location: .folder(drive.url), children: .nothing)
                }
                childNodes = nodes.isEmpty ? [] : nodes
            }
        }
    }
}

/// Sidebar folder rows are middle-click targets (open in new background tab).
struct NavLinkFrameReporter: ViewModifier {
    let node: NavNode

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .folder(let url) = node.location {
            content.modifier(ReportsLinkFrame(url: url))
        } else {
            content
        }
    }
}

/// Drop files onto sidebar folders to copy/move them there (Explorer/Dolphin behavior).
struct NavFolderDropTarget: ViewModifier {
    let node: NavNode
    let tab: TabState
    let app: AppModel
    @Binding var targeted: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if case .folder(let dest) = node.location {
            content.onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted) { providers in
                Task {
                    let urls = await FolderContentView.loadURLs(from: providers)
                        .filter { $0.standardizedFileURL.path != dest.standardizedFileURL.path }
                    guard !urls.isEmpty else { return }
                    let internalDrag = urls.contains { app.draggingURLs.contains($0.path) }
                    await FileOps.transfer(urls, to: dest, move: internalDrag, app: app, tab: tab)
                    app.draggingURLs = []
                }
                return true
            }
        } else {
            content
        }
    }
}

// MARK: - Icons

struct NavIconView: View {
    let icon: NavItemIcon

    var body: some View {
        Group {
            switch icon {
            case .folder(let url):
                FolderIconView(variant: FolderVariant.forFolderURL(url), size: 18)
            case .symbol(let name):
                NavIcon(symbol: name)
            case .pc:
                PCIconView(size: 17)
            case .trash:
                TrashIconView(size: 17)
            case .gallery:
                NavIcon(symbol: "photo.on.rectangle.angled")
            case .home:
                NavIcon(symbol: "house.fill")
            case .cloud:
                NavIcon(symbol: "cloud", color: Color(red: 0.1, green: 0.42, blue: 0.78))
            case .drive(let info):
                DriveIconView(drive: info, size: 18)
            case .network:
                NavIcon(symbol: "point.3.connected.trianglepath.dotted", color: Color(red: 0.35, green: 0.45, blue: 0.55))
            }
        }
        .frame(width: 22, alignment: .center)
    }
}
