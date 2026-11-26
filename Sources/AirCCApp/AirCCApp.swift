import AppKit
import SwiftUI
import AirCCCore

@main
struct AirCCMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var viewModel: AppViewModel!
    private var panelController: QuickPastePanelController!
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenuForTextEditing()

        let store: DatabaseStore
        do {
            store = try DatabaseStore()
        } catch {
            let alert = NSAlert()
            alert.messageText = "air-cc 数据库初始化失败"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        viewModel = AppViewModel(store: store, settings: .shared)
        panelController = QuickPastePanelController(viewModel: viewModel)

        viewModel.onRequestOpenSettings = { [weak self] in
            self?.openSettingsWindow()
        }

        GlobalHotKeyManager.shared.onActionTriggered = { [weak self] action in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch action {
                case .togglePanel:
                    self.panelController.toggle()
                default:
                    let wasVisible = self.panelController.isVisible
                    self.viewModel.performGlobalQuickPaste(action: action, wasPanelVisible: wasVisible)
                }
            }
        }

        setupStatusItem()
        viewModel.startServices()

        // If launched with --show, open Quick Paste immediately for easy preview/testing
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.panelController.show()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let img = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "air-cc")
            img?.isTemplate = true
            button.image = img
            button.toolTip = "air-cc · 空气剪切板 (\(viewModel.settings.togglePanelBadgeText))\n左键：打开历史面板 · 右键：菜单"
            button.target = self
            button.action = #selector(handleStatusItemClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        self.statusItem = item
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            panelController.toggle()
            return
        }
        let isRightClick = event.type == .rightMouseUp || event.modifierFlags.contains(.control)
        if isRightClick {
            presentStatusMenu()
        } else {
            panelController.toggle()
        }
    }

    private func presentStatusMenu() {
        guard let statusItem else { return }
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "打开剪贴板面板 (\(viewModel.settings.togglePanelBadgeText))",
            action: #selector(menuTogglePanel),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let pauseTitle = viewModel.settings.monitoringPaused ? "恢复监听剪贴板" : "暂停监听剪贴板"
        let pauseItem = NSMenuItem(title: pauseTitle, action: #selector(menuTogglePause), keyEquivalent: "")
        pauseItem.target = self
        if viewModel.settings.monitoringPaused {
            pauseItem.state = .on
        }
        menu.addItem(pauseItem)

        let clearItem = NSMenuItem(title: "清空未置顶历史记录…", action: #selector(menuClearHistory), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "偏好设置…", action: #selector(menuOpenSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 air-cc", action: #selector(menuQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func menuTogglePanel() {
        panelController.show()
    }

    @objc private func menuTogglePause() {
        viewModel.settings.monitoringPaused.toggle()
        updateStatusIconAppearance()
    }

    @objc private func menuClearHistory() {
        viewModel.clearAllUnpinned()
    }

    @objc private func menuOpenSettings() {
        openSettingsWindow()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    func updateStatusIconAppearance() {
        guard let button = statusItem?.button else { return }
        let symbol = viewModel.settings.monitoringPaused ? "pause.rectangle" : "doc.on.clipboard"
        let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "air-cc")
        img?.isTemplate = true
        button.image = img
        button.toolTip = "air-cc · 空气剪切板 (\(viewModel.settings.togglePanelBadgeText))\n左键：打开历史面板 · 右键：菜单"
    }

    func openSettingsWindow() {
        if let window = settingsWindow {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(viewModel: viewModel) { [weak self] in
            self?.updateStatusIconAppearance()
        }
        let hosting = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hosting)
        window.title = "air-cc · 空气剪切板 偏好设置"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 540, height: 490))
        window.center()
        window.isReleasedWhenClosed = false
        self.settingsWindow = window

        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// Standard Edit menu so Cmd+A / Cmd+C / Cmd+V / Cmd+X work inside search TextField in accessory apps.
    private func setupMainMenuForTextEditing() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 air-cc", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
