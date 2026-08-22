import SwiftUI
import AppKit

// MARK: - Conflict dialog (Windows "Replace or Skip Files")

struct ConflictSheet: View {
    let context: ConflictContext
    @ObservedObject var app: AppModel
    @State private var applyAll = false
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(p.caution)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Replace or Skip Files")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                    Text("The destination already has \(context.sourceName == context.destName ? "an item" : "an item") named “\(context.destName)”.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(18)

            if context.remaining > 0 {
                Toggle(isOn: $applyAll) {
                    Text("Do this for all \(context.remaining + 1) conflicts")
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.textSecondary)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
            }

            HStack(spacing: 8) {
                Spacer()
                Button {
                    app.resolveConflict(.skip, applyAll: applyAll)
                } label: { Text("Skip").frame(width: 86) }
                .buttonStyle(WinStandardButtonStyle())

                Button {
                    app.resolveConflict(.keepBoth, applyAll: applyAll)
                } label: { Text("Keep both").frame(width: 86) }
                .buttonStyle(WinStandardButtonStyle())

                Button {
                    app.resolveConflict(.replace, applyAll: applyAll)
                } label: { Text("Replace").frame(width: 86) }
                .buttonStyle(WinStandardButtonStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
        .frame(width: 480)
        .background(p.contentBG)
        .overlay(alignment: .topLeading) {
            Button {
                app.cancelConflict()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(p.textSecondary)
            }
            .buttonStyle(.plain)
            .padding(10)
        }
    }
}

// MARK: - Progress dialog

struct ProgressSheet: View {
    @ObservedObject var progress: TransferProgress
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        let fraction = progress.total > 0 ? Double(progress.done) / Double(progress.total) : 0
        VStack(alignment: .leading, spacing: 14) {
            Text("Moving — \(Int(fraction * 100))% complete")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(p.textPrimary)

            Text(progress.currentName.isEmpty ? "Preparing…" : progress.currentName)
                .font(.system(size: 12.5))
                .foregroundStyle(p.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.controlFillPressed)
                    Capsule().fill(p.accent).frame(width: max(3, geo.size.width * fraction))
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(progress.done) of \(progress.total) items")
                    .font(.system(size: 11.5))
                    .foregroundStyle(p.textSecondary)
                Spacer()
                Button {
                    progress.cancelled = true
                } label: { Text("Cancel") }
                .buttonStyle(WinStandardButtonStyle())
            }
        }
        .padding(20)
        .frame(width: 440)
        .background(p.contentBG)
        .interactiveDismissDisabled()
    }
}

// MARK: - Properties dialog

struct PropertiesSheet: View {
    let url: URL
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    @State private var sizeBytes: Int64 = 0
    @State private var fileCount = 0
    @State private var folderCount = 0
    @State private var modified: Date?
    @State private var created: Date?
    @State private var owner: String = "—"
    @State private var permissions: String = "—"
    @State private var isDirectory = false
    @State private var loaded = false

