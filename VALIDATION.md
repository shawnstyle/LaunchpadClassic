# v1.2.2 validation record / v1.2.2 验证记录

Target: Apple Silicon, macOS 14 or later.

目标平台：Apple Silicon，macOS 14 及以上。

## Automated checks / 自动检查

| Category / 类别 | Count / 数量 | Coverage / 范围 |
| --- | --- | --- |
| Core / 核心 | 30 | Search, aliases, grid geometry, deduplication, folders, and persistence.<br>搜索、多语言别名、分页几何、布局去重、文件夹及持久化。 |
| Launch behavior / 启动行为 | 11 | Hide before launch, late callbacks, failure handling, and folder activation.<br>先收起再启动、迟到回调、失败提示及文件夹激活。 |
| Interaction states / 交互状态 | 79 | Trackpad phases, mouse paging, wheel input, damping, cancellation, editing, folder naming requests, sorting, and edge paging.<br>触控板阶段、鼠标翻页、滚轮输入、阻尼、取消、编辑、文件夹命名请求、排序及边缘翻页。 |
| Total / 合计 | **120** | All application checks passed for v1.2.2.<br>v1.2.2 应用检查全部通过。 |

The arm64 build, code signature, and Info.plist checks passed. Documentation-only updates are checked separately for filenames, links, and bilingual coverage.

arm64 构建、应用签名与 Info.plist 检查通过。仅文档更新另行检查文件名、链接和双语覆盖情况。

## UI observations / 界面检查

- Blank-area mouse dragging and wheel scrolling page in both directions.
  空白处鼠标拖动及滚轮滚动可往返翻页。
- Holding an icon still enters persistent editing; clicking blank space ends editing while keeping the launcher open.
  静止长按进入持续编辑，点击空白退出编辑并保留界面。
- Releasing an ordinary icon drag ends temporary jiggle; reordering and saving work.
  普通图标拖动释放后停止临时抖动，换位与保存可用。
- Pinyin search, keyboard paging, folder opening, and blank-click closing work.
  拼音搜索、键盘翻页、文件夹打开和空白点击关闭可用。
- Horizontal dragging in a single-page folder does not accidentally close it.
  单页文件夹横向拖动不会误关闭。

## Validation limits / 验证范围

New-folder expansion and name-focus requests passed state checks. A complete prolonged-hover trajectory and the automatic text selection have not completed UI automation validation. Not every third-party mouse driver, continuous physical trackpad gesture, or original animation has been tested frame by frame.

新文件夹展开及命名焦点请求通过状态检查；完整长悬停轨迹与自动文字选区尚未完成 UI 自动化验证。未对每种第三方鼠标驱动、真实触控板连续轨迹或原版动画逐帧完成测试。

## Release checks / 发布检查

Public source files were checked for local absolute paths, personal emails, credentials, app inventories, preferences, and desktop screenshots. The release archive omits macOS extended attributes, resource forks, and AppleDouble files. See [Privacy / 隐私说明](PRIVACY.md).

公开源文件已检查本机绝对路径、个人邮箱、凭据、应用清单、偏好设置和桌面截图。发布包不携带 macOS 扩展属性、资源叉或 AppleDouble 文件。数据行为详见隐私文档。
