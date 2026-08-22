import SwiftUI

/// Windows-10-style status bar: item counts + selection + quick view toggles.
struct StatusBar: View {
    @ObservedObject var tab: TabState
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        HStack(spacing: 12) {
            Text(tab.statusSummary)
                .font(Win11.Fonts.status)
                .foregroundStyle(p.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)

            if let toast = app.statusMessage {
                Text(toast)
                    .font(Win11.Fonts.status)
                    .foregroundStyle(p.accentText)
                    .lineLimit(1)
                    .transition(.opacity)
            }

            Spacer(minLength: 8)

            viewToggle("square.grid.2x2", mode: .iconsMedium, help: "Icons view")
            viewToggle("list.bullet", mode: .list, help: "List view")
            viewToggle("text.justify", mode: .details, help: "Details view")
        }
        .padding(.horizontal, 12)
        .frame(height: Win11.Metrics.statusBarHeight)
        .overlay(alignment: .top) {
            Rectangle().fill(p.divider).frame(height: 1)
        }
    }

    private func viewToggle(_ symbol: String, mode: ViewMode, help: String) -> some View {
        Button {
            tab.setViewMode(mode)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
        }
        .buttonStyle(WinIconButtonStyle(padding: 4))
        .foregroundStyle(tab.viewMode == mode ? Win11.palette(theme.scheme).accentText : Win11.palette(theme.scheme).textSecondary)
        .help(help)
    }
}
