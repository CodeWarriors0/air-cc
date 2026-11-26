import AppKit
import Carbon
import Foundation
import AirCCCore

@inline(__always)
func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
    if !condition() {
        fputs("❌ Test assertion failed (\(file):\(line)): \(message)\n", stderr)
        exit(1)
    }
}

func makeTempStore() throws -> (DatabaseStore, URL) {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("AirCCTests-\(UUID().uuidString)", isDirectory: true)
    let store = try DatabaseStore(baseDirectory: dir)
    return (store, dir)
}

func testUpsertDeduplicationAndPinPreservation() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let payload1 = CapturedClipPayload(
        contentHash: ClipboardCapture.sha256Hex(Data("hello world".utf8)),
        kind: .text,
        title: "hello world",
        plainText: "hello world",
        byteSize: 11,
        sourceAppName: "Terminal"
    )
    guard let first = store.upsertClip(payload1) else {
        check(false, "Expected first clip to save")
        return
    }
    check(first.plainText == "hello world", "Plain text matches")
    check(!first.isPinned, "Initially unpinned")

    check(store.togglePin(id: first.id) == true, "Toggle pin turns on")
    store.recordPaste(id: first.id, moveToTop: true)

    let payload2 = CapturedClipPayload(
        contentHash: ClipboardCapture.sha256Hex(Data("second item".utf8)),
        kind: .text,
        title: "second item",
        plainText: "second item",
        byteSize: 11
    )
    check(store.upsertClip(payload2) != nil, "Second clip saved")

    Thread.sleep(forTimeInterval: 0.02)
    guard let deduped = store.upsertClip(payload1) else {
        check(false, "Expected deduplicated upsert to return item")
        return
    }
    check(deduped.id == first.id, "Deduplicated item keeps original row ID")
    check(deduped.isPinned, "Deduplicated item preserves pinned state")
    check(deduped.pasteCount == 1, "Deduplicated item preserves paste count")
    check(store.counts().total == 2, "Total count remains 2")
    check(store.counts().pinned == 1, "Pinned count remains 1")
    print("  ✓ testUpsertDeduplicationAndPinPreservation passed")
}

func testMaxHistoryPruningKeepsPinnedClips() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    for idx in 1...5 {
        let text = "Clip-\(idx)"
        let p = CapturedClipPayload(
            contentHash: ClipboardCapture.sha256Hex(Data(text.utf8)),
            kind: .text,
            title: text,
            plainText: text,
            byteSize: text.count
        )
        guard let saved = store.upsertClip(p, maxHistory: 10) else {
            check(false, "Clip-\(idx) should save")
            return
        }
        if idx == 1 {
            _ = store.togglePin(id: saved.id)
        }
        Thread.sleep(forTimeInterval: 0.01)
    }

    store.pruneIfNeeded(maxHistory: 2)
    let remaining = store.fetchClips()
    check(remaining.count == 3, "Expected 1 pinned + 2 newest unpinned = 3, got \(remaining.count)")
    check(remaining.first?.plainText == "Clip-1" && remaining.first?.isPinned == true, "Pinned item stays first and survives pruning")
    let texts = Set(remaining.map(\.plainText))
    check(texts.contains("Clip-5") && texts.contains("Clip-4"), "Newest unpinned kept")
    check(!texts.contains("Clip-2") && !texts.contains("Clip-3"), "Oldest unpinned pruned")
    print("  ✓ testMaxHistoryPruningKeepsPinnedClips passed")
}

func testSearchCategoryAndImageBlobs() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let textClip = CapturedClipPayload(
        contentHash: "h1",
        kind: .text,
        title: "Swift async await guide",
        plainText: "Swift async await guide for macOS",
        sourceAppName: "Safari"
    )
    let imageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let imgClip = CapturedClipPayload(
        contentHash: "h2",
        kind: .image,
        title: "图片 (800×600)",
        plainText: "图片 (800×600)",
        imagePNGData: imageBytes,
        imageWidth: 800,
        imageHeight: 600,
        byteSize: imageBytes.count
    )
    _ = store.upsertClip(textClip)
    guard let savedImg = store.upsertClip(imgClip) else {
        check(false, "Image clip should save")
        return
    }

    let matched = store.fetchClips(query: "swift safari", category: .all)
    check(matched.count == 1 && matched.first?.contentHash == "h1", "Multi-token search matches plainText + sourceAppName")

    let images = store.fetchClips(query: "", category: .image)
    check(images.count == 1, "Image category returns 1 item")
    check(store.loadBlobData(for: savedImg) == imageBytes, "Image blob roundtrips from disk")

    store.deleteClip(id: savedImg.id)
    check(store.fetchClips(category: .image).isEmpty, "Image clip deleted")
    print("  ✓ testSearchCategoryAndImageBlobs passed")
}

