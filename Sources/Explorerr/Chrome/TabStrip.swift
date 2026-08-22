import SwiftUI

/// One pane's tab strip (sits in the window titlebar area, OneCommander-style).
struct PaneTabStrip: View {
    @ObservedObject var controller: TabController
    var isPaneActive: Bool
    var isLastPane: Bool

    @EnvironmentObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(controller.tabs) { tab in
                        TabItemView(tab: tab, isActive: tab.id == controller.activeID) {
                            controller.activate(tab.id)
                        } onClose: {
                            controller.closeTab(tab.id)
                        } onDuplicate: {
                            controller.duplicateTab(tab.id)
                        } onCloseOthers: {
                            controller.closeOthers(tab.id)
                        } onCloseRight: {
                            controller.closeRight(of: tab.id)
                        } onNewTab: {
                            controller.addTab(.home)
                        }
                    }
                }
                .padding(.leading, 8)
            }

            Button {
                controller.addTab(.home)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(WinIconButtonStyle())
            .help("New tab (⌘T)")

            if isLastPane {
                Button {
                    NotificationCenter.default.post(name: .explorerrToggleDualPane, object: nil)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(WinIconButtonStyle())
                .help("Toggle dual pane (⌘\\)")
            }

            Spacer(minLength: isLastPane ? 12 : 6)
        }
        .frame(height: Win11.Metrics.tabStripHeight)
        .opacity(isPaneActive ? 1 : 0.72)
        .background(
            WindowDragArea()
                .onTapGesture(count: 2) {
                    NotificationCenter.default.post(name: .explorerrZoomWindow, object: nil)
                }
        )
    }
}

// Tab shape with only the top corners rounded
struct TopRoundedShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + r), control: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct TabItemView: View {
    @ObservedObject var tab: TabState
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onDuplicate: () -> Void
    let onCloseOthers: () -> Void
    let onCloseRight: () -> Void
    let onNewTab: () -> Void

    @EnvironmentObject var theme: Theme
    @State private var hovering = false
    @State private var closeHover = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 6) {
            tabIcon
                .frame(width: 15)

            Text(tab.title)
                .font(Win11.Fonts.tab)
                .foregroundStyle(p.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(closeHover ? .white : p.textSecondary)
                    .frame(width: 17, height: 17)
                    .background(
                        Circle().fill(closeHover ? p.danger : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(isActive || hovering ? 1 : 0)
            .help("Close tab (⌘W)")
            .onHover { closeHover = $0 }
        }
        .padding(.leading, 10)
        .padding(.trailing, 7)
        .frame(width: min(max(150.0, Double(tab.title.count) * 8 + 80), 230.0), height: Win11.Metrics.tabStripHeight - 6, alignment: .leading)
        .background(
            ZStack {
                if isActive {
                    TopRoundedShape(radius: 8)
                        .fill(p.tabActiveBG)
                        .overlay(
                            TopRoundedShape(radius: 8)
                                .stroke(p.tabStroke, lineWidth: 1)
                        )
                } else if hovering {
                    TopRoundedShape(radius: 8)
                        .fill(p.tabHoverBG)
                }
            }
            .padding(.horizontal, 1)
        )
        .padding(.top, 5)
        .contentShape(Rectangle())
        .onTapGesture { onActivate() }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("New tab") { onNewTab() }
            Button("Duplicate tab") { onDuplicate() }
            Divider()
            Button("Close tab") { onClose() }
            Button("Close other tabs") { onCloseOthers() }
            Button("Close tabs to the right") { onCloseRight() }
        }
    }

    @ViewBuilder
    private var tabIcon: some View {
        switch tab.location {
        case .folder(let url): FolderIconView(variant: FolderVariant.forFolderURL(url), size: 14)
        case .home: NavIcon(symbol: "house.fill", size: 14)
        case .gallery: NavIcon(symbol: "photo.on.rectangle.angled", size: 14)
        case .thisPC: PCIconView(size: 14)
        case .network: NavIcon(symbol: "point.3.connected.trianglepath.dotted", size: 14)
        case .trash: TrashIconView(size: 14)
        }
    }
}

extension Notification.Name {
    static let explorerrToggleDualPane = Notification.Name("explorerr.toggleDualPane")
    static let explorerrZoomWindow = Notification.Name("explorerr.zoomWindow")
}
