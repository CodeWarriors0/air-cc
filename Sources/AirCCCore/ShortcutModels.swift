import AppKit
import Carbon
import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = ShortcutModifiers(rawValue: 1 << 0)
    public static let option  = ShortcutModifiers(rawValue: 1 << 1)
    public static let shift   = ShortcutModifiers(rawValue: 1 << 2)
    public static let command = ShortcutModifiers(rawValue: 1 << 3)

    public init(nsFlags: NSEvent.ModifierFlags) {
        let masked = nsFlags.intersection(.deviceIndependentFlagsMask)
        var result: ShortcutModifiers = []
        if masked.contains(.control) { result.insert(.control) }
        if masked.contains(.option)  { result.insert(.option) }
        if masked.contains(.shift)   { result.insert(.shift) }
        if masked.contains(.command) { result.insert(.command) }
        self = result
    }

    public var carbonFlags: UInt32 {
        var flags: UInt32 = 0
        if contains(.control) { flags |= UInt32(controlKey) }
        if contains(.option)  { flags |= UInt32(optionKey) }
        if contains(.shift)   { flags |= UInt32(shiftKey) }
        if contains(.command) { flags |= UInt32(cmdKey) }
        return flags
    }

    public var symbolsString: String {
        var s = ""
        if contains(.control) { s += "⌃" }
        if contains(.option)  { s += "⌥" }
        if contains(.shift)   { s += "⇧" }
        if contains(.command) { s += "⌘" }
        return s
    }

    public var hasPrimaryModifier: Bool {
        contains(.command) || contains(.control) || contains(.option)
    }
}

public enum ShortcutValidationError: LocalizedError, Equatable {
    case reservedEscape
    case requiresModifierForGlobal
    case requiresModifierInPanel
    case conflictsWithSystemShortcut(String)
    case conflictsWithAppAction(String)

    public var errorDescription: String? {
        switch self {
        case .reservedEscape:
            return "Esc 键用于取消或关闭面板，不能单独绑定"
        case .requiresModifierForGlobal:
            return "全局快捷键需包含 ⌘ / ⌃ / ⌥ 修饰键（或使用 F1~F20）"
        case .requiresModifierInPanel:
            return "面板内快捷键需包含 ⌘ / ⌃ / ⌥（避免影响搜索框正常打字）"
        case .conflictsWithSystemShortcut(let key):
            return "\(key) 是 macOS 系统核心快捷键，请换一个组合"
        case .conflictsWithAppAction(let actionTitle):
            return "与“\(actionTitle)”的快捷键冲突"
        }
    }
}

public struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    public let keyCode: UInt16
    public let modifiers: ShortcutModifiers

    public init(keyCode: UInt16, modifiers: ShortcutModifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var carbonKeyCode: UInt32 {
        UInt32(keyCode)
    }

    public var carbonModifiers: UInt32 {
        modifiers.carbonFlags
    }

    public var keySymbol: String {
        KeyCodeMapper.symbol(for: keyCode)
    }

    public var displayString: String {
        "\(modifiers.symbolsString)\(keySymbol)"
    }

    public func matches(event: NSEvent) -> Bool {
        let eventMods = ShortcutModifiers(nsFlags: event.modifierFlags)
        guard eventMods == modifiers else { return false }
        if event.keyCode == keyCode {
            return true
        }
        // Treat main Return (36) and Keypad Enter (76) equivalently
        if (keyCode == UInt16(kVK_Return) && event.keyCode == UInt16(kVK_ANSI_KeypadEnter)) ||
           (keyCode == UInt16(kVK_ANSI_KeypadEnter) && event.keyCode == UInt16(kVK_Return)) {
            return true
        }
        return false
    }

    public func validateFormat(isGlobal: Bool) -> Result<Void, ShortcutValidationError> {
        if keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
            return .failure(.reservedEscape)
        }

        let isFunctionKey = KeyCodeMapper.isFunctionKey(keyCode)

        if isGlobal {
            if !modifiers.hasPrimaryModifier && !isFunctionKey {
                return .failure(.requiresModifierForGlobal)
            }
            if modifiers == [.command] {
                let protectedCmdKeys: Set<UInt16> = [
                    UInt16(kVK_ANSI_C),
                    UInt16(kVK_ANSI_V),
                    UInt16(kVK_ANSI_X),
                    UInt16(kVK_ANSI_Z),
                    UInt16(kVK_ANSI_A),
                    UInt16(kVK_ANSI_Q),
                    UInt16(kVK_ANSI_W),
                    UInt16(kVK_Tab),
                    UInt16(kVK_Space)
                ]
                if protectedCmdKeys.contains(keyCode) {
                    return .failure(.conflictsWithSystemShortcut(displayString))
                }
            }
            return .success(())
        } else {
            // Panel-local shortcut: keep basic typing and arrow/enter navigation intact
            if modifiers.hasPrimaryModifier || isFunctionKey {
                if modifiers == [.command] {
                    let protectedEditKeys: Set<UInt16> = [
                        UInt16(kVK_ANSI_C),
                        UInt16(kVK_ANSI_V),
                        UInt16(kVK_ANSI_X),
                        UInt16(kVK_ANSI_A),
                        UInt16(kVK_ANSI_Z),
                        UInt16(kVK_ANSI_Comma)
                    ]
                    if protectedEditKeys.contains(keyCode) {
                        return .failure(.conflictsWithSystemShortcut(displayString))
                    }
                }
                return .success(())
            }
            // Allow Shift + non-printable special keys inside panel (such as Shift+Return ⇧↩ or Shift+Delete ⇧⌫)
            if modifiers == [.shift] && KeyCodeMapper.isNonCharacterSpecialKey(keyCode) {
                return .success(())
            }
            return .failure(.requiresModifierInPanel)
        }
    }

    // Common presets
    public static let defaultTogglePanel = KeyShortcut(keyCode: UInt16(kVK_ANSI_Grave), modifiers: [.control])
    public static let cmdShiftV = KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.command, .shift])
    public static let ctrlOptV = KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .option])
    public static let optSpace = KeyShortcut(keyCode: UInt16(kVK_Space), modifiers: [.option])

    public static let defaultPanelPastePlain = KeyShortcut(keyCode: UInt16(kVK_Return), modifiers: [.shift])
    public static let defaultPanelTogglePin  = KeyShortcut(keyCode: UInt16(kVK_ANSI_P), modifiers: [.command])
    public static let defaultPanelDeleteClip = KeyShortcut(keyCode: UInt16(kVK_Delete), modifiers: [.command])
    public static let defaultPanelPinWindow  = KeyShortcut(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command])
}

