import AppKit

/// Shows the Allow / Block dialog, one at a time.
@MainActor
final class PromptCoordinator {
    private var queue: [(PromptRequest, (Bool) -> Void)] = []
    private var showing = false

    func enqueue(_ request: PromptRequest, reply: @escaping (Bool) -> Void) {
        queue.append((request, reply))
        showNext()
    }

    private func showNext() {
        guard !showing, !queue.isEmpty else { return }
        showing = true
        let (req, reply) = queue.removeFirst()

        let alert = NSAlert()
        alert.messageText = "“\(req.appName)” wants to use the network"
        alert.informativeText = """
            \(req.direction) \(req.kind) connection to \(req.destination)

            Your choice applies to every future connection from this app. \
            You can change it any time in Settings.
            """
        alert.icon = NSWorkspace.shared.icon(forFile: req.appKey)
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Block")
        alert.window.level = .floating

        NSApp.activate(ignoringOtherApps: true)
        let allow = alert.runModal() == .alertFirstButtonReturn
        reply(allow)
        showing = false
        showNext()
    }
}
