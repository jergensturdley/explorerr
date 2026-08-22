import SwiftUI

/// Windows-style "Folder Options" preferences.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            viewTab.tabItem { Label("View", systemImage: "eye") }
        }
        .frame(width: 480, height: 420)
    }

    private var generalTab: some View {
        Form {
            Picker("Open new windows to", selection: Binding(
                get: { app.prefs.startupHome },
                set: { app.prefs.startupHome = $0 }
            )) {
                Text("Home").tag(true)
                Text("Home folder (~)").tag(false)
            }
            .pickerStyle(.radioGroup)

            Toggle("Ask for confirmation before deleting", isOn: Binding(
                get: { app.prefs.confirmDelete },
                set: { app.prefs.confirmDelete = $0 }
            ))

            Toggle("Search all subfolders by default", isOn: Binding(
                get: { app.prefs.searchAllSubfolders },
                set: { app.prefs.searchAllSubfolders = $0 }
            ))
        }
        .padding(18)
    }

    private var viewTab: some View {
        Form {
            Toggle("Show hidden files, folders, and drives", isOn: Binding(
                get: { app.prefs.showHidden },
                set: {
                    app.prefs.showHidden = $0
                    app.reloadAllTabs()
                }
            ))
            Toggle("Show file name extensions", isOn: Binding(
                get: { app.prefs.showExtensions },
                set: { app.prefs.showExtensions = $0 }
            ))
            Toggle("Keep folders on top when sorting", isOn: Binding(
                get: { app.prefs.foldersFirst },
                set: { app.prefs.foldersFirst = $0 }
            ))
            Toggle("Show status bar", isOn: Binding(
                get: { app.prefs.statusVisible },
                set: { app.prefs.statusVisible = $0 }
            ))

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        app.prefs = Prefs()
                        app.reloadAllTabs()
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear per-folder view memory") {
                        app.folderPrefs = [:]
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear recent files") {
                        app.recents = []
                    }
                    .disabled(app.recents.isEmpty)
                }
            }
        }
        .padding(18)
    }
}
