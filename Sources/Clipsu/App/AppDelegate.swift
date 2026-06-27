import AppKit
import SwiftUI
import ClipsuCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var database: Database!
    private var imageStore: ImageStore!
    private var ocr: OCRService!
    private let settings = AppSettings.shared

    private var appState: AppState!
    private var capture: CaptureService!
    private var monitor: ClipboardMonitor!
    private var hotKey: HotKeyManager!
    private var panel: PanelController!

    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var retentionTimer: Timer?
    private var accessibilityAlertShowing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            database = try Database()
        } catch {
            presentFatal("Could not open the clipboard database:\n\(error)")
            return
        }
        imageStore = ImageStore()
        ocr = OCRService()

        appState = AppState(database: database, imageStore: imageStore, ocr: ocr, settings: settings)
        appState.onNeedsAccessibility = { [weak self] in self?.promptAccessibilityIfNeeded() }
        panel = PanelController(appState: appState, settings: settings)
        panel.onOpenSettings = { [weak self] in self?.openSettings() }

        capture = CaptureService(database: database, imageStore: imageStore, ocr: ocr, settings: settings)
        capture.onStoreChanged = { [weak self] in
            MainActor.assumeIsolated { self?.appState.reload() }
        }

        monitor = ClipboardMonitor()
        monitor.onChange = { [weak self] pasteboard in
            self?.capture.capture(from: pasteboard)
        }
        appState.acknowledgePasteboardWrite = { [weak self] in self?.monitor.acknowledgeOwnChange() }
        monitor.start()

        hotKey = HotKeyManager()
        hotKey.onHotKey = { [weak self] in
            MainActor.assumeIsolated { self?.panel.toggle() }
        }
        reRegisterHotKey()

        setupStatusItem()
        pruneRetention()
        startRetentionTimer()

        // First-run: nudge for Accessibility (needed for paste-back).
        if !PasteService().hasAccessibility {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                self?.promptAccessibilityIfNeeded()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKey?.unregister()
        retentionTimer?.invalidate()
    }

    // MARK: - Hotkey

    func reRegisterHotKey() {
        hotKey.register(keyCode: settings.hotKeyCode, nsModifiers: settings.hotKeyModifiers)
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipsu")
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "Open Clipsu", action: #selector(openPanel), keyEquivalent: "")
        menu.addItem(.separator())
        let pauseTitle = settings.paused ? "Resume Capturing" : "Pause Capturing"
        menu.addItem(withTitle: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Clipsu", action: #selector(quit), keyEquivalent: "q")
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    @objc private func openPanel() { panel.show() }

    @objc private func togglePause() {
        settings.paused.toggle()
        setupStatusItem() // rebuild to update title
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: - Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, appState: appState,
                                    onHotKeyChange: { [weak self] in self?.reRegisterHotKey() })
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 340),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            window.title = "Clipsu Settings"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Retention

    private func startRetentionTimer() {
        let timer = Timer(timeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pruneRetention() }
        }
        RunLoop.main.add(timer, forMode: .common)
        retentionTimer = timer
    }

    private func pruneRetention() {
        let mode = settings.retentionMode
        let count = settings.retentionCount
        let days = settings.retentionDays
        let db = database
        let store = imageStore
        DispatchQueue.global(qos: .utility).async {
            if let paths = try? db?.pruneRetention(mode: mode, count: count, days: days), !paths.isEmpty {
                store?.deleteFiles(paths)
                DispatchQueue.main.async { [weak self] in self?.appState.reload() }
            }
        }
    }

    // MARK: - Accessibility / errors

    private func promptAccessibilityIfNeeded() {
        guard !accessibilityAlertShowing, !PasteService().hasAccessibility else { return }
        accessibilityAlertShowing = true
        defer { accessibilityAlertShowing = false }

        let alert = NSAlert()
        alert.messageText = "Enable paste-back"
        alert.informativeText = "To paste entries straight into the app you were using, Clipsu needs Accessibility permission. The entry is already on your clipboard, so you can also paste it manually with ⌘V.\n\nNote: rebuilding the app changes its signature, so macOS may ask you to grant this again — remove the old “Clipsu” entry and re-add it if paste-back stops working."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = PasteService().requestAccessibility()
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Clipsu"
        alert.informativeText = message
        alert.alertStyle = .critical
        alert.runModal()
        NSApp.terminate(nil)
    }
}
