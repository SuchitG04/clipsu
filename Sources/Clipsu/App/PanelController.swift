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
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
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
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let code = event.keyCode

        // Editing: pass keys to the text editor, but capture Esc (cancel), ⌘↵ (save)
        // and ⌘Z/⌘⇧Z (undo/redo — no main menu exists to route these for us).
        if appState.editingItem != nil {
            if code == 53 { appState.cancelEdit(); return nil }
            if (code == 36 || code == 76) && cmd { appState.commitEdit(); return nil }
            if cmd, chars == "z" {
                if let textView = panel.firstResponder as? NSTextView, let undo = textView.undoManager {
                    if event.modifierFlags.contains(.shift) { undo.redo() } else { undo.undo() }
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

        switch code {
        case 53: // escape
            if appState.showingActions { appState.closeActions() } else { hide() }
            return nil
        case 126: // up arrow
            if appState.showingActions { appState.actionsPrevious() } else { appState.selectPrevious() }
            return nil
        case 125: // down arrow
            if appState.showingActions { appState.actionsNext() } else { appState.selectNext() }
            return nil
        case 36, 76: // return / enter
            if appState.showingActions {
                appState.performSelectedAction()
            } else if cmd {
                if let item = appState.selectedItem { appState.paste(item, plainOnly: true) }
            } else if let item = appState.selectedItem {
                appState.activate(item)
            }
            return nil
        default:
            break
        }

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
            if code == 51 { appState.perform(.delete); return nil } // ⌘⌫
        }

        // Space → Quick Look an image, but only when not typing a search.
        if code == 49, appState.query.isEmpty, !appState.showingActions,
           let item = appState.selectedItem, item.kind == .image {
            appState.quickLook(item)
            return nil
        }

        return event
    }
}
