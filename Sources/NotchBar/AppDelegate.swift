import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let music = MusicManager()
    private let clipboard = ClipboardManager()
    private var notch: NotchController?
    private var statusItem: NSStatusItem?

    func applicationWillTerminate(_ notification: Notification) {
        clipboard.clear()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        notch = NotchController(music: music, clipboard: clipboard)
        music.start()
        clipboard.start()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func screensChanged() {
        notch?.relayout()
    }


    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled",
                                     accessibilityDescription: "NotchBar")
            ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: "NotchBar")

        let menu = NSMenu()
        let login = NSMenuItem(title: "Abrir al iniciar sesión", action: #selector(toggleLogin(_:)), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de NotchBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("NotchBar: no se pudo cambiar inicio de sesión: \(error)")
        }
        sender.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}
