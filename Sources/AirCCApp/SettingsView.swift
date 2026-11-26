import AppKit
import ServiceManagement
import SwiftUI
import AirCCCore

struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var settings: AppSettings
    var onStatusIconNeedsUpdate: (() -> Void)?

    @StateObject private var recorderCoordinator = ShortcutRecorderCoordinator()
    @State private var selectedTab: SettingsTab = .shortcuts
    @State private var launchAtLogin: Bool = (SMAppService.mainApp.status == .enabled)
    @State private var confirmClearAlert: Bool = false

    enum SettingsTab: Hashable {
        case shortcuts
        case general
    }

    private let historyOptions = [100, 300, 500, 1000, 2000]

    init(viewModel: AppViewModel, onStatusIconNeedsUpdate: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
        self.onStatusIconNeedsUpdate = onStatusIconNeedsUpdate
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            shortcutsTab
                .tabItem {
                    Label("快捷键自定义", systemImage: "keyboard")
                }
                .tag(SettingsTab.shortcuts)

            generalTab
                .tabItem {
                    Label("通用与存储", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
        }
        .frame(width: 540, height: 490)
        .onChange(of: selectedTab) { _, _ in
            recorderCoordinator.stopRecording()
        }
        .onDisappear {
            recorderCoordinator.stopRecording()
        }
        .onAppear {
            viewModel.refreshAccessibilityStatus()
        }
        .alert("确认清空所有未置顶历史记录？", isPresented: $confirmClearAlert) {
            Button("取消", role: .cancel) {}
            Button("确认清空", role: .destructive) {
                viewModel.clearAllUnpinned()
            }
        } message: {
            Text("收藏置顶（Sticky）的记录会被完整保留，其余历史记录与对应缓存图片将被永久删除。")
        }
    }

    // MARK: - Shortcuts Tab

    private var shortcutsTab: some View {
        Form {
            Section {
                HStack(spacing: 8) {
                    Text("常用呼出预设：")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    quickPresetChip("⌃` (Ditto)", shortcut: .defaultTogglePanel)
                    quickPresetChip("⇧⌘V", shortcut: .cmdShiftV)
                    quickPresetChip("⌃⌥V", shortcut: .ctrlOptV)
                    quickPresetChip("⌥Space", shortcut: .optSpace)

                    Spacer()

                    Button("恢复全部默认") {
                        recorderCoordinator.stopRecording()
                        recorderCoordinator.validationMessage = nil
                        settings.resetAllShortcutsToDefault()
                        onStatusIconNeedsUpdate?()
                    }
                    .controlSize(.small)
                }
            }

            Section {
                ForEach(ShortcutActionID.globalActions) { action in
                    ShortcutRowRecorderView(
                        action: action,
                        settings: settings,
                        coordinator: recorderCoordinator,
                        onShortcutChanged: {
                            onStatusIconNeedsUpdate?()
                        }
                    )
                }
            } header: {
                Text("全局快捷键（在任意应用中均可直接触发）")
            } footer: {
                Text("提示：点击右侧按键框后直接按下目标组合键即可录制；录制时按 Esc 取消，按 ⌫ 清空。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(ShortcutActionID.panelActions) { action in
                    ShortcutRowRecorderView(
                        action: action,
                        settings: settings,
                        coordinator: recorderCoordinator,
                        onShortcutChanged: nil
                    )
                }
            } header: {
                Text("面板内操作快捷键（悬浮窗打开时生效）")
            } footer: {
                Text("内置固定导航：↑ / ↓ 上下选择 · ↩ 原格式粘贴 · ⌘1~⌘9（⇧⌘1~9 纯文本）快贴前 9 条 · Esc 清空或关闭。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func quickPresetChip(_ title: String, shortcut: KeyShortcut) -> some View {
        let isCurrent = settings.shortcut(for: .togglePanel) == shortcut
        return Button {
            recorderCoordinator.stopRecording()
            _ = settings.setShortcut(shortcut, for: .togglePanel)
            onStatusIconNeedsUpdate?()
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular, design: .monospaced))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.primary)
                .background(
                    isCurrent ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - General & Storage Tab

    private var generalTab: some View {
        Form {
            Section("启动与监听策略") {
                Toggle("登录 macOS 时自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = (SMAppService.mainApp.status == .enabled)
                        }
                    }

                Picker("最大保留条数（不含置顶）", selection: $settings.maxHistoryCount) {
                    ForEach(historyOptions, id: \.self) { count in
                        Text("\(count) 条").tag(count)
                    }
                }

                Toggle("粘贴后将该记录移至顶部", isOn: $settings.moveClipToTopOnPaste)

                Toggle("暂停监听剪贴板变化", isOn: $settings.monitoringPaused)
                    .onChange(of: settings.monitoringPaused) { _, _ in
                        onStatusIconNeedsUpdate?()
                    }
            }

            Section("直接粘贴权限（辅助功能）") {
                HStack {
                    Image(systemName: viewModel.isAccessibilityGranted ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(viewModel.isAccessibilityGranted ? .green : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(viewModel.isAccessibilityGranted ? "已授权：支持双击/回车/全局快贴直接上屏" : "未授权：选择后写入剪贴板，需手动按 ⌘V")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("macOS 发送模拟 ⌘V 按键需要“隐私与安全性 → 辅助功能”授权")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !viewModel.isAccessibilityGranted {
                        Button("请求授权") {
                            PasteService.requestAccessibilityPermission()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                viewModel.refreshAccessibilityStatus()
                            }
                        }
                    } else {
                        Button("刷新") {
                            viewModel.refreshAccessibilityStatus()
                        }
                    }
                }
            }

            Section("本地数据库（Local-First · 无网络上传）") {
                HStack {
                    Text("当前已存 \(viewModel.totalCount) 条（其中置顶 \(viewModel.pinnedCount) 条）")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("打开数据目录") {
                        NSWorkspace.shared.open(viewModel.store.baseDirectory)
                    }
                    Button("清空未置顶记录…", role: .destructive) {
                        confirmClearAlert = true
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
