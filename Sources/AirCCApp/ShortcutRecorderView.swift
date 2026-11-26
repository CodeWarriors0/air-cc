import AppKit
import Carbon
import SwiftUI
import AirCCCore

@MainActor
final class ShortcutRecorderCoordinator: ObservableObject {
    @Published var activeAction: ShortcutActionID?
    @Published var liveModifierPreview: String = ""
    @Published var validationMessage: String?

    private var eventMonitor: Any?
    private var outsideClickMonitor: Any?

    func startRecording(
        for action: ShortcutActionID,
        settings: AppSettings,
        onChanged: (() -> Void)?
    ) {
        stopRecording()
        activeAction = action
        liveModifierPreview = ""
        validationMessage = nil

        GlobalHotKeyManager.shared.suspendForRecording()

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, let currentAction = self.activeAction else { return event }

            if event.type == .flagsChanged {
                let mods = ShortcutModifiers(nsFlags: event.modifierFlags)
                self.liveModifierPreview = mods.symbolsString
                return nil
            }

            if event.type == .keyDown {
                let keyCode = event.keyCode
                if KeyCodeMapper.isModifierOnlyKey(keyCode) {
                    return nil
                }

                let mods = ShortcutModifiers(nsFlags: event.modifierFlags)

                // Bare Escape cancels recording without changing existing binding
                if keyCode == UInt16(kVK_Escape) && mods.isEmpty {
                    self.stopRecording()
                    return nil
                }

                // Bare Delete / ForwardDelete clears the shortcut
                if (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete)) && mods.isEmpty {
                    _ = settings.setShortcut(nil, for: currentAction)
                    self.stopRecording()
                    onChanged?()
                    return nil
                }

                let candidate = KeyShortcut(keyCode: keyCode, modifiers: mods)
                switch settings.setShortcut(candidate, for: currentAction) {
                case .success:
                    self.stopRecording()
                    onChanged?()
                case .failure(let error):
                    NSSound.beep()
                    self.validationMessage = error.localizedDescription
                    self.liveModifierPreview = ""
                }
                return nil
            }

            return event
        }

        outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Allow button clicks to manage state; keep clean if window loses focus
            _ = self
            return event
        }
    }

    func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        let wasRecording = (activeAction != nil)
        activeAction = nil
        liveModifierPreview = ""
        if wasRecording {
            GlobalHotKeyManager.shared.resumeAfterRecording()
        }
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }
}

struct ShortcutRowRecorderView: View {
    let action: ShortcutActionID
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: ShortcutRecorderCoordinator
    var onShortcutChanged: (() -> Void)?

    private var isRecording: Bool {
        coordinator.activeAction == action
    }

    private var currentShortcut: KeyShortcut? {
        settings.shortcut(for: action)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(action.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                recorderButton

                if currentShortcut != nil && !isRecording {
                    Button {
                        coordinator.validationMessage = nil
                        _ = settings.setShortcut(nil, for: action)
                        onShortcutChanged?()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("清除此快捷键")
                }

                if currentShortcut != action.defaultShortcut && !isRecording {
                    Button {
                        coordinator.validationMessage = nil
                        settings.resetShortcutToDefault(for: action)
                        onShortcutChanged?()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("恢复此项默认 (\(action.defaultShortcut?.displayString ?? "未设置"))")
                }
            }

            if isRecording, let errorMsg = coordinator.validationMessage {
                Text(errorMsg)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 2)
    }

    private var recorderButton: some View {
        Button {
            if isRecording {
                coordinator.stopRecording()
            } else {
                coordinator.startRecording(for: action, settings: settings, onChanged: onShortcutChanged)
            }
        } label: {
            HStack(spacing: 4) {
                if isRecording {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 6, height: 6)
                    Text(recordingPromptText)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                } else if let sc = currentShortcut {
                    Text(sc.displayString)
                        .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.primary)
                } else {
                    Text("点击录制")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(minWidth: 112, minHeight: 26)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isRecording ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isRecording ? Color.accentColor : Color.primary.opacity(0.14),
                        lineWidth: isRecording ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
        .help(isRecording ? "按下组合键完成设置，按 Esc 取消，按 ⌫ 清除" : "点击后按下键盘组合键进行自定义")
    }

    private var recordingPromptText: String {
        if !coordinator.liveModifierPreview.isEmpty {
            return "\(coordinator.liveModifierPreview)…"
        }
        return "请按键…"
    }
}
