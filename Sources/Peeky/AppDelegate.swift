import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [PreviewWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMainMenu()

        let launchRequests = CommandLine.arguments
            .dropFirst()
            .filter { !$0.hasPrefix("-") }
            .compactMap(OpenRequest.commandLineArgument)

        if !launchRequests.isEmpty {
            open(requests: launchRequests)
        }

        if windows.isEmpty {
            showEmptyWindow()
        }

        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        open(requests: filenames.map { OpenRequest(url: URL(fileURLWithPath: $0)) })
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        open(requests: urls.compactMap(OpenRequest.incomingURL))
    }

    @objc private func openDocument(_ sender: Any?) {
        showOpenPanel()
    }

    @objc private func zoomInPreview(_ sender: Any?) {
        currentWindowController()?.zoomInPreview(sender)
    }

    @objc private func zoomOutPreview(_ sender: Any?) {
        currentWindowController()?.zoomOutPreview(sender)
    }

    @objc private func resetPreviewZoom(_ sender: Any?) {
        currentWindowController()?.resetPreviewZoom(sender)
    }

    @objc private func refreshPreview(_ sender: Any?) {
        currentWindowController()?.refreshActiveTab(sender)
    }

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(
            withTitle: "About Peeky",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit Peeky",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)

        let fileMenu = NSMenu(title: "File")
        fileMenuItem.submenu = fileMenu

        let openItem = NSMenuItem(title: "Open...", action: #selector(openDocument(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)

        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu

        let refreshItem = NSMenuItem(title: "Refresh", action: #selector(refreshPreview(_:)), keyEquivalent: "r")
        refreshItem.target = self
        viewMenu.addItem(refreshItem)
        viewMenu.addItem(.separator())

        let zoomInItem = NSMenuItem(title: "Zoom In", action: #selector(zoomInPreview(_:)), keyEquivalent: "+")
        zoomInItem.target = self
        viewMenu.addItem(zoomInItem)

        let zoomOutItem = NSMenuItem(title: "Zoom Out", action: #selector(zoomOutPreview(_:)), keyEquivalent: "-")
        zoomOutItem.target = self
        viewMenu.addItem(zoomOutItem)

        let actualSizeItem = NSMenuItem(title: "Actual Size", action: #selector(resetPreviewZoom(_:)), keyEquivalent: "0")
        actualSizeItem.target = self
        viewMenu.addItem(actualSizeItem)

        NSApp.mainMenu = mainMenu
    }

    private func showOpenPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true

        let response = panel.runModal()
        guard response == .OK else { return }
        open(urls: panel.urls)
    }

    private func showEmptyWindow() {
        let controller = makeWindowController()
        controller.showWindow(nil)
    }

    private func open(urls: [URL]) {
        open(requests: urls.compactMap(OpenRequest.fileURL))
    }

    private func open(requests: [OpenRequest]) {
        let fileRequests = requests.filter { !$0.url.hasDirectoryPath }
        guard !fileRequests.isEmpty else { return }

        let controller = targetWindowController()
        controller.showWindow(nil)
        controller.open(requests: fileRequests)

        NSApp.activate(ignoringOtherApps: true)
    }

    private func targetWindowController() -> PreviewWindowController {
        currentWindowController() ?? makeWindowController()
    }

    private func currentWindowController() -> PreviewWindowController? {
        if let keyWindowController = windows.first(where: { $0.window?.isKeyWindow == true }) {
            return keyWindowController
        }

        if let mainWindowController = windows.first(where: { $0.window?.isMainWindow == true }) {
            return mainWindowController
        }

        if let existingWindowController = windows.first {
            return existingWindowController
        }

        return nil
    }

    private func makeWindowController() -> PreviewWindowController {
        let controller = PreviewWindowController()
        controller.onOpenRequested = { [weak self] in
            self?.showOpenPanel()
        }
        controller.onURLsDropped = { [weak self] urls in
            self?.open(urls: urls)
        }
        controller.onClose = { [weak self, weak controller] in
            guard let controller else { return }
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        return controller
    }
}
