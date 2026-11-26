import AppKit
import Combine
import Foundation
import AirCCCore

@MainActor
final class AppViewModel: ObservableObject {
    let store: DatabaseStore
    let settings: AppSettings
    let monitor: ClipboardMonitor

    @Published var clips: [ClipItem] = []
    @Published var searchQuery: String = "" {
        didSet {
            if searchQuery != oldValue {
                reloadClips(resetSelectionToTop: true)
            }
        }
    }
    @Published var selectedCategory: ClipFilterCategory = .all {
        didSet {
            if selectedCategory != oldValue {
                reloadClips(resetSelectionToTop: true)
            }
        }
    }
    @Published var selectedClipID: Int64?
    @Published var isWindowPinned: Bool = false
    @Published var statusBannerMessage: String?
    @Published var isAccessibilityGranted: Bool = PasteService.isAccessibilityTrusted()
    @Published var totalCount: Int = 0
    @Published var pinnedCount: Int = 0
    @Published var searchFocusTrigger: Int = 0

    weak var previousActiveApp: NSRunningApplication?
    var onRequestClosePanel: (() -> Void)?
    var onRequestOpenSettings: (() -> Void)?

    private var bannerClearWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    init(store: DatabaseStore, settings: AppSettings = .shared) {
        self.store = store
        self.settings = settings
        self.monitor = ClipboardMonitor(store: store, settings: settings)

        self.monitor.onClipCaptured = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadClips(resetSelectionToTop: false)
            }
        }

        settings.$maxHistoryCount
            .dropFirst()
            .sink { [weak self] newMax in
                guard let self else { return }
                self.store.pruneIfNeeded(maxHistory: newMax)
                self.reloadClips(resetSelectionToTop: false)
            }
            .store(in: &cancellables)

        settings.$shortcuts
            .dropFirst()
            .sink { updatedShortcuts in
                GlobalHotKeyManager.shared.syncShortcuts(updatedShortcuts)
            }
            .store(in: &cancellables)

        reloadClips(resetSelectionToTop: true)
    }

    func startServices() {
        monitor.start()
        GlobalHotKeyManager.shared.syncShortcuts(settings.shortcuts)
    }

    func refreshAccessibilityStatus() {
        isAccessibilityGranted = PasteService.isAccessibilityTrusted()
    }

    func recordFrontmostAppBeforeShowing() {
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousActiveApp = front
        }
    }

    func prepareForPanelPresentation() {
        refreshAccessibilityStatus()
        reloadClips(resetSelectionToTop: true)
        searchFocusTrigger &+= 1
    }

    func reloadClips(resetSelectionToTop: Bool) {
        let fetched = store.fetchClips(query: searchQuery, category: selectedCategory, limit: 300)
        clips = fetched
        let stats = store.counts()
        totalCount = stats.total
        pinnedCount = stats.pinned

        if resetSelectionToTop {
            selectedClipID = fetched.first?.id
        } else if let current = selectedClipID, fetched.contains(where: { $0.id == current }) {
            // Keep current selection
        } else {
            selectedClipID = fetched.first?.id
        }
    }

    var selectedClip: ClipItem? {
        guard let selectedClipID else { return clips.first }
        return clips.first(where: { $0.id == selectedClipID }) ?? clips.first
    }

    func moveSelection(delta: Int) {
        guard !clips.isEmpty else { return }
        guard let currentID = selectedClipID,
              let currentIndex = clips.firstIndex(where: { $0.id == currentID }) else {
            selectedClipID = clips.first?.id
            return
        }
        let nextIndex = max(0, min(clips.count - 1, currentIndex + delta))
        selectedClipID = clips[nextIndex].id
    }

    func pasteSelected(plainTextOnly: Bool, copyOnly: Bool = false) {
        guard let item = selectedClip else { return }
        paste(item: item, plainTextOnly: plainTextOnly, copyOnly: copyOnly)
    }

    func pasteAtIndex(_ index: Int, plainTextOnly: Bool = false) {
        guard index >= 0 && index < clips.count else { return }
        let item = clips[index]
        selectedClipID = item.id
        paste(item: item, plainTextOnly: plainTextOnly, copyOnly: false)
    }

    func paste(item: ClipItem, plainTextOnly: Bool, copyOnly: Bool = false) {
        let shouldClose = !isWindowPinned && !copyOnly
        let targetApp = previousActiveApp

        if shouldClose {
            onRequestClosePanel?()
        }

        PasteService.performPaste(
            item: item,
            store: store,
            targetApp: shouldClose ? targetApp : nil,
            plainTextOnly: plainTextOnly,
            copyOnly: copyOnly,
            moveToTop: settings.moveClipToTopOnPaste
        ) { [weak self] outcome in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.reloadClips(resetSelectionToTop: false)
                switch outcome {
                case .pastedDirectly:
                    if self.isWindowPinned {
                        self.showBanner(plainTextOnly ? "已纯文本写入剪贴板" : "已写入剪贴板")
                    }
                case .copiedOnly:
                    self.showBanner(plainTextOnly ? "已复制为纯文本 (⌘V 可粘贴)" : "已复制到剪贴板")
                case .copiedNeedsAccessibilityPermission:
                    self.isAccessibilityGranted = false
                    self.showBanner("已写入剪贴板，请按 ⌘V 粘贴（授权辅助功能后支持双击自动上屏）")
                }
            }
        }
    }

    func togglePin(for item: ClipItem) {
        _ = store.togglePin(id: item.id)
        reloadClips(resetSelectionToTop: false)
    }

    func togglePinSelected() {
        guard let item = selectedClip else { return }
        if let newState = store.togglePin(id: item.id) {
            reloadClips(resetSelectionToTop: false)
            showBanner(newState ? "已置顶收藏" : "已取消置顶")
        }
    }

    func delete(item: ClipItem) {
        let currentIndex = clips.firstIndex(where: { $0.id == item.id })
        store.deleteClip(id: item.id)
        let refreshed = store.fetchClips(query: searchQuery, category: selectedCategory, limit: 300)
        clips = refreshed
        let stats = store.counts()
        totalCount = stats.total
        pinnedCount = stats.pinned

        if let idx = currentIndex, !refreshed.isEmpty {
            let clamped = min(idx, refreshed.count - 1)
            selectedClipID = refreshed[clamped].id
        } else {
            selectedClipID = refreshed.first?.id
        }
    }

    func deleteSelected() {
        guard let item = selectedClip else { return }
        delete(item: item)
        showBanner("已删除记录")
    }

    func clearAllUnpinned() {
        store.clearUnpinned()
        reloadClips(resetSelectionToTop: true)
        showBanner("已清空未置顶历史记录")
    }

    /// Returns true if consumed (cleared search/filter), false if panel should close.
    func handleEscapeKey() -> Bool {
        if !searchQuery.isEmpty {
            searchQuery = ""
            return true
        }
        if selectedCategory != .all {
            selectedCategory = .all
            return true
        }
        return false
    }

    func loadPreviewImage(for item: ClipItem) -> NSImage? {
        if let data = store.loadBlobData(for: item) {
            return NSImage(data: data)
        }
        return nil
    }

    func performGlobalQuickPaste(action: ShortcutActionID, wasPanelVisible: Bool) {
        let allItems = store.fetchClips(query: "", category: .all, limit: 100)
        guard !allItems.isEmpty else { return }

        let targetItem: ClipItem?
        let plainTextOnly: Bool

        switch action {
        case .pasteLatestPlain:
            // Pick the most recently copied/updated item regardless of pin ordering
            targetItem = allItems.max(by: { $0.updatedAt < $1.updatedAt })
            plainTextOnly = true
        case .quickPasteSlot1:
            targetItem = allItems.indices.contains(0) ? allItems[0] : nil
            plainTextOnly = false
        case .quickPasteSlot2:
            targetItem = allItems.indices.contains(1) ? allItems[1] : nil
            plainTextOnly = false
        case .quickPasteSlot3:
            targetItem = allItems.indices.contains(2) ? allItems[2] : nil
            plainTextOnly = false
        default:
            targetItem = nil
            plainTextOnly = false
        }

        guard let item = targetItem else { return }

        let destApp: NSRunningApplication?
        if wasPanelVisible {
            if !isWindowPinned {
                onRequestClosePanel?()
            }
            destApp = previousActiveApp
        } else {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                destApp = front
            } else {
                destApp = previousActiveApp
            }
        }

        PasteService.performPaste(
            item: item,
            store: store,
            targetApp: destApp,
            plainTextOnly: plainTextOnly,
            copyOnly: false,
            moveToTop: settings.moveClipToTopOnPaste
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadClips(resetSelectionToTop: false)
            }
        }
    }

    func showBanner(_ text: String, duration: TimeInterval = 2.4) {
        bannerClearWorkItem?.cancel()
        statusBannerMessage = text
        let work = DispatchWorkItem { [weak self] in
            self?.statusBannerMessage = nil
        }
        bannerClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }
}
