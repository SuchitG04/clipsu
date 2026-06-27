import SwiftUI

/// Bottom hint bar (Raycast-style): item count / toast, an optional vim mode indicator,
/// and the relevant shortcut hints (which adapt to vim mode).
struct FooterBar: View {
    let itemCount: Int
    let toast: String?
    var vimEnabled: Bool = false
    var mode: InputMode = .search
    var pending: Character?
    var onActions: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if vimEnabled { modePill }

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

            hints
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
    }

    // MARK: Mode indicator

    private var modePill: some View {
        let isNormal = mode == .normal
        let label = isNormal ? "NORMAL" : "SEARCH"
        return HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(isNormal ? Color.accentColor.opacity(0.9) : Color.orange.opacity(0.85)))
                .foregroundStyle(.white)
            if let pending {
                Text(String(pending))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Hints

    @ViewBuilder
    private var hints: some View {
        if vimEnabled {
            if mode == .normal {
                hint("Move", "j k")
                divider
                hint("Search", "/")
                divider
                Button(action: onActions) { hint("Actions", "l") }.buttonStyle(.plain)
            } else {
                hint("Normal", "esc")
            }
        } else {
            hint("Paste", "↵")
            divider
            hint("Copy", "⌘C")
            divider
            Button(action: onActions) { hint("Actions", "⌘K") }.buttonStyle(.plain)
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.hairline).frame(width: 1, height: 12)
    }

    private func hint(_ label: String, _ key: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                .foregroundStyle(Theme.secondaryText)
        }
    }
}
