import AppKit
import SwiftUI
import AirCCCore

final class QuickPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        minSize = NSSize(width: 520, height: 400)

        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}

@MainActor
final class QuickPastePanelController: NSObject, NSWindowDelegate {
    let panel: QuickPastePanel
    private let viewModel: AppViewModel
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var hasPositionedOnce = false

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        let initialRect = NSRect(x: 0, y: 0, width: 640, height: 500)
        self.panel = QuickPastePanel(contentRect: initialRect)
        super.init()

        panel.delegate = self
        let rootView = QuickPasteView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = hostingView

        viewModel.onRequestClosePanel = { [weak self] in
            self?.hide(restoreFocus: false)
        }

        installKeyMonitor()
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
        }
    }

    var isVisible: Bool {
        panel.isVisible
    }

    func toggle() {
        if panel.isVisible && panel.isKeyWindow {
            hide(restoreFocus: true)
        } else {
            show()
        }
    }

    func show() {
        viewModel.recordFrontmostAppBeforeShowing()
        viewModel.prepareForPanelPresentation()
        positionNearActiveScreenCenterIfNeeded()

        panel.makeKeyAndOrderFront(nil)
        installGlobalClickMonitor()
    }

    func hide(restoreFocus: Bool) {
        removeGlobalClickMonitor()
        panel.orderOut(nil)

        if restoreFocus,
           let prev = viewModel.previousActiveApp,
           !prev.isTerminated {
            prev.activate(options: [.activateAllWindows])
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if !viewModel.isWindowPinned {
            hide(restoreFocus: false)
        }
    }

    private func positionNearActiveScreenCenterIfNeeded() {
        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen = targetScreen else { return }
        let visibleFrame = screen.visibleFrame
        let size = panel.frame.size

        if !hasPositionedOnce || !visibleFrame.intersects(panel.frame) {
            let x = round(visibleFrame.midX - size.width / 2.0)
            let y = round(visibleFrame.midY - size.height / 2.0 + visibleFrame.height * 0.06)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
            hasPositionedOnce = true
        }
    }

    private func installGlobalClickMonitor() {
        removeGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.panel.isVisible, !self.viewModel.isWindowPinned else { return }
                let mouseLoc = NSEvent.mouseLocation
                if !self.panel.frame.contains(mouseLoc) {
                    self.hide(restoreFocus: false)
                }
            }
        }
    }

    private func removeGlobalClickMonitor() {
        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private func installKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isVisible, event.window === self.panel else {
                return event
            }
            if self.handleKeyDown(event) {
                return nil
            }
            return event
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // Respect IME composition (e.g. Pinyin candidate window)
        if let textView = panel.firstResponder as? NSTextView, textView.hasMarkedText() {
            return false
        }

        let settings = viewModel.settings

        // 1. User-customizable panel shortcuts
        if settings.shortcut(for: .panelPastePlain)?.matches(event: event) == true {
            viewModel.pasteSelected(plainTextOnly: true)
            return true
        }
        if settings.shortcut(for: .panelTogglePin)?.matches(event: event) == true {
            viewModel.togglePinSelected()
            return true
        }
        if settings.shortcut(for: .panelDeleteClip)?.matches(event: event) == true {
            viewModel.deleteSelected()
            return true
        }
        if settings.shortcut(for: .panelPinWindow)?.matches(event: event) == true {
            viewModel.isWindowPinned.toggle()
            viewModel.showBanner(viewModel.isWindowPinned ? "已钉住悬浮窗" : "已取消钉住悬浮窗")
            return true
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = event.keyCode

        // 2. Built-in Command shortcuts (⌘1..⌘9 quick paste & ⌘, settings)
        if flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option) {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if let digit = Int(chars), (1...9).contains(digit) {
                    let plain = flags.contains(.shift)
                    viewModel.pasteAtIndex(digit - 1, plainTextOnly: plain)
                    return true
                }
                if chars == "," && !flags.contains(.shift) {
                    viewModel.onRequestOpenSettings?()
                    return true
                }
            }
        }

        // 3. Built-in navigation & primary paste / close
        let hasNoPrimaryMods = !flags.contains(.command) && !flags.contains(.control) && !flags.contains(.option)
        switch keyCode {
        case 125 where hasNoPrimaryMods: // Down arrow
            viewModel.moveSelection(delta: 1)
            return true
        case 126 where hasNoPrimaryMods: // Up arrow
            viewModel.moveSelection(delta: -1)
            return true
        case 36, 76: // Return / Enter (plain bare Return)
            if hasNoPrimaryMods && !flags.contains(.shift) {
                viewModel.pasteSelected(plainTextOnly: false)
                return true
            }
            return false
        case 53 where hasNoPrimaryMods: // Escape
            if !viewModel.handleEscapeKey() {
                hide(restoreFocus: true)
            }
            return true
        default:
            return false
        }
    }
}
