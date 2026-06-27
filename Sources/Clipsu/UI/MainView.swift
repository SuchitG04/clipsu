import SwiftUI
import ClipsuCore

/// The root content of the floating panel: search, filters, two-pane list/preview, footer.
struct MainView: View {
    @ObservedObject var appState: AppState
    var searchFocus: FocusState<Bool>.Binding

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                SearchBar(text: $appState.query, focus: searchFocus)
                Divider().background(Theme.hairline)

                FilterChips(selection: $appState.filter)
                Divider().background(Theme.hairline)

                HStack(spacing: 0) {
                    ItemListView(
                        items: appState.items,
                        selectedID: $appState.selectedID,
                        isFiltered: appState.filter != .all || !appState.query.isEmpty,
                        onActivate: { appState.activate($0) },
                        onSecondary: { _ in appState.toggleActions() }
                    )
                    .frame(width: Theme.listWidth)

                    Divider().background(Theme.hairline)

                    PreviewPane(item: appState.selectedItem)
                        .frame(maxWidth: .infinity)
                }

                Divider().background(Theme.hairline)
                FooterBar(
                    itemCount: appState.items.count,
                    toast: appState.toast,
                    onActions: { appState.toggleActions() }
                )
            }

            if appState.showingActions {
                ActionsMenu(appState: appState)
                    .transition(.opacity)
            }

            if let item = appState.quickLookItem {
                ImageLightbox(appState: appState, item: item)
                    .transition(.opacity)
            }

            if appState.editingItem != nil {
                EditOverlay(appState: appState)
                    .transition(.opacity)
            }
        }
        .background(VisualEffectView(material: .popover, blending: .behindWindow))
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.12), value: appState.showingActions)
        .animation(.easeOut(duration: 0.12), value: appState.quickLookItem)
        .animation(.easeOut(duration: 0.12), value: appState.editingItem)
        .animation(.default, value: appState.toast)
    }
}
