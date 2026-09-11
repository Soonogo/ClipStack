import SwiftUI

struct PanelView: View {
    @ObservedObject var store: ClipboardStore

    @State private var search = ""
    @State private var kindFilter: ClipboardItemKind?
    @State private var selection: UUID?
    @State private var keyMonitor: Any?
    @State private var scrollProxy: ScrollViewProxy?
    @State private var axTrusted = PasteService.isAccessibilityTrusted
    @State private var axPollTimer: Timer?

    private var filtered: [ClipboardItem] {
        var base = kindFilter.map { kind in store.items.filter { $0.kind == kind } } ?? store.items
        base.sort { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.createdAt > b.createdAt
        }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { item in
            (item.text?.localizedCaseInsensitiveContains(query) ?? false)
                || (item.filePaths?.contains { $0.localizedCaseInsensitiveContains(query) } ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !axTrusted, UserDefaults.standard.bool(forKey: DefaultsKey.autoPaste) {
                permissionBanner
            }
            Divider().opacity(0.4)
            content
            Divider().opacity(0.4)
            footer
        }
        .background(.ultraThinMaterial)
        .onAppear {
            installKeyMonitor()
            startAXPolling()
        }
        .onDisappear(perform: removeKeyMonitor)
    }

    private var permissionBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("点击条目仅会复制——授权“辅助功能”后可自动粘贴")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Button("去授权") {
                PasteService.requestAccessibilityPermission()
                PasteService.openAccessibilitySettings()
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.08))
    }

    private func startAXPolling() {
        axPollTimer?.invalidate()
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            let trusted = PasteService.isAccessibilityTrusted
            if trusted {
                self.axTrusted = true
                self.axPollTimer?.invalidate()
                self.axPollTimer = nil
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索剪贴板历史…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .onChange(of: search) { _ in selection = nil }

            Menu {
                filterButton(nil, label: "全部", icon: "tray.full")
                Divider()
                filterButton(.text, label: "文本", icon: "doc.text")
                filterButton(.link, label: "链接", icon: "link")
                filterButton(.image, label: "图片", icon: "photo")
                filterButton(.file, label: "文件", icon: "folder")
            } label: {
                Image(systemName: kindFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(kindFilter == nil ? .secondary : Color.accentColor)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func filterButton(_ kind: ClipboardItemKind?, label: String, icon: String) -> some View {
        Button {
            kindFilter = kind
            selection = nil
        } label: {
            Label(label, systemImage: icon)
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(filtered) { item in
                        ClipboardItemRow(
                            item: item,
                            store: store,
                            isSelected: effectiveSelection == item.id
                        )
                        .id(item.id)
                        .onTapGesture {
                            paste(item)
                        }
                        .contextMenu { contextMenu(for: item) }
                    }
                }
                .padding(8)
            }
            .onAppear { scrollProxy = proxy }
            .overlay {
                if filtered.isEmpty {
                    emptyState
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clipboard")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(search.isEmpty ? "还没有剪贴板记录" : "没有匹配的结果")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var effectiveSelection: UUID? {
        if let selection, filtered.contains(where: { $0.id == selection }) {
            return selection
        }
        return filtered.first?.id
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Text("\(filtered.count) 项")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            Menu {
                Button("清空未置顶") { store.clear(keepPinned: true) }
                Button("全部清空", role: .destructive) { store.clear(keepPinned: false) }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("清空历史")

            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("设置")

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("退出 ClipStack")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func contextMenu(for item: ClipboardItem) -> some View {
        Button("粘贴") { paste(item) }
        Button("仅复制") { copyOnly(item) }
        Divider()
        Button(item.isPinned ? "取消置顶" : "置顶") { store.togglePin(item) }
        if item.kind == .file, let path = item.filePaths?.first {
            Button("在访达中显示") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            }
        }
        if item.kind == .link, let text = item.text, let url = URL(string: text) {
            Button("打开链接") { NSWorkspace.shared.open(url) }
        }
        Divider()
        Button("删除", role: .destructive) { store.delete(item) }
    }

    // MARK: - Actions

    private func paste(_ item: ClipboardItem) {
        AppDelegate.shared.paste(item)
    }

    private func copyOnly(_ item: ClipboardItem) {
        PasteService.copy(item, store: store)
    }

    // MARK: - Keyboard navigation

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === AppDelegate.shared.panel else { return event }
            return handleKey(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 126: // up
            moveSelection(offset: -1)
            return true
        case 125: // down
            moveSelection(offset: 1)
            return true
        case 36, 76: // return / enter
            guard let id = effectiveSelection,
                  let item = filtered.first(where: { $0.id == id })
            else { return true }
            paste(item)
            return true
        case 53: // escape
            if search.isEmpty {
                AppDelegate.shared.dismissPanel()
            } else {
                search = ""
            }
            return true
        default:
            return false
        }
    }

    private func moveSelection(offset: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let currentIndex = selection.flatMap { sel in list.firstIndex(where: { $0.id == sel }) } ?? (offset > 0 ? -1 : list.count)
        let next = max(0, min(list.count - 1, currentIndex + offset))
        selection = list[next].id
        scrollProxy?.scrollTo(list[next].id, anchor: .center)
    }
}
