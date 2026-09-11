import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore

    @AppStorage(DefaultsKey.autoPaste) private var autoPaste = true
    @AppStorage(DefaultsKey.hotkeyPreset) private var hotkeyPreset = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var accessibilityTrusted = PasteService.isAccessibilityTrusted
    @State private var permissionTimer: Timer?

    var body: some View {
        Form {
            Section("通用") {
                Toggle("登录时启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        do {
                            if enabled {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }

                Picker("全局快捷键", selection: $hotkeyPreset) {
                    ForEach(Array(HotKeyManager.Preset.all.enumerated()), id: \.offset) { index, preset in
                        Text(preset.name).tag(index)
                    }
                }
                .onChange(of: hotkeyPreset) { index in
                    AppDelegate.shared.applyHotKeyPreset(index: index)
                }

                Picker("历史记录上限", selection: $store.maxHistory) {
                    Text("100 条").tag(100)
                    Text("250 条").tag(250)
                    Text("500 条").tag(500)
                    Text("1000 条").tag(1000)
                    Text("2000 条").tag(2000)
                }
            }

            Section("粘贴") {
                Toggle("选中后自动粘贴到当前应用", isOn: $autoPaste)

                HStack {
                    Label(
                        accessibilityTrusted ? "辅助功能权限已授予" : "需要辅助功能权限",
                        systemImage: accessibilityTrusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityTrusted ? .green : .orange)
                    .font(.system(size: 12))

                    Spacer()

                    if !accessibilityTrusted {
                        Button("去授权") {
                            PasteService.requestAccessibilityPermission()
                            PasteService.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("数据") {
                HStack {
                    Text("剪贴板历史存储在本地，绝不会上传。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("清空历史", role: .destructive) {
                        store.clear(keepPinned: false)
                    }
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
        .onAppear { startPermissionPolling() }
        .onDisappear { stopPermissionPolling() }
    }

    private func startPermissionPolling() {
        accessibilityTrusted = PasteService.isAccessibilityTrusted
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            let trusted = PasteService.isAccessibilityTrusted
            if trusted != self.accessibilityTrusted {
                self.accessibilityTrusted = trusted
            }
            if trusted {
                self.stopPermissionPolling()
            }
        }
    }

    private func stopPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = nil
    }
}
