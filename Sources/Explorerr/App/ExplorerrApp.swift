import SwiftUI

@main
struct ExplorerrApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var shared = AppModel()

    init() {
        // Headless logic verification for environments without XCTest
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }
    }

    var body: some Scene {
        WindowGroup(for: WindowSeed.self) { seed in
            MainWindow(seed: seed.wrappedValue, shared: shared)
                .environmentObject(shared)
                .environmentObject(shared.menuCoordinator)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1120, height: 700)
        .commands { ExplorerCommands() }

        Settings { SettingsView().environmentObject(shared) }
    }
}

struct WindowSeed: Codable, Hashable { var id: UUID = UUID() }

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
}
