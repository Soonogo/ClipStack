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
        HStack(spacing: 10) {
            icon
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    if let app = item.sourceAppName {
                        Text(app)
                            .lineLimit(1)
                    }
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

    @ViewBuilder
    private var icon: some View {
        switch item.kind {
        case .image:
            if let name = item.imageFileName,
               let thumb = store.thumbnail(fileName: name) {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                iconBadge("photo", color: .purple)
            }
        case .link:
            iconBadge("link", color: .blue)
        case .file:
            iconBadge("doc.fill", color: .indigo)
        case .text:
            iconBadge("text.alignleft", color: .teal)
        }
    }

    private func iconBadge(_ symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.15))
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
        }
    }
}
