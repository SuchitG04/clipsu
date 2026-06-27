import SwiftUI

/// The top search field. Visual only — special keys are handled by the panel's key monitor.
struct SearchBar: View {
    @Binding var text: String
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.secondaryText)

            TextField("Search clipboard…", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused(focus)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}
