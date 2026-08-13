@preconcurrency import AppKit
@preconcurrency import QuickLookUI

@MainActor
final class ImportQuickLookController: NSObject, ObservableObject, @preconcurrency QLPreviewPanelDataSource {
    private var urls: [URL] = []

    func present(urls: [URL], selectedURL: URL) {
        let availableURLs = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard
            !availableURLs.isEmpty,
            let selectedIndex = availableURLs.firstIndex(of: selectedURL),
            let panel = QLPreviewPanel.shared()
        else {
            return
        }

        self.urls = availableURLs
        panel.dataSource = self
        panel.currentPreviewItemIndex = selectedIndex
        panel.reloadData()
        panel.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        QLPreviewPanel.shared()?.close()
        urls = []
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        urls.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard urls.indices.contains(index) else {
            return nil
        }
        return urls[index] as NSURL
    }
}
