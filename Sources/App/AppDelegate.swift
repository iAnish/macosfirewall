import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let model: FirewallModel
    private let windows: WindowManager
    private let prompts = PromptCoordinator()
    private let local: LocalBackend?
    private let statusLine = NSMenuItem()
    private let loginItem = NSMenuItem()

    override init() {
        let demo = CommandLine.arguments.contains("--demo")
        let real = demo ? nil : LocalBackend()
        local = real
        let backend: FirewallBackend
        if let real { backend = real } else { backend = DemoBackend() }
        model = FirewallModel(backend: backend)
        windows = WindowManager(model: model)
        super.init()
        backend.promptHandler = { [weak self] request, reply in
            self?.prompts.enqueue(request, reply: reply)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Firewall")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings)))
        menu.addItem(item("History", #selector(openHistory)))
        menu.addItem(item("About", #selector(openAbout)))
        menu.addItem(.separator())
        loginItem.title = "Launch at Login"
        loginItem.action = #selector(toggleLogin)
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(item("Quit", #selector(NSApplication.terminate(_:)), target: NSApp))
        statusItem.menu = menu

        local?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        local?.monitor.resumeAll()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        statusLine.title = model.statusText
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func item(_ title: String, _ action: Selector, target: AnyObject? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = target ?? self
        return i
    }

    @objc private func openSettings() { windows.showSettings() }
    @objc private func openHistory() { windows.showHistory() }
    @objc private func openAbout() { windows.showAbout() }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            NSLog("%@", "Launch at login failed: \(error.localizedDescription)")
        }
    }
}
