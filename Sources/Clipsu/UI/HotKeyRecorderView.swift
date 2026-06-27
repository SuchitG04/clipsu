import SwiftUI
import AppKit

/// A click-to-record control for capturing a global shortcut.
struct HotKeyRecorderView: NSViewRepresentable {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    var onChange: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(keyCode: $keyCode, modifiers: $modifiers, onChange: onChange)
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.coordinator = context.coordinator
        button.refreshTitle()
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        nsView.coordinator = context.coordinator
        if !nsView.isRecording { nsView.refreshTitle() }
    }

    final class Coordinator {
        private let keyCodeBinding: Binding<Int>
        private let modifiersBinding: Binding<Int>
        private let onChange: () -> Void

        init(keyCode: Binding<Int>, modifiers: Binding<Int>, onChange: @escaping () -> Void) {
            self.keyCodeBinding = keyCode
            self.modifiersBinding = modifiers
            self.onChange = onChange
        }

        var keyCode: Int { keyCodeBinding.wrappedValue }
        var modifiers: Int { modifiersBinding.wrappedValue }
        func setKeyCode(_ value: Int) { keyCodeBinding.wrappedValue = value }
        func setModifiers(_ value: Int) { modifiersBinding.wrappedValue = value }
        func commit() { onChange() }
    }
}

/// NSButton that records the next keystroke (with modifiers) when armed.
final class RecorderButton: NSButton {
    weak var coordinator: HotKeyRecorderView.Coordinator?
    private(set) var isRecording = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }

    func refreshTitle() {
        guard let c = coordinator else { return }
        title = KeyDisplay.string(keyCode: c.keyCode, modifiers: c.modifiers)
    }

    @objc private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        isRecording = true
        title = "Type shortcut…"
        window?.makeFirstResponder(self)
    }

    private func stopRecording() {
        isRecording = false
        refreshTitle()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { super.keyDown(with: event); return }
        // Require at least one modifier so the shortcut is global-safe.
        let mods = Int(event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        let onlyTracked = mods & ((1<<17)|(1<<18)|(1<<19)|(1<<20))
        if onlyTracked == 0 {
            NSSound.beep()
            return
        }
        coordinator?.setKeyCode(Int(event.keyCode))
        coordinator?.setModifiers(onlyTracked)
        coordinator?.commit()
        stopRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stopRecording() }
        return super.resignFirstResponder()
    }
}
