import SwiftUI
import SucclippyCore

/// The left-hand scrollable list of clipboard entries.
struct ItemListView: View {
    let items: [ClipboardItem]
    @Binding var selectedID: Int64?
    var isFiltered: Bool = false
    var onActivate: (ClipboardItem) -> Void
    var onSecondary: (ClipboardItem) -> Void

    var body: some View {
        if items.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ItemRowView(item: item, isSelected: item.id == selectedID)
                                .id(item.id)
                                .onTapGesture { selectedID = item.id }
                                .simultaneousGesture(TapGesture(count: 2).onEnded { onActivate(item) })
                                .contextMenu { rowMenu(item) }
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .onChange(of: selectedID) { _, newValue in
                    guard let id = newValue else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    @ViewBuilder
    private func rowMenu(_ item: ClipboardItem) -> some View {
        Button("Paste") { onActivate(item) }
        Button("Actions…") { selectedID = item.id; onSecondary(item) }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: isFiltered ? "magnifyingglass" : "doc.on.clipboard")
                .font(.system(size: 30))
                .foregroundStyle(Theme.tertiaryText)
            Text(isFiltered ? "No matching items" : "No clipboard history yet")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            Text(isFiltered ? "Try a different filter or search." : "Copy something and it'll show up here.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
