import AppKit

/// Polls the general pasteboard for changes. macOS provides no change notification,
/// so we watch `changeCount` on a lightweight timer (~0.4s) — negligible CPU.
final class ClipboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private let pasteboard: NSPasteboard
    private let interval: TimeInterval

    /// Called on the main thread whenever new pasteboard content appears.
    /// The flag is true when the change was caused by Succlippy itself pasting back,
    /// so the capturer can avoid re-recording its own write if desired.
    var onChange: ((NSPasteboard) -> Void)?

    init(pasteboard: NSPasteboard = .general, interval: TimeInterval = 0.4) {
        self.pasteboard = pasteboard
        self.interval = interval
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            self?.tick()
        }
        // Common modes so polling continues during menu tracking / dragging.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Call after Succlippy writes to the pasteboard, so the resulting change isn't treated as new.
    func acknowledgeOwnChange() {
        lastChangeCount = pasteboard.changeCount
    }

    private func tick() {
        let current = pasteboard.changeCount
        guard current != lastChangeCount else { return }
        lastChangeCount = current
        onChange?(pasteboard)
    }
}
