import SwiftUI
import ClipsuCore

/// In-app Quick Look: shows the full image over a dimmed backdrop. Space/Esc/click dismisses.
struct ImageLightbox: View {
    @ObservedObject var appState: AppState
    let item: ClipboardItem

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { appState.closeQuickLook() }

            VStack(spacing: 10) {
                CachedImage(path: item.imagePath, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 24, y: 8)

                HStack(spacing: 8) {
                    if let w = item.imageWidth, let h = item.imageHeight {
                        Text("\(w) × \(h)")
                    }
                    Text("·")
                    Text(item.byteSize.clipBytes)
                    Text("·")
                    Text("Space or Esc to close")
                }
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.75))
            }
            .padding(28)
        }
    }
}
