import AppKit
import SwiftUI

@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    private let model: FirewallModel
    private var windows: [String: NSWindow] = [:]

    init(model: FirewallModel) { self.model = model }

    func showSettings() { show("settings", title: "Settings", style: [.titled, .closable, .resizable]) { SettingsView(model: model) } }
    func showHistory() { show("history", title: "Connection History", style: [.titled, .closable, .resizable, .miniaturizable]) { HistoryView(model: model) } }
    func showAbout() { show("about", title: "About", style: [.titled, .closable]) { AboutView() } }

    private func show<V: View>(_ id: String, title: String, style: NSWindow.StyleMask, @ViewBuilder content: () -> V) {
        if windows[id] == nil {
            let w = NSWindow(contentViewController: NSHostingController(rootView: content()))
            w.title = title
            w.styleMask = style
            w.isReleasedWhenClosed = false
            w.delegate = self
            w.identifier = NSUserInterfaceItemIdentifier(id)
            w.center()
            windows[id] = w
        }
        model.windowOpened(id)
        NSApp.activate(ignoringOtherApps: true)
        windows[id]?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let id = (notification.object as? NSWindow)?.identifier?.rawValue { model.windowClosed(id) }
    }
}
