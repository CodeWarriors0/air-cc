import Combine
import Foundation
import Carbon

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text = "text"
    case richText = "rich_text"
    case image = "image"
    case files = "files"

    public var label: String {
        switch self {
        case .text: return "文本"
        case .richText: return "富文本"
        case .image: return "图片"
        case .files: return "文件"
        }
    }

    public var systemSymbolName: String {
        switch self {
        case .text: return "doc.plaintext"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .files: return "folder"
        }
    }
}

public enum ClipFilterCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "all"
    case pinned = "pinned"
    case text = "text"
    case image = "image"
    case files = "files"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: return "全部"
        case .pinned: return "置顶"
        case .text: return "文本"
        case .image: return "图片"
        case .files: return "文件"
        }
    }

    public var symbolName: String {
        switch self {
        case .all: return "tray.full"
        case .pinned: return "pin.fill"
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.on.doc"
        }
    }
}

public struct CapturedClipPayload: Sendable {
    public let contentHash: String
    public let kind: ClipKind
    public let title: String
    public let plainText: String
    public let rtfData: Data?
    public let htmlData: Data?
    public let imagePNGData: Data?
    public let thumbnailPNGData: Data?
    public let filePaths: [String]
    public let imageWidth: Int
    public let imageHeight: Int
    public let byteSize: Int
    public let sourceAppName: String?
    public let sourceBundleID: String?

    public init(
        contentHash: String,
        kind: ClipKind,
        title: String,
        plainText: String,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        imagePNGData: Data? = nil,
        thumbnailPNGData: Data? = nil,
        filePaths: [String] = [],
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        byteSize: Int = 0,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil
    ) {
        self.contentHash = contentHash
        self.kind = kind
        self.title = title
        self.plainText = plainText
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.imagePNGData = imagePNGData
        self.thumbnailPNGData = thumbnailPNGData
        self.filePaths = filePaths
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
    }
}

public struct ClipItem: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let contentHash: String
    public let kind: ClipKind
    public let title: String
    public let plainText: String
    public let rtfData: Data?
    public let htmlData: Data?
    public let thumbnailData: Data?
    public let blobFilename: String?
    public let filePaths: [String]
    public let imageWidth: Int
    public let imageHeight: Int
    public let byteSize: Int
    public let sourceAppName: String?
    public let sourceBundleID: String?
    public var isPinned: Bool
    public var pasteCount: Int
    public let createdAt: Date
    public var updatedAt: Date
    public var lastPastedAt: Date?

    public init(
        id: Int64,
        contentHash: String,
        kind: ClipKind,
        title: String,
        plainText: String,
        rtfData: Data? = nil,
        htmlData: Data? = nil,
        thumbnailData: Data? = nil,
        blobFilename: String? = nil,
        filePaths: [String] = [],
        imageWidth: Int = 0,
        imageHeight: Int = 0,
        byteSize: Int = 0,
        sourceAppName: String? = nil,
        sourceBundleID: String? = nil,
        isPinned: Bool = false,
        pasteCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastPastedAt: Date? = nil
    ) {
        self.id = id
        self.contentHash = contentHash
        self.kind = kind
        self.title = title
        self.plainText = plainText
        self.rtfData = rtfData
        self.htmlData = htmlData
        self.thumbnailData = thumbnailData
        self.blobFilename = blobFilename
        self.filePaths = filePaths
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.byteSize = byteSize
        self.sourceAppName = sourceAppName
        self.sourceBundleID = sourceBundleID
        self.isPinned = isPinned
        self.pasteCount = pasteCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastPastedAt = lastPastedAt
    }

    public var metadataSubtitle: String {
        var parts: [String] = []
        switch kind {
        case .text:
            parts.append("\(plainText.count) 字符")
        case .richText:
            parts.append("富文本 · \(plainText.count) 字符")
        case .image:
            if imageWidth > 0 && imageHeight > 0 {
                parts.append("\(imageWidth)×\(imageHeight)")
            }
            parts.append(Self.formatBytes(byteSize))
        case .files:
            parts.append("\(filePaths.count) 个文件")
        }
        if let app = sourceAppName, !app.isEmpty {
            parts.append(app)
        }
        return parts.joined(separator: " · ")
    }

    public static func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

public enum HotKeyPreset: String, CaseIterable, Identifiable, Codable, Sendable {
    case ctrlGrave = "ctrl_grave"
    case cmdShiftV = "cmd_shift_v"
    case ctrlOptV = "ctrl_opt_v"
    case optSpace = "opt_v"

    public var id: String { rawValue }

