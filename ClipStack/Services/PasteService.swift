import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

enum PasteService {
    /// Writes an item back to the system pasteboard.
    static func copy(_ item: ClipboardItem, store: ClipboardStore) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .image:
            if let name = item.imageFileName,
               let image = store.fullImage(fileName: name) {
                pasteboard.writeObjects([image])
            }
        case .file:
            let urls = (item.filePaths ?? []).map { NSURL(fileURLWithPath: $0) }
            if !urls.isEmpty {
                pasteboard.writeObjects(urls)
            }
        case .text, .link:
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    /// True when the app is trusted to post synthetic keyboard events.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestAccessibilityPermission() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Posts ⌘V so the frontmost app pastes whatever we just wrote
    /// to the pasteboard. Requires accessibility permission.
    static func simulatePaste() {
        guard isAccessibilityTrusted else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
