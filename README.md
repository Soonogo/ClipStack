# ClipStack

一个现代化的 macOS 剪贴板管理器 —— SwiftUI 构建，常驻菜单栏，全局快捷键呼出。

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20(Apple%20Silicon)-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)

## 功能

- **剪贴板历史**：自动记录文本、链接、图片、文件，去重并持久化到本地磁盘
- **全局快捷键**：默认 `⌘⇧V` 呼出面板（可在设置中切换为 `⌥V` / `⌃⌥V` / `⌘⇧C`）
- **搜索与过滤**：按内容搜索，按类型（文本/链接/图片/文件）筛选
- **置顶**：常用条目置顶，不被自动清理
- **自动粘贴**：选中条目自动写入剪贴板并模拟 `⌘V` 粘贴到当前应用（需辅助功能权限）
- **键盘导航**：`↑`/`↓` 选择，`⏎` 粘贴，`⎋` 关闭/清空搜索
- **隐私保护**：自动忽略密码管理器等标记为 transient/concealed 的剪贴板内容；所有数据仅存本地
- **登录自启**：可选开机启动
- **右键菜单**：置顶、仅复制、访达中显示、打开链接、删除

## 内存安全设计

- 历史上限可配置（默认 500 条），超出自动淘汰最旧的未置顶条目并删除其图片文件
- 缩略图经 ImageIO 按目标尺寸解码（大截图只占几 KB 内存），并存入有容量上限的 `NSCache`
- 剪贴板轮询 `Timer` 使用 `[weak self]`，关闭即失效；Carbon 热键回调以 unretained 指针传入，无引用循环
- 保存任务可取消、防抖合并，退出时强制落盘

## 安装

从 [Releases](../../releases) 下载 `ClipStack-arm64.dmg`，拖入 `Applications`。

应用未经过 Apple 公证，首次打开请右键 → “打开”，或执行：

```bash
xattr -d com.apple.quarantine /Applications/ClipStack.app
```

如需“选中后自动粘贴”，请在 系统设置 → 隐私与安全性 → 辅助功能 中授权 ClipStack。

## 本地构建

```bash
brew install xcodegen
xcodegen
open ClipStack.xcodeproj   # 在 Xcode 中 ⌘R 运行
```

或命令行：

```bash
xcodebuild -project ClipStack.xcodeproj -scheme ClipStack \
  -configuration Release -derivedDataPath build \
  ARCHS=arm64 CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO build
```

## CI / 发布

`.github/workflows/release.yml` 在每次 push / PR 时构建 arm64 app 并上传 `ClipStack-arm64.dmg` 构建产物。

发布新版本：

```bash
git tag v1.0.0 && git push origin v1.0.0
```

tag 推送后 Action 自动创建 GitHub Release 并附加 DMG。

## 技术栈

SwiftUI · AppKit（NSPanel / NSStatusItem / NSPasteboard）· Carbon HotKey · ImageIO 缩略图 · SMAppService 登录项 · CGEvent 模拟粘贴 · XcodeGen
