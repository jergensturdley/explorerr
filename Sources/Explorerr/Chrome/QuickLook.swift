import Quartz
import AppKit

/// Real macOS Quick Look (QLPreviewPanel) for the selection, Finder-style:
/// Space toggles, Esc closes (handled by the panel itself).
enum QuickLook {
    final class Controller: NSObject, QLPreviewPanelDataSource {
        var urls: [URL] = []
        var currentPanel: QLPreviewPanel?

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { urls.count }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            guard urls.indices.contains(index) else { return nil }
            return urls[index] as NSURL
        }
    }

    static let controller = Controller()

    static func toggle(items: [FSItem]) {
        let urls = items.filter { !$0.isDirectory }.map { $0.url }
        guard !urls.isEmpty else { return }
        guard let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, controller.urls == urls {
            panel.orderOut(nil)
            return
        }
        controller.urls = urls
        panel.dataSource = controller
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    static func dismissIfVisible() {
        if let panel = QLPreviewPanel.shared(), panel.isVisible {
            panel.orderOut(nil)
        }
    }
}
