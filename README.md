# Launchpad Classic

A standalone native Launchpad-style application launcher for Apple Silicon Macs running macOS 14 or later.

面向 Apple 芯片 Mac 的独立原生 Launchpad 风格应用启动器，适用于 macOS 14 及以上。

## Download and install / 下载与安装

1. Download the app ZIP from [Releases / 发布页面](https://github.com/shawnstyle/LaunchpadClassic/releases/latest).
   从发布页面下载应用 ZIP 压缩包。
2. Extract the ZIP, move `Launchpad Classic.app` into `/Applications` or `~/Applications`, and open it.
   解压后将应用放入“应用程序”或用户应用程序目录，再双击打开。
3. The installed app runs independently. Xcode, Python, a browser, and development tools are not needed at runtime.
   安装后的应用可以独立运行，运行时无需 Xcode、Python、浏览器或开发工具。

The current build is arm64 only, uses an ad-hoc signature, and is not notarized by Apple. Another Mac may require confirmation in System Settings → Privacy & Security on first launch.

当前构建仅支持 arm64，使用本地临时签名，尚未经过 Apple 公证；在其他 Mac 首次打开时，可能需要在“系统设置 → 隐私与安全性”中确认。

## Usage / 使用

| Action / 操作 | Instructions / 说明 |
| --- | --- |
| Show or hide / 显示或收起 | Double-click the app, click its Dock or menu-bar icon, or press **Control + Option + Space**.<br>双击应用、点击 Dock 或菜单栏图标，或按 **Control + Option + 空格**。 |
| Search / 搜索 | Search by Chinese or English name, pinyin, or initials.<br>支持中文名称、英文名称、拼音及首字母搜索。 |
| Launch / 启动 | Click an app icon, or select it with arrow keys and press Return.<br>点击图标，或使用方向键选择后按回车。 |
| Change page / 翻页 | Swipe horizontally on a trackpad, click page dots, use Page Up / Page Down, or press Command + Left / Right.<br>横向滑动触控板、点击页码圆点、使用 Page Up / Page Down，或按 Command + 左右方向键。 |
| Mouse paging / 鼠标翻页 | Drag horizontally from a blank area. Scroll down for the next page and up for the previous page; scroll direction follows system events.<br>从空白处按住鼠标左右拖动；滚轮向下进入下一页、向上返回上一页，方向遵循系统滚动事件。 |
| Reorder / 排列 | Drag an icon to move it. Ordinary dragging causes temporary jiggle that stops on release.<br>拖动图标调整位置；普通拖动只临时抖动，松手后停止。 |
| Persistent editing / 持续编辑 | Hold an icon still for about 0.55 seconds. Click a blank area or press Escape to end editing.<br>按住图标不动约 0.55 秒进入持续编辑，点击空白或按 Esc 退出。 |
| Create a folder / 新建文件夹 | Hold one app over another app's center, then release. The new folder opens and requests name editing after the expansion animation.<br>将应用停留在另一应用中心后松手；新文件夹展开，并在展开动画后请求编辑名称。 |
| Edit a folder / 编辑文件夹 | Click its title and press Return to save. Drag onto an existing folder to add an app; drag outside its panel to move an app out.<br>点击标题编辑名称并回车保存；拖入已有文件夹添加应用，拖到展开面板外移出应用。 |
| Move between pages / 跨页移动 | Use the icon context menu, hold near the screen edge, or hover over a page dot while dragging.<br>使用图标右键菜单、在屏幕边缘停留，或拖动时悬停在页码圆点上。 |
| Refresh / 刷新 | Press Command + R. The app also scans periodically; use the menu to add other app locations.<br>按 Command + R 刷新；应用也会定时扫描，可通过菜单添加其他应用位置。 |
| Return or close / 返回或关闭 | Escape cancels a drag first, then ends editing, closes a folder, clears search, or hides the launcher as applicable. A blank click ends editing before hiding.<br>Esc 优先取消拖动，然后依当前状态结束编辑、关闭文件夹、清空搜索或收起界面；编辑时点击空白先退出编辑。 |
| Login and quit / 登录启动与退出 | The menu-bar context menu provides login-at-startup and quit actions. Command + Q also quits.<br>菜单栏右键菜单提供登录启动及退出选项，也可按 Command + Q 退出。 |

The launcher scans standard application directories, including `/Applications`, `~/Applications`, and `/System/Applications`. Layouts and folders are stored locally in macOS preferences; the system application database is not modified.

启动器扫描上述标准应用目录。排列和文件夹保存在本机 macOS 偏好设置中，不修改系统应用数据库。

## Build, test, and package / 构建、检查与打包

Building requires Xcode or a configured Swift command-line development environment on an Apple Silicon Mac. If an Xcode license prompt appears, the computer owner must review and handle it with `sudo xcodebuild -license`.

构建需要 Apple 芯片 Mac，以及 Xcode 或已配置的 Swift 命令行开发环境；若提示 Xcode 协议未接受，需要由本人运行上述命令阅读并处理。

```bash
bash test.sh
bash build.sh
bash package-release.sh
```

The app is written to `build/Launchpad Classic.app`. Release ZIPs and SHA-256 checksums are written under `.build/releases/`. Packaging preserves executable permissions while omitting extended attributes, resource forks, and AppleDouble metadata.

应用输出到上述 `build` 路径；发布 ZIP 和 SHA-256 校验文件保存在 `.build/releases/`。打包保留可执行权限，不复制扩展属性、资源叉或 AppleDouble 元数据。

## Privacy / 隐私

The app has no account login, telemetry, or network upload. It reads app information and wallpaper locally and stores its preferences on the computer. See [Privacy / 隐私说明](PRIVACY.md).

应用不提供账号登录、遥测或网络上传，应用信息与壁纸均在本机读取，偏好设置保存在本机。完整说明见隐私文档。

The public bundle identifier is `org.launchpadclassic.app`. Earlier private builds used a different identifier; their saved layouts are not migrated automatically. Publishing the public build does not modify an existing local installation.

公开版采用通用应用标识。此前自用版本使用不同标识，其排列不会自动迁移；公开发布操作不更改已有本机安装。

## Visual references and limits / 视觉参考与限制

The classic layout uses seven columns and five rows. Proportions were calibrated against Apple's [macOS Sequoia Launchpad reference / 原版参考图](https://support.apple.com/en-ie/guide/mac-mini/aside/apd2d2a58738/2024/mac/15): a 1512 × 982 reference canvas, 96 pt icon canvas, 13 pt labels, and a 250 × 26 pt search field. These are replica calibration values, not published Apple implementation constants.

经典布局采用七列五行；基础比例依据苹果参考图校准。上述尺寸为复刻参数，不是苹果公开的内部实现常量。

Icons come from locally installed apps. Materials and fonts are rendered by the current macOS version. Pixel-perfect or frame-perfect parity with the original is not claimed. System pinch gestures, the dedicated Launchpad key, Dock drops, App Store installation progress, and system uninstall controls are outside the current scope.

图标来自本机已安装应用，材质和字体由当前 macOS 渲染；未宣称与原版逐像素或逐帧完全一致。系统捏合手势、专用 Launchpad 键、拖入 Dock、App Store 安装进度及系统卸载控件尚未接入。

## Version history / 版本记录

| Version / 版本 | Changes / 变化 |
| --- | --- |
| 1.1 | Classic grid, search proportions, and editable folders.<br>经典网格、搜索比例及可编辑文件夹。 |
| 1.1.1 | Hide immediately when launching an app; delayed callbacks cannot close a reopened session.<br>启动应用时立即收起，迟到回调不会关闭后来重新打开的界面。 |
| 1.1.2 | Reopening the launcher from its own icon toggles visibility.<br>再次点击启动器自身图标可切换显示与收起。 |
| 1.2 | Page, drag, folder, and presentation animations with cancellation and rollback.<br>分页、拖动、文件夹及显示动画，支持取消与回滚。 |
| 1.2.1 | Separate transient drag jiggle from persistent editing; open and request naming for new folders.<br>区分拖动临时抖动与持续编辑，新文件夹自动展开并请求命名。 |
| 1.2.2 | Mouse dragging and wheel paging, release prediction, damping, and input-conflict handling.<br>鼠标拖动与滚轮翻页、释放预测、边界阻尼及输入冲突处理。 |

## Documentation / 文档

- [Privacy / 隐私说明](PRIVACY.md)
- [Validation record / 验证记录](VALIDATION.md)
- [Interaction and animation status / 交互动画状态](MOTION_STATUS.md)