    public var displayText: String {
        switch self {
        case .ctrlGrave: return "⌃` (Control + ~ · Ditto 经典)"
        case .cmdShiftV: return "⇧⌘V (Shift + Command + V)"
        case .ctrlOptV: return "⌃⌥V (Control + Option + V)"
        case .optSpace: return "⌥V (Option + V)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .ctrlGrave: return "⌃`"
        case .cmdShiftV: return "⇧⌘V"
        case .ctrlOptV: return "⌃⌥V"
        case .optSpace: return "⌥V"
        }
    }

    public var toKeyShortcut: KeyShortcut {
        switch self {
        case .ctrlGrave: return KeyShortcut(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.control])
        case .cmdShiftV: return KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift])
        case .ctrlOptV:  return KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .option])
        case .optSpace:  return KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.option])
        }
    }
}

private struct StoredShortcutEntry: Codable {
    let shortcut: KeyShortcut?
}

public final class AppSettings: ObservableObject {
    public static let shared = AppSettings()

    private let defaults: UserDefaults

    private enum Keys {
        static let hotKeyPreset = "aircc.hotKeyPreset"
        static let customShortcuts = "aircc.customShortcuts.v1"
        static let maxHistoryCount = "aircc.maxHistoryCount"
        static let moveClipToTopOnPaste = "aircc.moveClipToTopOnPaste"
        static let monitoringPaused = "aircc.monitoringPaused"
    }

    @Published public private(set) var shortcuts: [ShortcutActionID: KeyShortcut]

    @Published public var maxHistoryCount: Int {
        didSet {
            defaults.set(maxHistoryCount, forKey: Keys.maxHistoryCount)
        }
    }

    @Published public var moveClipToTopOnPaste: Bool {
        didSet {
            defaults.set(moveClipToTopOnPaste, forKey: Keys.moveClipToTopOnPaste)
        }
    }

    @Published public var monitoringPaused: Bool {
        didSet {
            defaults.set(monitoringPaused, forKey: Keys.monitoringPaused)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        var loadedShortcuts: [ShortcutActionID: KeyShortcut] = [:]
        for action in ShortcutActionID.allCases {
            if let def = action.defaultShortcut {
                loadedShortcuts[action] = def
            }
        }

        if let data = defaults.data(forKey: Keys.customShortcuts),
           let decoded = try? JSONDecoder().decode([String: StoredShortcutEntry].self, from: data) {
            for (rawKey, entry) in decoded {
                if let action = ShortcutActionID(rawValue: rawKey) {
                    if let sc = entry.shortcut {
                        loadedShortcuts[action] = sc
                    } else {
                        loadedShortcuts.removeValue(forKey: action)
                    }
                }
            }
        } else if let legacyRaw = defaults.string(forKey: Keys.hotKeyPreset),
                  let legacyPreset = HotKeyPreset(rawValue: legacyRaw) {
            loadedShortcuts[.togglePanel] = legacyPreset.toKeyShortcut
        }
        self.shortcuts = loadedShortcuts

        let storedMax = defaults.integer(forKey: Keys.maxHistoryCount)
        self.maxHistoryCount = storedMax > 0 ? storedMax : 500

        if defaults.object(forKey: Keys.moveClipToTopOnPaste) == nil {
            self.moveClipToTopOnPaste = true
        } else {
            self.moveClipToTopOnPaste = defaults.bool(forKey: Keys.moveClipToTopOnPaste)
        }

        self.monitoringPaused = defaults.bool(forKey: Keys.monitoringPaused)
    }

    public func shortcut(for action: ShortcutActionID) -> KeyShortcut? {
        shortcuts[action]
    }

    public func badgeText(for action: ShortcutActionID, fallback: String = "未设置") -> String {
        shortcuts[action]?.displayString ?? fallback
    }

    public var togglePanelBadgeText: String {
        badgeText(for: .togglePanel, fallback: "未绑定")
    }

    @discardableResult
    public func setShortcut(_ newShortcut: KeyShortcut?, for action: ShortcutActionID) -> Result<Void, ShortcutValidationError> {
        if let newShortcut {
            if case .failure(let err) = newShortcut.validateFormat(isGlobal: action.isGlobal) {
                return .failure(err)
            }
            for (otherAction, existingShortcut) in shortcuts where otherAction != action {
                if existingShortcut == newShortcut {
                    return .failure(.conflictsWithAppAction(otherAction.title))
                }
            }
            shortcuts[action] = newShortcut
        } else {
            shortcuts.removeValue(forKey: action)
        }
        persistShortcuts()
        return .success(())
    }

    public func resetShortcutToDefault(for action: ShortcutActionID) {
        if let def = action.defaultShortcut {
            // Remove any conflicting custom assignment before restoring default
            for (other, existing) in shortcuts where other != action && existing == def {
                shortcuts.removeValue(forKey: other)
            }
            shortcuts[action] = def
        } else {
            shortcuts.removeValue(forKey: action)
        }
        persistShortcuts()
    }

    public func resetAllShortcutsToDefault() {
        var defaultsMap: [ShortcutActionID: KeyShortcut] = [:]
        for action in ShortcutActionID.allCases {
            if let def = action.defaultShortcut {
                defaultsMap[action] = def
            }
        }
        shortcuts = defaultsMap
        persistShortcuts()
    }

    private func persistShortcuts() {
        var payload: [String: StoredShortcutEntry] = [:]
        for action in ShortcutActionID.allCases {
            payload[action.rawValue] = StoredShortcutEntry(shortcut: shortcuts[action])
        }
        if let data = try? JSONEncoder().encode(payload) {
            defaults.set(data, forKey: Keys.customShortcuts)
        }
    }
}
