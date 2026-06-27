import SwiftUI

/// Hosts `MainView` and owns the search-field focus.
///
/// In normal (non-vim) mode the search field always holds focus. In vim mode it's focused
/// only in Search mode. Focus is driven by `inputMode`; during the open transition we enforce
/// the intended focus (AppKit tries to restore the field as first responder on re-show, which
/// would otherwise flip us into Search mode). Once settled, clicking the field enters Search.
struct PanelRootView: View {
    @ObservedObject var appState: AppState
    @FocusState private var searchFocused: Bool
    @State private var settling = false

    var body: some View {
        MainView(appState: appState, searchFocus: $searchFocused)
            .frame(width: Theme.panelWidth, height: Theme.panelHeight)
            .onAppear { onPresent() }
            .onChange(of: appState.focusNonce) { _, _ in onPresent() }
            .onChange(of: appState.inputMode) { _, _ in applyFocus() }
            .onChange(of: searchFocused) { _, focused in handleFocusChange(focused) }
    }

    private func applyFocus() {
        searchFocused = appState.shouldFocusSearch
    }

    /// Called each time the panel is shown. Enforces the intended focus through the transition.
    private func onPresent() {
        settling = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { applyFocus() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            applyFocus()
            settling = false
        }
    }

    private func handleFocusChange(_ focused: Bool) {
        guard appState.vimEnabled else { return }
        if settling {
            // Ignore AppKit's responder restoration; keep the focus the mode dictates.
            if focused != appState.shouldFocusSearch {
                DispatchQueue.main.async { searchFocused = appState.shouldFocusSearch }
            }
            return
        }
        // After settling, honour user-driven focus changes (e.g. clicking the search field).
        if focused, appState.inputMode == .normal { appState.enterSearch() }
        if !focused, appState.inputMode == .search { appState.enterNormal() }
    }
}
