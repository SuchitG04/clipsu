import SwiftUI

/// Bottom hint bar (Raycast-style) showing the primary shortcuts and any transient toast.
struct FooterBar: View {
    let itemCount: Int
    let toast: String?
    var onActions: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let toast {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(toast)
                }
                .font(.system(size: 11, weight: .medium))
                .transition(.opacity)
            } else {
                Text("\(itemCount) item\(itemCount == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }

            Spacer()

            hint("Paste", "return")
            divider
            hint("Copy", "C", mods: "⌘")
            divider
            Button(action: onActions) {
                hint("Actions", "K", mods: "⌘")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 12)
    }

    private func hint(_ label: String, _ key: String, mods: String = "") -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Text(mods + keyGlyph(key))
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func keyGlyph(_ key: String) -> String {
        switch key {
        case "return": return "↵"
        default: return key
        }
    }
}