public enum ShortcutActionID: String, CaseIterable, Codable, Identifiable, Sendable {
    // Global hotkeys (work in any app via Carbon RegisterEventHotKey)
    case togglePanel        = "global.toggle_panel"
    case pasteLatestPlain   = "global.paste_latest_plain"
    case quickPasteSlot1    = "global.quick_paste_1"
    case quickPasteSlot2    = "global.quick_paste_2"
    case quickPasteSlot3    = "global.quick_paste_3"

    // Panel shortcuts (work when Quick Paste window is open)
    case panelPastePlain    = "panel.paste_plain"
    case panelTogglePin     = "panel.toggle_pin"
    case panelDeleteClip    = "panel.delete_clip"
    case panelPinWindow     = "panel.pin_window"

    public var id: String { rawValue }

    public var isGlobal: Bool {
        switch self {
        case .togglePanel, .pasteLatestPlain, .quickPasteSlot1, .quickPasteSlot2, .quickPasteSlot3:
            return true
        case .panelPastePlain, .panelTogglePin, .panelDeleteClip, .panelPinWindow:
            return false
        }
    }

    public var carbonHotKeyID: UInt32 {
        switch self {
        case .togglePanel:      return 1
        case .pasteLatestPlain: return 2
        case .quickPasteSlot1:  return 3
        case .quickPasteSlot2:  return 4
        case .quickPasteSlot3:  return 5
        default:                return 0
        }
    }

    public static var globalActions: [ShortcutActionID] {
        [.togglePanel, .pasteLatestPlain, .quickPasteSlot1, .quickPasteSlot2, .quickPasteSlot3]
    }

    public static var panelActions: [ShortcutActionID] {
        [.panelPastePlain, .panelTogglePin, .panelDeleteClip, .panelPinWindow]
    }

    public static func fromCarbonHotKeyID(_ id: UInt32) -> ShortcutActionID? {
        globalActions.first { $0.carbonHotKeyID == id }
    }

    public var title: String {
        switch self {
        case .togglePanel:      return "呼出 / 收起剪贴板面板"
        case .pasteLatestPlain: return "全局纯文本粘贴最新一条"
        case .quickPasteSlot1:  return "全局直接粘贴第 1 条记录"
        case .quickPasteSlot2:  return "全局直接粘贴第 2 条记录"
        case .quickPasteSlot3:  return "全局直接粘贴第 3 条记录"
        case .panelPastePlain:  return "纯文本粘贴选中项"
        case .panelTogglePin:   return "置顶收藏 / 取消置顶"
        case .panelDeleteClip:  return "删除当前选中记录"
        case .panelPinWindow:   return "钉住 / 取消钉住悬浮窗"
        }
    }

    public var subtitle: String {
        switch self {
        case .togglePanel:      return "在任意应用中打开或隐藏 air-cc 悬浮窗"
        case .pasteLatestPlain: return "无需打开面板，直接剥离富文本格式粘贴刚复制的内容"
        case .quickPasteSlot1:  return "直接粘贴列表排第 1 的记录（如置顶常用语）"
        case .quickPasteSlot2:  return "直接粘贴列表排第 2 的记录"
        case .quickPasteSlot3:  return "直接粘贴列表排第 3 的记录"
        case .panelPastePlain:  return "面板打开时剥离样式粘贴（文件则粘贴路径）"
        case .panelTogglePin:   return "切换当前高亮条目的 Sticky 永久置顶状态"
        case .panelDeleteClip:  return "从本地数据库中移除当前选中的历史条目"
        case .panelPinWindow:   return "保持悬浮窗常驻不自动收起，方便连续多次粘贴"
        }
    }

