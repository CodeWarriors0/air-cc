import AppKit
import SwiftUI
import AirCCCore

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct QuickPasteView: View {
    @ObservedObject var viewModel: AppViewModel
    @ObservedObject private var settings: AppSettings

    @FocusState private var isSearchFocused: Bool
    @State private var showPreviewPane: Bool = true
    @State private var lastClickedID: Int64?
    @State private var lastClickTime: TimeInterval = 0

    init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        self.settings = viewModel.settings
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeaderBar
            Divider().opacity(0.45)
            categoryFilterBar
            Divider().opacity(0.45)
            mainContentSplit
            Divider().opacity(0.45)
            footerStatusBar
        }
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
        }
        .onChange(of: viewModel.searchFocusTrigger) { _, _ in
            isSearchFocused = true
        }
    }

    // MARK: - Search Header

    private var searchHeaderBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索剪贴板历史（支持多词空格过滤）…", text: $viewModel.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($isSearchFocused)

            if !viewModel.searchQuery.isEmpty {
                Button {
                    viewModel.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空搜索词 (Esc)")
            }

            if settings.monitoringPaused {
                Text("已暂停监听")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }

            Divider()
                .frame(height: 16)
                .opacity(0.4)

            // Always on Top toggle (Ditto classic feature)
            Button {
                viewModel.isWindowPinned.toggle()
            } label: {
                Image(systemName: viewModel.isWindowPinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.isWindowPinned ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                    .background(
                        viewModel.isWindowPinned ? Color.accentColor.opacity(0.15) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
            .help(pinWindowTooltip)

            // Preview pane toggle
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    showPreviewPane.toggle()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(showPreviewPane ? Color.primary : Color.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help(showPreviewPane ? "收起右侧详情预览" : "展开右侧详情预览")

            // Settings button
            Button {
                viewModel.onRequestOpenSettings?()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .help("偏好设置 (⌘,)")

            // Close button
            Button {
                viewModel.onRequestClosePanel?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭面板 (Esc)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    // MARK: - Category Filter Bar

    private var categoryFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(ClipFilterCategory.allCases) { category in
                let isSelected = viewModel.selectedCategory == category
                Button {
                    viewModel.selectedCategory = category
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: category.symbolName)
                            .font(.system(size: 11))
                        Text(categoryLabel(for: category))
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .background(
                        isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.04),
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Text("\(viewModel.clips.count) 条匹配")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func categoryLabel(for category: ClipFilterCategory) -> String {
        if category == .pinned && viewModel.pinnedCount > 0 {
            return "\(category.title) \(viewModel.pinnedCount)"
        }
        return category.title
    }

    // MARK: - Main Content Split

    private var mainContentSplit: some View {
        Group {
            if viewModel.clips.isEmpty {
                emptyStateView
            } else {
                HStack(spacing: 0) {
                    clipListView
                        .frame(minWidth: 280, maxWidth: showPreviewPane ? .infinity : .infinity)

                    if showPreviewPane, let selected = viewModel.selectedClip {
                        Divider().opacity(0.45)
                        ClipDetailPreviewPane(
                            item: selected,
                            previewImage: viewModel.loadPreviewImage(for: selected),
                            settings: settings,
                            onPaste: { plain in
                                viewModel.paste(item: selected, plainTextOnly: plain)
                            },
                            onTogglePin: {
                                viewModel.togglePin(for: selected)
                            },
                            onDelete: {
                                viewModel.delete(item: selected)
                            }
                        )
                        .frame(width: 255)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: viewModel.searchQuery.isEmpty ? "doc.on.clipboard" : "magnifyingglass")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.tertiary)
            Text(viewModel.searchQuery.isEmpty ? "暂无剪贴板记录" : "没有找到匹配的剪贴板内容")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            Text(viewModel.searchQuery.isEmpty ? "在任意应用中按 ⌘C 复制文本、图片或文件，这里会自动保存" : "按 Esc 清空搜索条件")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var clipListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(Array(viewModel.clips.enumerated()), id: \.element.id) { index, item in
                        ClipRowView(
                            item: item,
                            rankIndex: index,
                            isSelected: viewModel.selectedClipID == item.id,
                            onRowClick: {
                                handleRowTap(item: item)
                            },
                            onTogglePin: {
                                viewModel.togglePin(for: item)
                            }
                        )
                        .id(item.id)
                        .contextMenu {
                            Button("粘贴 (↩)") {
                                viewModel.paste(item: item, plainTextOnly: false)
                            }
                            Button(menuTitle("纯文本粘贴", action: .panelPastePlain)) {
                                viewModel.paste(item: item, plainTextOnly: true)
                            }
                            Button("仅复制到剪贴板") {
                                viewModel.paste(item: item, plainTextOnly: false, copyOnly: true)
                            }
                            Divider()
                            Button(menuTitle(item.isPinned ? "取消置顶" : "置顶收藏", action: .panelTogglePin)) {
                                viewModel.togglePin(for: item)
                            }
                            Divider()
                            Button(menuTitle("删除记录", action: .panelDeleteClip), role: .destructive) {
                                viewModel.delete(item: item)
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onChange(of: viewModel.selectedClipID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(newID, anchor: nil)
                }
            }
        }
    }

    private func handleRowTap(item: ClipItem) {
        let now = ProcessInfo.processInfo.systemUptime
        let isDoubleClick = (lastClickedID == item.id) && ((now - lastClickTime) <= NSEvent.doubleClickInterval)
        lastClickedID = item.id
        lastClickTime = now

        viewModel.selectedClipID = item.id
        if isDoubleClick {
            let plainOnly = NSEvent.modifierFlags.contains(.shift)
            viewModel.paste(item: item, plainTextOnly: plainOnly)
        }
    }

    // MARK: - Footer Status Bar

    private var footerStatusBar: some View {
        HStack(spacing: 8) {
            if let message = viewModel.statusBannerMessage {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Text(message)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            } else if !viewModel.isAccessibilityGranted {
                Button {
                    PasteService.requestAccessibilityPermission()
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.orange)
                            .frame(width: 6, height: 6)
                        Text("授权辅助功能以启用双击/回车直接粘贴上屏")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .underline()
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text("共 \(viewModel.totalCount) 条 · 置顶 \(viewModel.pinnedCount) 条")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Text(footerShortcutHintText)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var pinWindowTooltip: String {
        let base = viewModel.isWindowPinned ? "取消钉住窗口（粘贴后自动关闭）" : "钉住窗口置顶（方便连续粘贴多条）"
        if let sc = settings.shortcut(for: .panelPinWindow) {
            return "\(base) (\(sc.displayString))"
        }
        return base
    }

    private func menuTitle(_ base: String, action: ShortcutActionID) -> String {
        if let sc = settings.shortcut(for: action) {
            return "\(base) (\(sc.displayString))"
        }
        return base
    }

    private var footerShortcutHintText: String {
        var parts = ["双击/↩ 粘贴"]
        if let plain = settings.shortcut(for: .panelPastePlain) {
            parts.append("\(plain.displayString) 纯文本")
        }
        parts.append("⌘1-9 快贴")
        if let pin = settings.shortcut(for: .panelTogglePin) {
            parts.append("\(pin.displayString) 置顶")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Row View

private struct ClipRowView: View {
    let item: ClipItem
    let rankIndex: Int
    let isSelected: Bool
    let onRowClick: () -> Void
    let onTogglePin: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 9) {
            // Ditto-inspired status indicator bar (Amber = Sticky/Pinned, Blue = Previously Pasted)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(indicatorColor)
                .frame(width: 3, height: 32)

            leadingIconOrThumbnail

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 12.5, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text(item.metadataSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("·")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)

                    Text(Self.relativeTime(from: item.updatedAt))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                if item.isPinned || isHovered {
                    Button(action: onTogglePin) {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 11))
                            .foregroundStyle(item.isPinned ? Color.orange : Color.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(item.isPinned ? "取消置顶" : "置顶收藏")
                }

                if rankIndex < 9 {
                    Text("⌘\(rankIndex + 1)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary.opacity(0.75))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            Color.primary.opacity(isSelected ? 0.10 : 0.05),
                            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
                        )
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            onRowClick()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var indicatorColor: Color {
        if item.isPinned {
            return .orange
        } else if item.pasteCount > 0 {
            return .blue.opacity(0.8)
        } else {
            return .clear
        }
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.20)
        } else if isHovered {
            return Color.primary.opacity(0.06)
        } else {
            return Color.clear
        }
    }

    @ViewBuilder
    private var leadingIconOrThumbnail: some View {
        if let thumbData = item.thumbnailData, let nsImage = NSImage(data: thumbData) {
            Image(nsImage: nsImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 32, height: 32)
                Image(systemName: item.kind.systemSymbolName)
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
    }

    static func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 15 { return "刚刚" }
        if seconds < 60 { return "\(seconds)秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)分前" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)小时前" }
        let days = hours / 24
        return "\(days)天前"
    }
}

// MARK: - Detail Preview Pane

private struct ClipDetailPreviewPane: View {
    let item: ClipItem
    let previewImage: NSImage?
    @ObservedObject var settings: AppSettings
    let onPaste: (_ plainTextOnly: Bool) -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header info
            HStack(spacing: 6) {
                Image(systemName: item.kind.systemSymbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(item.kind.label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if item.pasteCount > 0 {
                    Text("已粘贴 \(item.pasteCount) 次")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider().opacity(0.35)

            // Main preview body
            Group {
                switch item.kind {
                case .image:
                    imagePreviewBody
                case .files:
                    filesPreviewBody
                case .text, .richText:
                    textPreviewBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.35)

            // Action bar
            HStack(spacing: 6) {
                Button {
                    onPaste(false)
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11.5, weight: .medium))
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .help("按原格式粘贴 (↩)")

                if item.kind != .image {
                    Button {
                        onPaste(true)
                    } label: {
                        Text("纯文本")
                            .font(.system(size: 11.5))
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .help(tooltip("剥离样式以纯文本粘贴", for: .panelPastePlain))
                }

                Button(action: onTogglePin) {
                    Image(systemName: item.isPinned ? "pin.slash.fill" : "pin")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help(tooltip(item.isPinned ? "取消置顶" : "收藏置顶", for: .panelTogglePin))

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .help(tooltip("删除此条", for: .panelDeleteClip))
            }
            .padding(10)
        }
        .background(Color.primary.opacity(0.02))
    }

    private func tooltip(_ base: String, for action: ShortcutActionID) -> String {
        if let sc = settings.shortcut(for: action) {
            return "\(base) (\(sc.displayString))"
        }
        return base
    }

    private var textPreviewBody: some View {
        ScrollView {
            Text(item.plainText)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }

    private var imagePreviewBody: some View {
        VStack(spacing: 8) {
            if let img = previewImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(10)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 32))
                    .foregroundStyle(.tertiary)
            }
            Text("\(item.imageWidth) × \(item.imageHeight) px · \(ClipItem.formatBytes(item.byteSize))")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
    }

    private var filesPreviewBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(item.filePaths, id: \.self) { path in
                    HStack(spacing: 8) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(path)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 2)
                        if FileManager.default.fileExists(atPath: path) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
                            } label: {
                                Image(systemName: "arrow.right.circle")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("在访达 (Finder) 中显示")
                        }
                    }
                    .padding(6)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(10)
        }
    }
}
