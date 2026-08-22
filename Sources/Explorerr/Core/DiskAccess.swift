import AppKit

/// macOS file-access plumbing. Full Disk Access has no programmatic prompt: the app can
/// only detect that it is missing and send the user to the System Settings pane. The
/// per-folder prompts (Desktop/Documents/Downloads) CAN be triggered by touching the
/// folders, which we do once on first launch so the app asks up front instead of
/// mid-navigation.
enum DiskAccess {
    /// True when the app can read Full-Disk-Access-gated locations (Recycle Bin,
    /// Mail/Safari data, other users' files). Probes a TCC-protected folder; plain
    /// user-level permissions are not enough to list it.
    static var hasFullDiskAccess: Bool {
        let home = NSHomeDirectory()
        for probe in ["\(home)/Library/Safari", "\(home)/.Trash"] {
            if (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil {
                return true
            }
        }
        return false
    }

    /// Opens System Settings on Privacy & Security > Full Disk Access.
    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Touch the TCC-protected user folders so macOS shows their permission prompts
    /// now rather than on first navigation. Runs off-main: each call blocks while its
    /// dialog is on screen.
    static func primeFolderPermissions() {
        Task.detached(priority: .utility) {
            let home = NSHomeDirectory()
            for folder in ["Desktop", "Documents", "Downloads"] {
                _ = try? FileManager.default.contentsOfDirectory(atPath: "\(home)/\(folder)")
            }
        }
    }
}
