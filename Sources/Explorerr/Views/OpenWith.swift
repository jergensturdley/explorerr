import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// "Open With" support: default app, alternates, and a picker — Windows context-menu style.
@MainActor
enum OpenWith {
    struct Candidate: Identifiable {
        let url: URL
        let name: String
        let isDefault: Bool
        var id: String { url.path }
    }

    static func appName(for appURL: URL) -> String {
        Bundle(url: appURL)?.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String
            ?? appURL.deletingPathExtension().lastPathComponent
    }

    static func candidates(for fileURL: URL, limit: Int = 8) -> (defaultApp: Candidate?, others: [Candidate]) {
        let workspace = NSWorkspace.shared
        let defaultURL = workspace.urlForApplication(toOpen: fileURL)
        let all = workspace.urlsForApplications(toOpen: fileURL)
        var others: [Candidate] = []
        for url in all where url != defaultURL {
            others.append(Candidate(url: url, name: appName(for: url), isDefault: false))
            if others.count >= limit { break }
        }
        let def = defaultURL.map { Candidate(url: $0, name: appName(for: $0), isDefault: true) }
        return (def, others)
    }

    static func open(_ fileURL: URL, with appURL: URL, app: AppModel) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([fileURL], withApplicationAt: appURL, configuration: config)
        app.recordRecent(fileURL)
    }

    static func showPicker(for fileURL: URL, app: AppModel) {
        let panel = NSOpenPanel()
        panel.title = "Choose an application"
        panel.message = "Open “\(fileURL.lastPathComponent)” with:"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.application]
        panel.directoryURL = URL(fileURLWithPath: "/System/Applications")
        if panel.runModal() == .OK, let chosen = panel.url {
            open(fileURL, with: chosen, app: app)
        }
    }
}
