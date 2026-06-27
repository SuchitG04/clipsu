import SwiftUI
import SucclippyCore

/// Full-panel, in-app editor. Saving creates a new history entry (originals are preserved).
struct EditOverlay: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "pencil").foregroundStyle(Theme.secondaryText)
                Text("Edit Entry").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("Saves as a new entry")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            Divider().background(Theme.hairline)

            MultilineTextView(text: $appState.editingText, onCancel: { appState.cancelEdit() })
                .padding(6)

            Divider().background(Theme.hairline)

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                    Text("Undo")
                    Keycap("⌘Z")
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)

                Spacer()

                Button { appState.cancelEdit() } label: {
                    HStack(spacing: 5) { Text("Cancel"); Keycap("esc") }
                }
                .keyboardShortcut(.cancelAction)

                Button { appState.commitEdit() } label: {
                    HStack(spacing: 5) { Text("Save as New"); Keycap("⌘↵", light: true) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(appState.editingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
        }
        .background(VisualEffectView(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
    }
}