    var body: some View {
        let p = Win11.palette(theme.scheme)
        let item = FSItem.virtual(url, name: url.lastPathComponent, kind: isDirectory ? "File folder" : "", isDirectory: isDirectory)
        VStack(spacing: 0) {
            // header
            HStack(spacing: 12) {
                Group {
                    if item.category == .image {
                        ThumbnailView(item: item, size: 56, cornerRadius: 6)
                    } else {
                        FileIconView(item: item, size: 54)
                    }
                }
                .frame(width: 58, height: 58)

                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                        .lineLimit(2)
                    Text(url.path)
                        .font(.system(size: 11.5))
                        .foregroundStyle(p.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .overlay(alignment: .bottom) { Rectangle().fill(p.divider).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    row(p, "Type:", isDirectory ? "File folder" : (kindText))
                    row(p, "Location:", (url.path as NSString).deletingLastPathComponent)
                    if isDirectory {
                        row(p, "Contains:", loaded ? Fmt.counts(folders: folderCount, files: fileCount) : "Calculating…")
                        row(p, "Size:", loaded ? sizeBytes.string : "Calculating…")
                    } else {
                        row(p, "Size:", loaded ? sizeBytes.string : "…")
                    }
                    row(p, "Created:", created.map { Fmt.dateTime.string(from: $0) } ?? "—")
                    row(p, "Modified:", modified.map { Fmt.dateTime.string(from: $0) } ?? "—")
                    Divider()
                    Text("Sharing and permissions")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(p.textPrimary)
                    row(p, "Owner:", owner)
                    row(p, "Permissions:", permissions)
                }
                .padding(16)
            }

            HStack {
                Spacer()
                Button { dismiss() } label: { Text("OK").frame(width: 80) }
                    .buttonStyle(WinStandardButtonStyle())
            }
            .padding(14)
            .overlay(alignment: .top) { Rectangle().fill(p.divider).frame(height: 1) }
        }
        .frame(width: 440, height: 520)
        .background(p.contentBG)
        .task { await load() }
    }

    private var kindText: String {
        let kinds = (try? url.resourceValues(forKeys: [.localizedTypeDescriptionKey]))?.localizedTypeDescription
        return kinds ?? "File"
    }

    private func row(_ p: Win11.Palette, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(p.textSecondary)
                .frame(width: 96, alignment: .trailing)
            Text(value)
                .font(.system(size: 12.5))
                .foregroundStyle(p.textPrimary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func load() async {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: url.path, isDirectory: &isDir)
        isDirectory = isDir.boolValue
        guard exists else { loaded = true; return }

        let attrs = try? fm.attributesOfItem(atPath: url.path) as [FileAttributeKey: Any]
        created = attrs?[.creationDate] as? Date
        modified = attrs?[.modificationDate] as? Date
        owner = (attrs?[.ownerAccountName] as? String) ?? "Me"
        if let posix = attrs?[.posixPermissions] as? Int {
            permissions = posixString(posix)
        }
        if isDirectory {
            let stats = await Task.detached(priority: .userInitiated) {
                DirectoryLoader.directoryStats(url)
            }.value
            sizeBytes = stats.bytes
            fileCount = stats.files
            folderCount = stats.folders
        } else {
            sizeBytes = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        }
        loaded = true
    }

    private func posixString(_ value: Int) -> String {
        func seg(_ v: Int) -> String {
            (v & 4 != 0 ? "r" : "-") + (v & 2 != 0 ? "w" : "-") + (v & 1 != 0 ? "x" : "-")
        }
        return seg(value >> 6) + seg(value >> 3) + seg(value)
    }
}

// MARK: - About

struct AboutSheet: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    private var versionString: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 14) {
            FolderIconView(variant: .plain, size: 84)
            Text("Explorerr")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(p.textPrimary)
            Text(versionString)
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)
            Text("A Windows 11-style File Explorer for macOS.\nWin11 looks. Win10 ease.")
                .font(.system(size: 12.5))
                .foregroundStyle(p.textSecondary)
                .multilineTextAlignment(.center)

            Button { dismiss() } label: { Text("OK").frame(width: 80) }
                .buttonStyle(WinStandardButtonStyle())
                .padding(.top, 8)
        }
        .padding(30)
        .frame(width: 380)
        .background(p.contentBG)
    }
}

// MARK: - Keyboard shortcuts reference

struct ShortcutsSheet: View {
    @EnvironmentObject var theme: Theme
    @Environment(\.dismiss) private var dismiss

