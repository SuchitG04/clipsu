import AppKit
import SwiftUI
import ClipsuCore

/// A borderless panel that can still become key (so the search field accepts typing)
/// without activating the owning app — preserving the previous app's focus for paste-back.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Owns the floating clipboard panel: construction, positioning, show/hide, and the key monitor.
@MainActor
final class PanelController {
    private let appState: AppState
    private let settings: AppSettings
    private let panel: KeyablePanel
    private var keyMonitor: Any?

    /// Wired by AppDelegate to open Settings (⌘,).
    var onOpenSettings: (() -> Void)?

    init(appState: AppState, settings: AppSettings) {
        self.appState = appState
        self.settings = settings

        panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Theme.panelWidth, height: Theme.panelHeight),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        // Full-screen apps can draw above `.floating` windows. Use an overlay level
        // so the panel remains visible when invoked over another app's full-screen
        // Space (for example, a browser video player or game).
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .canJoinAllApplications,
            .fullScreenAuxiliary,
            .stationary,
        ]
        panel.animationBehavior = .utilityWindow
        panel.isMovableByWindowBackground = false

        let host = NSHostingView(rootView: PanelRootView(appState: appState))
        host.frame = panel.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        appState.hidePanel = { [weak self] in self?.hide() }

        // Dismiss when the panel loses focus (click outside / switch app),
        // unless we're mid-edit or a system dialog (save/open) is up.
        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleResignKey() }
        }
    }

    private func handleResignKey() {
        guard panel.isVisible else { return }
        if appState.editingItem != nil { return }   // don't discard an in-progress edit
        if panel.attachedSheet != nil { return }
        if NSApp.modalWindow != nil { return }       // save/open dialog open
        hide()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        positionPanel()
        appState.prepareForPresentation()
        appState.requestSearchFocus()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }
        installMonitor()
    }

    func hide() {
        if settings.panelPosition == .remembered { panel.saveFrame(usingName: "ClipsuPanel") }
        appState.closeActions()
        panel.orderOut(nil)
        removeMonitor()
    }

    // MARK: - Positioning

    private func positionPanel() {
        let screen = screenForCursor()
        let visible = screen.visibleFrame
        let size = panel.frame.size

        switch settings.panelPosition {
        case .remembered:
            if panel.setFrameUsingName("ClipsuPanel") { return }
            fallthrough
        case .center:
            let x = visible.midX - size.width / 2
            let y = visible.midY - size.height / 2 + visible.height * 0.06
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        case .cursor:
            let mouse = NSEvent.mouseLocation
            var x = mouse.x - size.width / 2
            var y = mouse.y - size.height + 20
            x = min(max(visible.minX + 8, x), visible.maxX - size.width - 8)
            y = min(max(visible.minY + 8, y), visible.maxY - size.height - 8)
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func screenForCursor() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Key handling

    private func installMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    private func removeMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        let cmd = event.modifierFlags.contains(.command)
        let shift = event.modifierFlags.contains(.shift)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode

        // Editing: pass keys to the text editor, but capture Esc (cancel), ⌘↵ (save)
        // and ⌘Z/⌘⇧Z (undo/redo — no main menu exists to route these for us).
        if appState.editingItem != nil {
            if code == 53 { appState.cancelEdit(); return nil }
            if (code == 36 || code == 76) && cmd { appState.commitEdit(); return nil }
            if cmd, chars == "z" {
                if let textView = panel.firstResponder as? NSTextView, let undo = textView.undoManager {
                    if shift { undo.redo() } else { undo.undo() }
                }
                return nil
            }
            return event
        }

        // Quick Look open: Space/Esc closes it; swallow other keys.
        if appState.quickLookItem != nil {
            if code == 53 || code == 49 { appState.closeQuickLook() }
            return nil
        }

        // ⌘ shortcuts — active in every mode (don't collide with single-letter vim commands).
        if cmd {
            switch chars {
            case "k": appState.toggleActions(); return nil
            case "c": appState.perform(.copy); return nil
            case "e": appState.perform(.edit); return nil
            case "p": appState.perform(.pin); return nil
            case "s": appState.perform(.saveImage); return nil
            case ",": onOpenSettings?(); return nil
            case "o":
                if let item = appState.selectedItem {
                    if item.kind == .link { appState.perform(.openInBrowser) }
                    else if item.kind == .image { appState.perform(.openImage) }
                }
                return nil
            default: break
            }
            if code == 51 { appState.perform(.delete); return nil }      // ⌘⌫
            if code == 36 || code == 76 {                                 // ⌘↵ → paste plain
                if !appState.showingActions, let item = appState.selectedItem {
                    appState.paste(item, plainOnly: true)
                }
                return nil
            }
        }

        // Tab / Shift-Tab cycles filters (both modes; not while the actions menu is open).
        if code == 48, !appState.showingActions {
            shift ? appState.previousFilter() : appState.nextFilter()
            return nil
        }

        if settings.vimEnabled {
            return appState.inputMode == .search
                ? handleVimSearch(event, code: code)
                : handleVimNormal(event, code: code, chars: chars, shift: shift)
        }

        return handleDefault(event, code: code)
    }

    // MARK: - Non-vim key handling (default)

    private func handleDefault(_ event: NSEvent, code: UInt16) -> NSEvent? {
        switch code {
        case 53: // escape
            if appState.showingActions { appState.closeActions() } else { hide() }
            return nil
        case 126: // up
            if appState.showingActions { appState.actionsPrevious() } else { appState.selectPrevious() }
            return nil
        case 125: // down
            if appState.showingActions { appState.actionsNext() } else { appState.selectNext() }
            return nil
        case 36, 76: // return
            if appState.showingActions {
                appState.performSelectedAction()
            } else if let item = appState.selectedItem {
                appState.activate(item)
            }
            return nil
        default:
            break
        }

        // Space → Quick Look an image, but only when not typing a search.
        if code == 49, appState.query.isEmpty, !appState.showingActions,
           let item = appState.selectedItem, item.kind == .image {
            appState.quickLook(item)
            return nil
        }

        return event
    }

    // MARK: - Vim key handling

    /// Search (insert) mode: typing reaches the search field; Esc/Enter return to Normal.
    private func handleVimSearch(_ event: NSEvent, code: UInt16) -> NSEvent? {
        switch code {
        case 53, 36, 76:                 // Esc / Return → back to Normal (top result selected)
            appState.enterNormal()
            return nil
        case 126:                        // up — navigate results while searching
            appState.selectPrevious(); return nil
        case 125:                        // down
            appState.selectNext(); return nil
        default:
            return event                 // let the search field receive the keystroke
        }
    }

    private func handleVimNormal(_ event: NSEvent, code: UInt16, chars: String, shift: Bool) -> NSEvent? {
        // --- Actions menu navigation ---
        if appState.showingActions {
            if let pending = appState.pendingOperator {
                appState.clearPending()
                if pending == "g", chars == "g" { appState.actionsFirst(); return nil }
            }
            switch chars {
            case "j": appState.actionsNext(); return nil
            case "k": appState.actionsPrevious(); return nil
            case "l": appState.performSelectedAction(); return nil
            case "h": appState.closeActions(); return nil
            case "g": shift ? appState.actionsLast() : appState.setPending("g"); return nil
            default: break
            }
            switch code {
            case 53, 51: appState.closeActions(); return nil      // Esc / Backspace → back
            case 36, 76: appState.performSelectedAction(); return nil
            case 126: appState.actionsPrevious(); return nil
            case 125: appState.actionsNext(); return nil
            default: return nil                                   // swallow other keys
            }
        }

        // --- List navigation ---
        // Resolve a pending two-stroke command (gg / dd / yy).
        if let pending = appState.pendingOperator {
            appState.clearPending()
            if chars == String(pending) {
                switch pending {
                case "g": appState.selectFirst()
                case "d": if let item = appState.selectedItem { appState.delete(item) }
                case "y": if let item = appState.selectedItem { appState.copyToClipboard(item) }
                default: break
                }
                return nil
            }
            // mismatched second key: pending cleared, fall through and treat this key freshly.
        }

        switch code {
        case 53: hide(); return nil                              // Esc closes the panel
        case 36, 76:                                             // Enter pastes
            if let item = appState.selectedItem { appState.activate(item) }
            return nil
        case 126: appState.selectPrevious(); return nil          // up arrow
        case 125: appState.selectNext(); return nil              // down arrow
        case 49:                                                 // Space → Quick Look image
            if let item = appState.selectedItem, item.kind == .image { appState.quickLook(item) }
            return nil
        default: break
        }

        if chars == "g", shift { appState.selectLast(); return nil }   // G → bottom

        switch chars {
        case "j": appState.selectNext(); return nil
        case "k": appState.selectPrevious(); return nil
        case "l": appState.toggleActions(); return nil
        case "x": appState.perform(.delete); return nil
        case "p": appState.perform(.pin); return nil
        case "g": appState.setPending("g"); return nil
        case "d": appState.setPending("d"); return nil
        case "y": appState.setPending("y"); return nil
        case "/": appState.enterSearch(); return nil
        case "i": appState.perform(.edit); return nil           // insert → edit the entry
        default: return nil                                      // swallow other keys in Normal mode
        }
    }
}
