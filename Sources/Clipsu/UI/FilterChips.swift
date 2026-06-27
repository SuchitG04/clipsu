import SwiftUI
import ClipsuCore

/// Horizontal category filter chips shown above the list.
struct FilterChips: View {
    @Binding var selection: ClipFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ClipFilter.allCases, id: \.self) { filter in
                    chip(filter)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func chip(_ filter: ClipFilter) -> some View {
        let isOn = selection == filter
        return Button {
            selection = filter
        } label: {
            HStack(spacing: 4) {
                Image(systemName: filter.symbolName).font(.system(size: 10))
                Text(filter.title).font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(isOn ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.06))
            )
            .foregroundStyle(isOn ? Color.white : Theme.secondaryText)
        }
        .buttonStyle(.plain)
    }
}