    public var defaultShortcut: KeyShortcut? {
        switch self {
        case .togglePanel:      return .defaultTogglePanel
        case .pasteLatestPlain: return nil
        case .quickPasteSlot1:  return nil
        case .quickPasteSlot2:  return nil
        case .quickPasteSlot3:  return nil
        case .panelPastePlain:  return .defaultPanelPastePlain
        case .panelTogglePin:   return .defaultPanelTogglePin
        case .panelDeleteClip:  return .defaultPanelDeleteClip
        case .panelPinWindow:   return .defaultPanelPinWindow
        }
    }
}

public enum KeyCodeMapper {
    public static func isFunctionKey(_ keyCode: UInt16) -> Bool {
        functionKeyMap[keyCode] != nil
    }

    public static func isNonCharacterSpecialKey(_ keyCode: UInt16) -> Bool {
        specialNonCharKeys.contains(keyCode) || isFunctionKey(keyCode)
    }

    public static func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    public static func symbol(for keyCode: UInt16) -> String {
        if let mapped = keyMap[keyCode] {
            return mapped
        }
        if let fn = functionKeyMap[keyCode] {
            return fn
        }
        return "Key\(keyCode)"
    }

    private static let modifierKeyCodes: Set<UInt16> = [
        UInt16(kVK_Command),
        UInt16(kVK_RightCommand),
        UInt16(kVK_Shift),
        UInt16(kVK_RightShift),
        UInt16(kVK_Option),
        UInt16(kVK_RightOption),
        UInt16(kVK_Control),
        UInt16(kVK_RightControl),
        UInt16(kVK_CapsLock),
        UInt16(kVK_Function)
    ]

    private static let specialNonCharKeys: Set<UInt16> = [
        UInt16(kVK_Return),
        UInt16(kVK_ANSI_KeypadEnter),
        UInt16(kVK_Tab),
        UInt16(kVK_Delete),
        UInt16(kVK_ForwardDelete),
        UInt16(kVK_LeftArrow),
        UInt16(kVK_RightArrow),
        UInt16(kVK_UpArrow),
        UInt16(kVK_DownArrow),
        UInt16(kVK_Home),
        UInt16(kVK_End),
        UInt16(kVK_PageUp),
        UInt16(kVK_PageDown)
    ]

    private static let functionKeyMap: [UInt16: String] = [
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20"
    ]

    private static let keyMap: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A",
        UInt16(kVK_ANSI_B): "B",
        UInt16(kVK_ANSI_C): "C",
        UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E",
        UInt16(kVK_ANSI_F): "F",
        UInt16(kVK_ANSI_G): "G",
        UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I",
        UInt16(kVK_ANSI_J): "J",
        UInt16(kVK_ANSI_K): "K",
        UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M",
        UInt16(kVK_ANSI_N): "N",
        UInt16(kVK_ANSI_O): "O",
        UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q",
        UInt16(kVK_ANSI_R): "R",
        UInt16(kVK_ANSI_S): "S",
        UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U",
        UInt16(kVK_ANSI_V): "V",
        UInt16(kVK_ANSI_W): "W",
        UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y",
        UInt16(kVK_ANSI_Z): "Z",

        UInt16(kVK_ANSI_0): "0",
        UInt16(kVK_ANSI_1): "1",
        UInt16(kVK_ANSI_2): "2",
        UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4",
        UInt16(kVK_ANSI_5): "5",
        UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8",
        UInt16(kVK_ANSI_9): "9",

        UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_ANSI_Minus): "-",
        UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\",
        UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'",
        UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/",

        UInt16(kVK_ANSI_Keypad0): "Num0",
        UInt16(kVK_ANSI_Keypad1): "Num1",
        UInt16(kVK_ANSI_Keypad2): "Num2",
        UInt16(kVK_ANSI_Keypad3): "Num3",
        UInt16(kVK_ANSI_Keypad4): "Num4",
        UInt16(kVK_ANSI_Keypad5): "Num5",
        UInt16(kVK_ANSI_Keypad6): "Num6",
        UInt16(kVK_ANSI_Keypad7): "Num7",
        UInt16(kVK_ANSI_Keypad8): "Num8",
        UInt16(kVK_ANSI_Keypad9): "Num9",
        UInt16(kVK_ANSI_KeypadDecimal): "Num.",
        UInt16(kVK_ANSI_KeypadMultiply): "Num*",
        UInt16(kVK_ANSI_KeypadPlus): "Num+",
        UInt16(kVK_ANSI_KeypadClear): "Clear",
        UInt16(kVK_ANSI_KeypadDivide): "Num/",
        UInt16(kVK_ANSI_KeypadMinus): "Num-",
        UInt16(kVK_ANSI_KeypadEquals): "Num=",

        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "↩",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟"
    ]
}
