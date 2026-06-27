import SwiftUI
import ClipsuCore

/// A contextual action available for a clipboard item. Keeps title/glyph/shortcut and behaviour together
/// so the ⌘K menu and the global key monitor stay in sync.
enum ClipAction: CaseIterable {
    case paste
    case pastePlain
    case copy
    case edit
    case pin
    case openInBrowser
    case openImage
    case quickLook
    case saveImage
    case copyOCR
    case revealSource
    case delete
    case clearAll

    var title: String {
        switch self {
        case .paste:         return "Paste"
        case .pastePlain:    return "Paste as Plain Text"
        case .copy:          return "Copy to Clipboard"
        case .edit:          return "Edit"
        case .pin:           return "Pin / Unpin"
        case .openInBrowser: return "Open in Browser"
        case .openImage:     return "Open Image"
        case .quickLook:     return "Quick Look"
        case .saveImage:     return "Save Image…"
        case .copyOCR:       return "Copy Recognized Text"
        case .revealSource:  return "Reveal Source App"
        case .delete:        return "Delete"
        case .clearAll:      return "Clear All History…"
        }
    }

    var symbol: String {
        switch self {
        case .paste:         return "doc.on.clipboard"
        case .pastePlain:    return "textformat"
        case .copy:          return "doc.on.doc"
        case .edit:          return "pencil"
        case .pin:           return "pin"
        case .openInBrowser: return "safari"
        case .openImage:     return "photo"
        case .quickLook:     return "eye"
        case .saveImage:     return "square.and.arrow.down"
        case .copyOCR:       return "text.viewfinder"
        case .revealSource:  return "app.badge"
        case .delete:        return "trash"
        case .clearAll:      return "trash.slash"
        }
    }

    /// Display shortcut hint, e.g. "⌘C".
    var shortcutHint: String {
        switch self {
        case .paste:         return "↵"
        case .pastePlain:    return "⌘↵"
        case .copy:          return "⌘C"
        case .edit:          return "⌘E"
        case .pin:           return "⌘P"
        case .openInBrowser: return "⌘O"
        case .openImage:     return "⌘O"
        case .quickLook:     return "Space"
        case .saveImage:     return "⌘S"
        case .delete:        return "⌘⌫"
        default:             return ""
        }
    }

    var isDestructive: Bool { self == .delete || self == .clearAll }

    /// Whether this action applies to the given item.
    func applies(to item: ClipboardItem) -> Bool {
        switch self {
        case .pastePlain, .edit:
            return item.kind == .text || item.kind == .richText || item.kind == .link || item.kind == .color
        case .openInBrowser:
            return item.kind == .link
        case .openImage, .quickLook, .saveImage:
            return item.kind == .image
        case .copyOCR:
            return item.ocrText?.isEmpty == false
        case .revealSource:
            return item.sourceBundleID != nil
        default:
            return true
        }
    }

    @MainActor
    func perform(on item: ClipboardItem, appState: AppState) {
        switch self {
        case .paste:         appState.paste(item)
        case .pastePlain:    appState.paste(item, plainOnly: true)
        case .copy:          appState.copyToClipboard(item)
        case .edit:          appState.beginEdit(item)
        case .pin:           appState.togglePin(item)
        case .openInBrowser: appState.openInBrowser(item)
        case .openImage:     appState.openImage(item)
        case .quickLook:     appState.quickLook(item)
        case .saveImage:     appState.saveImage(item)
        case .copyOCR:       appState.copyOCRText(item)
        case .revealSource:  appState.revealSourceApp(item)
        case .delete:        appState.delete(item)
        case .clearAll:      appState.clearAll()
        }
    }

    /// Ordered list of actions applicable to an item.
    static func actions(for item: ClipboardItem) -> [ClipAction] {
        let order: [ClipAction] = [
            .paste, .pastePlain, .copy, .openInBrowser, .openImage, .quickLook,
            .edit, .pin, .saveImage, .copyOCR, .revealSource, .delete, .clearAll
        ]
        return order.filter { $0.applies(to: item) }
    }
}
