import SwiftUI

struct ClipboardItemRow: View {
    let item: ClipboardItem
    let store: ClipboardStore
    let isSelected: Bool

    @State private var hovered = false

    private static let timeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Source app icon, top-left of the card.
            Image(nsImage: store.appIcon(bundleID: item.sourceAppBundleID))
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    typeDot
                }
                .help(item.sourceAppName ?? "Unknown")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.previewText)
                    .font(.system(size: 13))
                    .lineLimit(3)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)

                if item.kind == .image, let name = item.imageFileName,
                   let thumb = store.thumbnail(fileName: name, maxPixel: 300) {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: 80, alignment: .leading)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                HStack(spacing: 5) {
                    if let app = item.sourceAppName {
                        Text(app)
                    }
                    if let host = sourceHost {
                        Text("·")
                        Text(host)
                            .lineLimit(1)
                    }
                    Text("·")
                    Text(Self.timeFormatter.localizedString(for: item.createdAt, relativeTo: Date()))
                    if item.kind == .text, let text = item.text {
                        Text("·")
                        Text("\(text.count) 字符")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected
                      ? Color.accentColor.opacity(0.18)
                      : (hovered ? Color.primary.opacity(0.06) : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onHover { hovered = $0 }
    }

    /// Small kind badge sitting on the app icon's corner.
    private var typeDot: some View {
        let (symbol, color): (String, Color) = switch item.kind {
        case .text: ("text.alignleft", .teal)
        case .link: ("link", .blue)
        case .image: ("photo", .purple)
        case .file: ("doc.fill", .indigo)
        }
        return Image(systemName: symbol)
            .font(.system(size: 6, weight: .bold))
            .foregroundStyle(.white)
            .padding(2)
            .background(Circle().fill(color))
            .offset(x: 4, y: 4)
    }

    /// Shortened host/path of the page the content was copied from.
    private var sourceHost: String? {
        guard let raw = item.sourceURL,
              let url = URL(string: raw),
              let host = url.host()
        else { return nil }
        return host.replacingOccurrences(of: #"^www\."#, with: "", options: .regularExpression)
    }
}
