import SwiftUI

/// Windows-style "Folder Options" preferences: General / Appearance / Files.
struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.colorScheme) private var scheme
    @State private var fullDiskAccess = DiskAccess.hasFullDiskAccess

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            appearanceTab.tabItem { Label("Appearance", systemImage: "paintbrush") }
            filesTab.tabItem { Label("Files", systemImage: "doc.on.doc") }
        }
        .frame(width: 520, height: 520)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess = DiskAccess.hasFullDiskAccess
        }
    }

    // Binding into app.prefs without repeating the get/set dance per row.
    private func pref<T>(_ keyPath: WritableKeyPath<Prefs, T>) -> Binding<T> {
        Binding(
            get: { app.prefs[keyPath: keyPath] },
            set: { app.prefs[keyPath: keyPath] = $0 }
        )
    }

    // MARK: General

    private var generalTab: some View {
        Form {
            Picker("Open new windows to", selection: pref(\.startupHome)) {
                Text("Home").tag(true)
                Text("Home folder (~)").tag(false)
            }
            .pickerStyle(.radioGroup)

            Picker("Open new tabs to", selection: pref(\.newTabsOpenHome)) {
                Text("Home").tag(true)
                Text("Home folder (~)").tag(false)
            }
            .pickerStyle(.radioGroup)

            Section("Click behavior") {
                Picker("Open items with", selection: pref(\.singleClickOpen)) {
                    Text("Double-click (select with single click)").tag(false)
                    Text("Single click (select with checkboxes or keyboard)").tag(true)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()

                Toggle("Double-click empty space to go up one folder", isOn: pref(\.doubleClickEmptyGoesUp))
            }

            Section("Terminal") {
                Toggle("Terminal follows navigation (cd when idle)", isOn: pref(\.syncTerminalCD))
            }

            Section("File access") {
                HStack(spacing: 6) {
                    Image(systemName: fullDiskAccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(fullDiskAccess ? Color.green : Color.orange)
                    Text(fullDiskAccess ? "Full Disk Access granted" : "Full Disk Access not granted")
                }
                if !fullDiskAccess {
                    Text("Needed for the Recycle Bin and protected folders (Mail, Safari, Time Machine). macOS only lets you grant it in System Settings: turn on Explorerr under Privacy & Security, Full Disk Access, then relaunch the app.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Full Disk Access Settings…") {
                        DiskAccess.openFullDiskAccessSettings()
                    }
                }
            }
        }
        .padding(18)
    }

    // MARK: Appearance

    private var appearanceTab: some View {
        Form {
            Picker("Theme", selection: pref(\.appearance)) {
                ForEach(AppearanceMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)

            Section("Density") {
                Toggle("Compact rows in Details and List views", isOn: pref(\.compactRows))
            }

            Section("Panels") {
                Toggle("Show status bar", isOn: pref(\.statusVisible))
                Toggle("Show details pane", isOn: pref(\.showDetailsPane))
            }

            Section("Sidebar") {
                Toggle("Gallery", isOn: pref(\.sidebarGallery))
                Toggle("Cloud storage", isOn: pref(\.sidebarCloud))
                Toggle("Network", isOn: pref(\.sidebarNetwork))
                Toggle("Recycle Bin", isOn: pref(\.sidebarTrash))
            }
        }
        .padding(18)
    }

    // MARK: Files

    private var filesTab: some View {
        Form {
            Toggle("Show hidden files, folders, and drives", isOn: Binding(
                get: { app.prefs.showHidden },
                set: {
                    app.prefs.showHidden = $0
                    app.reloadAllTabs()
                }
            ))
            Toggle("Show file name extensions", isOn: pref(\.showExtensions))
            Toggle("Keep folders on top when sorting", isOn: pref(\.foldersFirst))
            Toggle("Ask for confirmation before deleting", isOn: pref(\.confirmDelete))
            Toggle("Search all subfolders by default", isOn: pref(\.searchAllSubfolders))

            Section("Privacy") {
                Toggle("Track and show recent files on Home", isOn: pref(\.showRecents))
                HStack {
                    Spacer()
                    Button("Clear recent files") { app.recents = [] }
                        .disabled(app.recents.isEmpty)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Clear per-folder view memory") { app.folderPrefs = [:] }
                }
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        var fresh = Prefs()
                        fresh.didPrimeFolderAccess = app.prefs.didPrimeFolderAccess
                        app.prefs = fresh
                        app.reloadAllTabs()
                    }
                }
            }
        }
        .padding(18)
    }
}
