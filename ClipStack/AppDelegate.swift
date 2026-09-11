import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate!

    let store = ClipboardStore()

    private var statusItem: NSStatusItem!
    private(set) var panel: NSPanel!
    private var monitor: ClipboardMonitor!
    private var didPromptAccessibility = false
    /// The app that was frontmost before our panel took focus —
    /// the ⌘V keystroke must be delivered back to it.
    private var previousApp: NSRunningApplication?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        UserDefaults.standard.register(defaults: [DefaultsKey.autoPaste: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "clipboard",
            accessibilityDescription: "ClipStack"
        )
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.target = self

        monitor = ClipboardMonitor(imagesDirectory: store.imagesDirectory)
        monitor.onItem = { [weak store] item in
            store?.add(item)
        }
        monitor.start()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 600),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "ClipStack"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: PanelView(store: store)
        )
        self.panel = panel

        HotKeyManager.shared.onHotKey = { [weak self] in
            self?.togglePanel()
        }
        HotKeyManager.shared.register(preset: currentHotKeyPreset())
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.saveNow()
        HotKeyManager.shared.unregister()
        monitor.stop()
    }

    // MARK: - Panel

    @objc private func statusItemClicked() {
        togglePanel()
    }

    func togglePanel() {
        if panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    func showPanel() {
        guard let screen = screenUnderMouse() ?? NSScreen.main else { return }
        // Remember where ⌘V should go before we steal activation.
        previousApp = NSWorkspace.shared.frontmostApplication
        let size = panel.frame.size
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.maxY - size.height - 12
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    /// Give keyboard focus back to the app that was active before the
    /// panel appeared — without this, a synthetic ⌘V goes to ClipStack
    /// (a menu-bar app) and lands nowhere.
    private func restorePreviousAppFocus() {
        guard let app = previousApp, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        app.activate()
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    /// Dismiss without pasting (clicking away / Esc): still hand focus
    /// back so the user isn't left inside an app-less session.
    func dismissPanel() {
        hidePanel()
        restorePreviousAppFocus()
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) }
    }

    // MARK: - Paste

    func paste(_ item: ClipboardItem) {
        PasteService.copy(item, store: store)
        monitor.swallowPendingChange()
        store.moveToTop(item)
        hidePanel()
        restorePreviousAppFocus()

        guard UserDefaults.standard.bool(forKey: DefaultsKey.autoPaste) else { return }

        if PasteService.isAccessibilityTrusted {
            // Wait for the other app to become active, then post ⌘V.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                PasteService.simulatePaste()
            }
        } else if !didPromptAccessibility {
            didPromptAccessibility = true
            let alert = NSAlert()
            alert.messageText = "辅助功能权限"
            alert.informativeText = "ClipStack 需要“辅助功能”权限才能自动粘贴到当前应用。可以在设置中随时关闭自动粘贴。"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
            if alert.runModal() == .alertFirstButtonReturn {
                PasteService.requestAccessibilityPermission()
                PasteService.openAccessibilitySettings()
            }
        }
    }

    // MARK: - Hotkey

    func currentHotKeyPreset() -> HotKeyManager.Preset {
        let index = UserDefaults.standard.integer(forKey: DefaultsKey.hotkeyPreset)
        let presets = HotKeyManager.Preset.all
        return presets.indices.contains(index) ? presets[index] : presets[0]
    }

    func applyHotKeyPreset(index: Int) {
        let presets = HotKeyManager.Preset.all
        guard presets.indices.contains(index) else { return }
        UserDefaults.standard.set(index, forKey: DefaultsKey.hotkeyPreset)
        HotKeyManager.shared.register(preset: presets[index])
    }

    // MARK: - NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        guard let window = notification.object as? NSPanel, window === panel else { return }
        hidePanel()
        previousApp = nil
    }
}

enum DefaultsKey {
    static let autoPaste = "autoPaste"
    static let hotkeyPreset = "hotkeyPreset"
    static let launchAtLogin = "launchAtLogin"
}
