import SwiftUI
import AppKit
import SucclippyCore

/// The right-hand pane: full content render + metadata for the selected item.
struct PreviewPane: View {
    let item: ClipboardItem?

    var body: some View {
        if let item {
            VStack(spacing: 0) {
                content(for: item)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                Divider().background(Theme.hairline)
                metadata(for: item)
            }
        } else {
            VStack {
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.tertiaryText)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func content(for item: ClipboardItem) -> some View {
        switch item.kind {
        case .image:
            ZStack {
                Color.black.opacity(0.04)
                CachedImage(path: item.imagePath, contentMode: .fit)
                    .padding(16)
            }
        case .file:
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.fileURLs ?? [], id: \.self) { path in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                                .resizable().frame(width: 18, height: 18)
                            Text((path as NSString).lastPathComponent).font(.system(size: 13))
                            Spacer()
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .color:
            VStack(spacing: 12) {
                if let hex = item.plainText, let color = Color(hex: hex) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(color)
                        .frame(height: 120)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                }
                Text(item.plainText ?? "").font(.system(.body, design: .monospaced))
            }
            .padding(16)
        case .richText:
            ScrollView {
                Text(attributed(item))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .text, .link:
            ScrollView {
                Text(item.plainText ?? "")
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func attributed(_ item: ClipboardItem) -> AttributedString {
        if let data = item.richData,
           let ns = NSAttributedString(rtf: data, documentAttributes: nil),
           let attr = try? AttributedString(ns, including: \.appKit) {
            return attr
        }
        return AttributedString(item.plainText ?? "")
    }

    // MARK: - Metadata

    private func metadata(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metaRow("Type", item.kind.displayName)
            if let app = item.sourceAppName { metaRow("Source", app) }
            metaRow("Copied", item.lastUsedAt.clipLong)
            metaRow("Size", item.byteSize.clipBytes)
            if let w = item.imageWidth, let h = item.imageHeight {
                metaRow("Dimensions", "\(w) × \(h)")
            }
            if item.copyCount > 1 { metaRow("Used", "\(item.copyCount) times") }
            if let ocr = item.ocrText, !ocr.isEmpty {
                metaRow("Recognized", String(ocr.prefix(140)))
            }
        }
        .font(.system(size: 11))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.tertiaryText)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }
}
