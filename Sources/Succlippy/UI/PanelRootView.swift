import SwiftUI

/// Hosts `MainView` and owns the search-field focus, refocusing whenever the panel is re-shown.
struct PanelRootView: View {
    @ObservedObject var appState: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        MainView(appState: appState, searchFocus: $searchFocused)
            .frame(width: Theme.panelWidth, height: Theme.panelHeight)
            .onAppear { focusSoon() }
            .onChange(of: appState.focusNonce) { _, _ in focusSoon() }
    }

    private func focusSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { searchFocused = true }
    }
}