    private let shortcuts: [(String, String)] = [
        ("New tab", "⌘T"), ("New window", "⌘N"), ("Close tab", "⌘W"),
        ("Reopen closed tab", "⇧⌘T"), ("Next / previous tab", "⌃⇥ / ⌃⇧⇥"),
        ("New folder", "⇧⌘N"), ("Open…", "⌘O"), ("Properties", "⌘I or ⌥↩ or ⌥double-click"),
        ("Copy / Cut / Paste", "⌘C / ⌘X / ⌘V"), ("Copy as path", "⇧⌘C"),
        ("Select all / invert selection", "⌘A / ⇧⌘A"), ("Duplicate", "⌘D"),
        ("Undo / Redo", "⌘Z / ⇧⌘Z"), ("Rename", "F2"),
        ("Move to Recycle Bin", "⌘⌫ or fn⌫"), ("Empty Recycle Bin", "⇧⌘⌫"),
        ("Go up (parent folder)", "Backspace, ⌥↑ or ⌘↑"),
        ("Back / Forward", "⌥←/→, ⌘[ / ⌘], mouse 4/5"),
        ("Middle-click tab", "close tab"),
        ("Middle-click folder", "open in background tab"),
        ("Open selection", "Enter or ⌘↓"),
        ("Type to select", "just start typing"),
        ("First / last item", "Home / End"),
        ("Clear search or selection", "Esc"),
        ("Refresh", "F5 or ⌘R"),
        ("Icons / List / Details / Tiles", "⌘1 / ⌘2 / ⌘3 / ⌘4"),
        ("Show hidden items", "⌘⇧."),
        ("Edit address bar / paste a path", "⌘L / ⇧⌘G"),
        ("Address bar: open path in new tab", "⌥↩ (while editing)"),
        ("Go to Home folder", "⇧⌘H"), ("This PC", "⇧⌘C"),
        ("Navigate items (grid-aware)", "↑ ↓ ← →"),
        ("Extend selection", "⇧ + arrows"), ("Page up / down", "PgUp / PgDn"),
        ("Toggle dual pane", "⌘\\"), ("Add pane / close pane", "View menu"),
        ("Focus next / previous pane", "⌘⇧] / ⌘⇧["),
        ("Copy to other pane (dual)", "F5"), ("Move to other pane (dual)", "F6"),
        ("Quick Look (preview)", "Space or ⌘Y"), ("Details pane", "⌘⇧I"),
        ("Zoom in / out / reset view", "⌘= / ⌘− / ⌘0"), ("Find in this folder", "⌘F"),
        ("Navigate panes together", "⌥⌘S (multi-pane)"), ("Open with / Send to", "right-click"),
        ("Toggle integrated terminal", "F4 or ⌥⌘T"),
        ("Terminal: copy (or ^C) / paste", "⌘C / ⌘V"), ("Terminal: send Esc", "esc"),
    ]

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 0) {
            Text("Keyboard Shortcuts")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.textPrimary)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(Array(shortcuts.enumerated()), id: \.offset) { _, pair in
                        HStack {
                            Text(pair.0).font(.system(size: 12.5)).foregroundStyle(p.textPrimary)
                            Spacer()
                            Text(pair.1).font(.system(size: 12)).foregroundStyle(p.accentText)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 5)
                    }
                }
                .padding(.vertical, 8)
            }

            Button { dismiss() } label: { Text("OK").frame(width: 80) }
                .buttonStyle(WinStandardButtonStyle())
                .padding(14)
        }
        .frame(width: 420, height: 520)
        .background(p.contentBG)
    }
}

// MARK: - Empty trash confirm

struct EmptyTrashSheet: View {
    @ObservedObject var app: AppModel
    @EnvironmentObject var theme: Theme

    var body: some View {
        let p = Win11.palette(theme.scheme)
        VStack(spacing: 16) {
            TrashIconView(size: 52)
            Text("Are you sure you want to permanently delete all of these items?")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(p.textPrimary)
                .multilineTextAlignment(.center)
            Text("You can't undo this action.")
                .font(.system(size: 12))
                .foregroundStyle(p.textSecondary)
            HStack(spacing: 10) {
                Button { app.activeSheet = nil } label: { Text("Cancel").frame(width: 84) }
                    .buttonStyle(WinStandardButtonStyle())
                Button { Task { await FileOps.performEmptyTrash(app: app) } } label: { Text("Yes").frame(width: 84) }
                    .buttonStyle(WinStandardButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(p.contentBG)
    }
}
