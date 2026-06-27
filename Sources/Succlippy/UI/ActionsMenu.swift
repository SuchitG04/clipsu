import SwiftUI
import SucclippyCore

/// The ⌘K actions overlay: a floating card listing contextual actions for the selection.
/// Keyboard navigation is driven by the panel's key monitor via `AppState`.
struct ActionsMenu: View {
    @ObservedObject var appState: AppState

    var body: some View {
        let actions = appState.currentActions
        ZStack(alignment: .bottomTrailing) {
            // Dim + click-to-dismiss backdrop.
            Color.black.opacity(0.12)
                .contentShape(Rectangle())
                .onTapGesture { appState.closeActions() }

            VStack(alignment: .leading, spacing: 2) {
                Text("Actions")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.tertiaryText)
                    .padding(.horizontal, 10)
                    .padding(.top, 8)
                    .padding(.bottom, 2)

                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    row(action, selected: index == appState.actionIndex)
                        .onTapGesture {
                            appState.actionIndex = index
                            appState.performSelectedAction()
                        }
                }
                .padding(.bottom, 6)
            }
            .frame(width: 260)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thickMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.hairline)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
            .padding(.trailing, 12)
            .padding(.bottom, 38)
        }
    }

    private func row(_ action: ClipAction, selected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: action.symbol)
                .frame(width: 16)
                .foregroundStyle(action.isDestructive ? Color.red : Theme.secondaryText)
            Text(action.title)
                .font(.system(size: 12))
                .foregroundStyle(action.isDestructive ? Color.red : .primary)
            Spacer()
            if !action.shortcutHint.isEmpty {
                Text(action.shortcutHint)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}
