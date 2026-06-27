import SwiftUI
import ClipsuCore

/// One row in the clipboard list: leading glyph/thumbnail, title, source + time, pin marker.
struct ItemRowView: View {
    let item: ClipboardItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                HStack(spacing: 5) {
                    if let app = item.sourceAppName {
                        Text(app).lineLimit(1)
                    }
                    Text("·")
                    Text(item.lastUsedAt.clipShort)
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .rotationEffect(.degrees(45))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowCorner, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var leading: some View {
        switch item.kind {
        case .image:
            CachedImage(path: item.thumbPath ?? item.imagePath)
        case .color:
            colorSwatch
        default:
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var colorSwatch: some View {
        if let hex = item.plainText, let color = Color(hex: hex) {
            color
        } else {
            Image(systemName: "paintpalette").foregroundStyle(Theme.secondaryText)
        }
    }
}

extension Color {
    /// Parses #RGB / #RRGGBB / #RRGGBBAA.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard let value = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 6:
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
            a = 1
        case 8:
            r = Double((value >> 24) & 0xFF) / 255
            g = Double((value >> 16) & 0xFF) / 255
            b = Double((value >> 8) & 0xFF) / 255
            a = Double(value & 0xFF) / 255
        default:
            return nil
        }
        self = Color(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
