# air-cc · 空气剪切板

> **Air Clipboard for macOS** — 轻若空气、呼之即来的原生 macOS 剪贴板历史与快捷粘贴工具。

参考经典开源剪贴板工具 [Ditto](https://github.com/sabrogden/Ditto) 的核心效率哲学，采用 **SwiftUI + AppKit 原生混编 + SQLite3** 打造：无第三方重依赖、无网络上传、整包体积不到 2 MB，常驻右上角菜单栏随叫随到。

---

## 核心特性

- **Local-First 纯本地持久化**
  - 无账号、零遥测、零云端上传，所有数据仅保存在本地 `~/Library/Application Support/air-cc/clips.sqlite3`（WAL 模式）。
- **多格式自动捕获与智能去重**
  - 原生支持 **纯文本**、**富文本 (RTF / HTML)**、**图片（自动生成高清缩略图 + 按需磁盘原图缓存）** 与 **Finder 文件列表**。
  - 基于 SHA-256 自动去重合并：重复复制相同内容自动刷新至顶部并保留置顶/粘贴计数。
  - **隐私保护**：自动识别并跳过 1Password、Apple 密码等密码管理器写入的敏感数据（`org.nspasteboard.ConcealedType`）。
- **不抢焦点的毛玻璃悬浮窗 (`NSPanel`)**
  - 基于 `.nonactivatingPanel` 构建，全屏应用与多桌面空间下无缝弹出，关闭或粘贴后自动把焦点精准归还给原窗口。
  - 支持右上角图钉 **钉住窗口置顶（Always on Top）**，方便连续双击粘贴多条记录。
- **全套自定义快捷键与实时按键录制器**
  - 内置交互式按键录制组件，支持录制任意修饰键组合与 `F1`~`F20` 功能键，自带系统核心热键保护与应用内冲突检测：
    - **全局快捷键**（任意应用内直接触发）：呼出/收起面板（默认 `⌃`` `）、**全局纯文本粘贴最新一条**、**全局直接粘贴第 1 / 2 / 3 条记录**。
    - **面板内快捷键**：纯文本粘贴（默认 `⇧↩`）、置顶收藏（默认 `⌘P`）、删除记录（默认 `⌘⌫`）、钉住悬浮窗（默认 `⌘T`）。

---

## 默认操作与快捷键一览

| 按键 / 操作 | 功能说明 |
| :--- | :--- |
| **`⌃`` ` (Control + ~)** | 全局呼出 / 收起 `air-cc` 剪贴板面板（可在 `⌘,` 设置中自由录制修改） |
| **菜单栏图标** | **左键单击**直接呼出/收起面板；**右键单击**打开快捷菜单 |
| **直接输入文字** | 打开即聚焦搜索框，支持**空格分词多关键词**实时检索文本、文件名与来源应用 |
| **`↑` / `↓`** | 上下切换选中记录（自动识别中文输入法候选框，选词不误触） |
| **双击** 或 **`↩`** | **原格式粘贴**（保留富文本样式、图片或 Finder 文件对象） |
| **`⇧↩` (Shift + Return)** | **纯文本粘贴**（一键剥离网页/文档样式；文件记录则粘贴完整路径） |
| **`⌘1` ~ `⌘9`** | 一键快贴前 9 条记录（搭配 `⇧⌘1` ~ `⇧⌘9` 为纯文本快贴） |
| **`⌘P`** | **置顶收藏 / 取消置顶**（Sticky 记录固定排在最前且永不被容量上限淘汰） |
| **`⌘T`** | 钉住 / 取消钉住悬浮窗（Always on Top） |
| **`⌘⌫` / `Esc`** | `⌘⌫` 删除当前选中项；`Esc` 先清空搜索与筛选，再按收起面板 |

---

## 编译与运行

**环境要求**：macOS 14.0+（Apple Silicon / Intel），安装 Xcode 或 Xcode Command Line Tools（Swift 5.10+）。

```bash
# 克隆仓库
git clone https://github.com/CodeWarriors0/air-cc.git
cd air-cc

# 一键运行自动化自检测试并打包签名 dist/air-cc.app
chmod +x scripts/build_app.sh
./scripts/build_app.sh

# 启动应用（常驻菜单栏，首次加 --show 可立即弹出主面板预览）
open -a ./dist/air-cc.app --args --show
```

也可将生成的 `dist/air-cc.app` 直接拖入 `/Applications` 目录，并在 `⌘,` 偏好设置中开启 **登录 macOS 时自动启动**。

> **自动上屏粘贴权限说明**：macOS 向当前光标窗口自动发送模拟 `⌘V` 需要辅助功能权限。首次使用时可在面板底部或「偏好设置 → 通用与存储」中点击授权 **系统设置 → 隐私与安全性 → 辅助功能**；未授权时选择条目也会自动写入系统剪贴板，手动按 `⌘V` 即可粘贴。

---

## 目录结构

```text
air-cc/
├── Package.swift                 # SwiftPM 工程清单
├── Resources/Info.plist          # macOS App Bundle 元信息 (LSUIElement 菜单栏应用)
├── Sources/
│   ├── AirCCCore/                # 核心层：SQLite3 存储、多格式捕获、粘贴服务、Carbon 全局热键、快捷键模型
│   ├── AirCCApp/                 # 界面层：NSPanel 悬浮窗、SwiftUI 列表与详情预览、按键录制器与偏好设置
│   └── AirCCSelfTest/            # 独立自动化自检测试套件
└── scripts/
    ├── generate_icon.swift       # CoreGraphics 矢量图标生成脚本 (.icns)
    └── build_app.sh              # 自动化测试 + Release 编译 + .app 组装签名脚本
```

## License

[MIT](LICENSE)
