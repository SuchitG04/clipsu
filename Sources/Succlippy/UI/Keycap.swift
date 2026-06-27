import SwiftUI

/// A small key-cap glyph, matching the footer hint style. `light` suits dark/accent backgrounds.
struct Keycap: View {
    let text: String
    var light: Bool = false

    init(_ text: String, light: Bool = false) {
        self.text = text
        self.light = light
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(light ? Color.white.opacity(0.25) : Color.primary.opacity(0.08))
            )
            .foregroundStyle(light ? Color.white : Theme.secondaryText)
    }
}
