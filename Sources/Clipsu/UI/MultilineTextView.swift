import SwiftUI
import AppKit

/// A multiline text editor backed by `NSTextView` with native undo (⌘Z) support —
/// SwiftUI's `TextEditor` doesn't enable `allowsUndo`.
struct MultilineTextView: NSViewRepresentable {
    @Binding var text: String
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = Self.makeScrollView()
        guard let textView = scroll.documentView as? CancellableTextView else { return scroll }

        textView.delegate = context.coordinator
        textView.allowsUndo = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.string = text
        textView.onCancel = onCancel

        scroll.drawsBackground = false
        scroll.backgroundColor = .clear

        DispatchQueue.main.async { textView.window?.makeFirstResponder(textView) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? CancellableTextView else { return }
        if textView.string != text { textView.string = text }
        textView.onCancel = onCancel
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let parent: MultilineTextView
        init(_ parent: MultilineTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

/// Routes the Escape key to a cancel callback instead of beeping.
final class CancellableTextView: NSTextView {
    var onCancel: () -> Void = {}

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}

private extension MultilineTextView {
    /// Builds an NSScrollView hosting our cancellable text view.
    static func makeScrollView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        let contentSize = scroll.contentSize
        let textView = CancellableTextView(frame: NSRect(origin: .zero, size: contentSize))
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: contentSize.width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        return scroll
    }
}
