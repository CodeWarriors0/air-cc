import AppKit
import ApplicationServices
import Carbon
import Foundation

public enum PasteOutcome: Equatable {
    case pastedDirectly
    case copiedOnly
    case copiedNeedsAccessibilityPermission
}

public enum PasteService {
    public static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public static func writeToPasteboard(
        item: ClipItem,
        store: DatabaseStore,
        plainTextOnly: Bool,
        pasteboard: NSPasteboard = .general
    ) {
        pasteboard.clearContents()

        if plainTextOnly {
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.plainText, forType: .string)
            pbItem.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
            pasteboard.writeObjects([pbItem])
            return
        }

        switch item.kind {
        case .text:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.plainText, forType: .string)
            pbItem.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
            pasteboard.writeObjects([pbItem])

        case .richText:
            let pbItem = NSPasteboardItem()
            pbItem.setString(item.plainText, forType: .string)
            if let rtf = item.rtfData, !rtf.isEmpty {
                pbItem.setData(rtf, forType: .rtf)
            }
            if let html = item.htmlData, !html.isEmpty {
                pbItem.setData(html, forType: .html)
            }
            pbItem.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
            pasteboard.writeObjects([pbItem])

        case .image:
            let pbItem = NSPasteboardItem()
            if let pngData = store.loadBlobData(for: item) {
                pbItem.setData(pngData, forType: .png)
                if let nsImage = NSImage(data: pngData),
                   let tiffData = nsImage.tiffRepresentation {
                    pbItem.setData(tiffData, forType: .tiff)
                }
            } else {
                pbItem.setString(item.plainText, forType: .string)
            }
            pbItem.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
            pasteboard.writeObjects([pbItem])

        case .files:
            let validURLs = item.filePaths
                .filter { FileManager.default.fileExists(atPath: $0) }
                .map { NSURL(fileURLWithPath: $0) }
            if !validURLs.isEmpty {
                pasteboard.writeObjects(validURLs)
                pasteboard.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
            } else {
                let pbItem = NSPasteboardItem()
                pbItem.setString(item.plainText, forType: .string)
                pbItem.setData(Data([1]), forType: ClipboardCapture.internalMarkerType)
                pasteboard.writeObjects([pbItem])
            }
        }
    }

    public static func performPaste(
        item: ClipItem,
        store: DatabaseStore,
        targetApp: NSRunningApplication?,
        plainTextOnly: Bool = false,
        copyOnly: Bool = false,
        moveToTop: Bool = true,
        completion: ((PasteOutcome) -> Void)? = nil
    ) {
        writeToPasteboard(
            item: item,
            store: store,
            plainTextOnly: plainTextOnly
        )
        store.recordPaste(id: item.id, moveToTop: moveToTop)

        if copyOnly {
            completion?(.copiedOnly)
            return
        }

        if let targetApp, !targetApp.isTerminated {
            targetApp.activate(options: [.activateAllWindows])
        }

        guard isAccessibilityTrusted() else {
            completion?(.copiedNeedsAccessibilityPermission)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.065) {
            synthesizeCommandV()
            completion?(.pastedDirectly)
        }
    }

    public static func synthesizeCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKeyCode = CGKeyCode(kVK_ANSI_V)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }
}
