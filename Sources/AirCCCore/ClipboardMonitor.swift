import AppKit
import Foundation

public final class ClipboardMonitor {
    private let pasteboard: NSPasteboard
    private let store: DatabaseStore
    private let settings: AppSettings
    private var timer: Timer?
    private var lastChangeCount: Int

    public var onClipCaptured: ((ClipItem) -> Void)?

    public init(
        pasteboard: NSPasteboard = .general,
        store: DatabaseStore,
        settings: AppSettings = .shared
    ) {
        self.pasteboard = pasteboard
        self.store = store
        self.settings = settings
        self.lastChangeCount = pasteboard.changeCount
    }

    public func start(interval: TimeInterval = 0.30) {
        stop()
        lastChangeCount = pasteboard.changeCount
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.pollOnce()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func pollOnce() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current

        guard !settings.monitoringPaused else { return }

        let frontApp = NSWorkspace.shared.frontmostApplication
        guard let payload = ClipboardCapture.capture(from: pasteboard, sourceApp: frontApp) else {
            return
        }

        if let saved = store.upsertClip(payload, maxHistory: settings.maxHistoryCount) {
            onClipCaptured?(saved)
        }
    }
}