func testPasteboardCapturePrivacyAndPlainTextPaste() throws {
    let (store, dir) = try makeTempStore()
    defer { try? FileManager.default.removeItem(at: dir) }

    let pb = NSPasteboard.withUniqueName()
    defer { pb.releaseGlobally() }

    // 1. Concealed password item must be ignored
    pb.clearContents()
    let secretItem = NSPasteboardItem()
    secretItem.setString("super-secret-password", forType: .string)
    secretItem.setData(Data([1]), forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
    pb.writeObjects([secretItem])
    check(ClipboardCapture.capture(from: pb, sourceApp: nil) == nil, "Concealed password clipboard items must be ignored")

    // 2. Rich text capture + plain-text-only paste stripping
    pb.clearContents()
    let attr = NSAttributedString(
        string: "Bold Title",
        attributes: [.font: NSFont.boldSystemFont(ofSize: 16)]
    )
    let rtfData = try attr.data(
        from: NSRange(location: 0, length: attr.length),
        documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
    )
    let richPBItem = NSPasteboardItem()
    richPBItem.setString("Bold Title", forType: .string)
    richPBItem.setData(rtfData, forType: .rtf)
    pb.writeObjects([richPBItem])

    guard let captured = ClipboardCapture.capture(from: pb, sourceApp: nil) else {
        check(false, "Rich text item should be captured")
        return
    }
    check(captured.kind == .richText && captured.rtfData != nil, "Captured kind is richText with RTF data")

    guard let saved = store.upsertClip(captured) else {
        check(false, "Saved rich text clip")
        return
    }

    // Full paste keeps RTF and sets internal marker
    PasteService.writeToPasteboard(item: saved, store: store, plainTextOnly: false, pasteboard: pb)
    check(pb.string(forType: .string) == "Bold Title", "Full paste restores string")
    check(pb.data(forType: .rtf) != nil, "Full paste restores RTF")
    check(ClipboardCapture.capture(from: pb, sourceApp: nil) == nil, "Internal marker prevents self re-capture loop")

    // Plain-text-only paste strips RTF
    PasteService.writeToPasteboard(item: saved, store: store, plainTextOnly: true, pasteboard: pb)
    check(pb.string(forType: .string) == "Bold Title", "Plain paste writes plain string")
    check(pb.data(forType: .rtf) == nil, "Plain paste strips RTF formatting")
    print("  ✓ testPasteboardCapturePrivacyAndPlainTextPaste passed")
}

func testCustomShortcutsValidationConflictAndPersistence() throws {
    let suiteName = "io.github.codewarriors0.air-cc.tests.\(UUID().uuidString)"
    guard let testDefaults = UserDefaults(suiteName: suiteName) else {
        check(false, "Expected isolated UserDefaults suite")
        return
    }
    defer { testDefaults.removePersistentDomain(forName: suiteName) }

    let settings = AppSettings(defaults: testDefaults)
    check(settings.shortcut(for: .togglePanel)?.displayString == "⌃`", "Default toggle shortcut is ⌃`")
    check(settings.shortcut(for: .panelPastePlain)?.displayString == "⇧↩", "Default plain paste shortcut is ⇧↩")
    check(settings.shortcut(for: .panelTogglePin)?.displayString == "⌘P", "Default pin shortcut is ⌘P")
    check(settings.shortcut(for: .pasteLatestPlain) == nil, "Global plain paste starts unbound")

    // Reject single letter without primary modifier for global hotkey
    let bareV = KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [])
    if case .failure(.requiresModifierForGlobal) = settings.setShortcut(bareV, for: .togglePanel) {
        // expected
    } else {
        check(false, "Bare letter must be rejected for global shortcut")
    }

    // Reject system core shortcut ⌘C
    let cmdC = KeyShortcut(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command])
    if case .failure(.conflictsWithSystemShortcut) = settings.setShortcut(cmdC, for: .togglePanel) {
        // expected
    } else {
        check(false, "⌘C must be protected against override")
    }

    // Bind custom global shortcut ⌃⇧V to pasteLatestPlain
    let ctrlShiftV = KeyShortcut(keyCode: UInt16(kVK_ANSI_V), modifiers: [.control, .shift])
    if case .failure(let err) = settings.setShortcut(ctrlShiftV, for: .pasteLatestPlain) {
        check(false, "⌃⇧V should bind to pasteLatestPlain, got \(err)")
    }
    check(settings.shortcut(for: .pasteLatestPlain)?.displayString == "⌃⇧V", "Display string formats as ⌃⇧V")

    // Detect duplicate conflict across actions
    if case .failure(.conflictsWithAppAction) = settings.setShortcut(ctrlShiftV, for: .quickPasteSlot1) {
        // expected
    } else {
        check(false, "Duplicate shortcut across actions must be rejected")
    }

    // Clear a default-enabled panel shortcut and verify persistence across reload
    if case .failure(let err) = settings.setShortcut(nil, for: .panelPinWindow) {
        check(false, "Clearing panelPinWindow should succeed, got \(err)")
    }

    let reloaded = AppSettings(defaults: testDefaults)
    check(reloaded.shortcut(for: .pasteLatestPlain) == ctrlShiftV, "Custom shortcut persists across reload")
    check(reloaded.shortcut(for: .panelPinWindow) == nil, "Explicitly cleared default shortcut stays cleared across reload")

    // Reset all restores defaults
    reloaded.resetAllShortcutsToDefault()
    check(reloaded.shortcut(for: .togglePanel)?.displayString == "⌃`", "Reset restores ⌃`")
    check(reloaded.shortcut(for: .pasteLatestPlain) == nil, "Reset clears optional global shortcut")
    check(reloaded.shortcut(for: .panelPinWindow)?.displayString == "⌘T", "Reset restores ⌘T")
    print("  ✓ testCustomShortcutsValidationConflictAndPersistence passed")
}

do {
    try testUpsertDeduplicationAndPinPreservation()
    try testMaxHistoryPruningKeepsPinnedClips()
    try testSearchCategoryAndImageBlobs()
    try testPasteboardCapturePrivacyAndPlainTextPaste()
    try testCustomShortcutsValidationConflictAndPersistence()
    print("All air-cc self-tests passed!")
} catch {
    fputs("❌ Unexpected error in tests: \(error)\n", stderr)
    exit(1)
}
