import AppKit
import ClipsuCore

/// Places an item back onto the pasteboard and (optionally) synthesises ⌘V into the frontmost app.
final class PasteService {
    /// Writes the item's richest representation to the general pasteboard.
    func place(_ item: ClipboardItem, plainOnly: Bool = false) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.kind {
        case .image:
            if let path = item.imagePath, let data = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(data, forType: .png)
            }
        case .file:
            if let paths = item.fileURLs, !paths.isEmpty {
                let urls = paths.map { NSURL(fileURLWithPath: $0) }
                pb.writeObjects(urls)
            } else if let text = item.plainText {
                pb.setString(text, forType: .string)
            }
        case .richText:
            if !plainOnly, let rtf = item.richData {
                pb.setData(rtf, forType: .rtf)
            }
            if let text = item.plainText { pb.setString(text, forType: .string) }
        case .text, .link, .color:
            if let text = item.plainText { pb.setString(text, forType: .string) }
        }
    }

    /// Synthesises a ⌘V keystroke to the frontmost application. Requires Accessibility permission.
    func synthesizePaste() {
        guard AXIsProcessTrusted() else {
            Log.error("paste skipped: Accessibility permission not granted")
            return
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKeyCode: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    var hasAccessibility: Bool { AXIsProcessTrusted() }

    /// Prompts the user to grant Accessibility (opens the system dialog once).
    @discardableResult
    func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
