# v1.2.2 interaction and animation status / v1.2.2 交互动画状态

The reference is the classic macOS Sequoia Launchpad. Layout proportions follow Apple's public reference; animation curves and durations are replica calibration values and have not been aligned frame by frame against an original recording on the same device.

参考目标为 macOS Sequoia 经典 Launchpad。布局比例依据苹果公开参考图；动画时长与曲线为复刻校准参数，尚未与同设备原版录屏逐帧对齐。

| Interaction / 交互 | Behavior / 实现 | Validation / 验证 |
| --- | --- | --- |
| Show and hide / 显示与收起 | Wallpaper blur, fading, grid scaling, and interruptible reversal.<br>壁纸模糊、淡入淡出、网格缩放及可中断反向。 | Builds and runs; original frame comparison pending.<br>已编译运行，原版逐帧比对待完成。 |
| App activation / 启动应用 | Press feedback, target-oriented fade/scale, and recovery on launch failure.<br>按压反馈、朝目标缩放淡出，启动失败时恢复。 | Launch behavior checks passed.<br>启动行为检查通过。 |
| Page dots and keys / 页码与键盘 | Full-page horizontal translation with shared snapping curves.<br>整页横向平移，使用统一吸附曲线。 | Keyboard paging and final states observed.<br>键盘翻页和终态已实测。 |
| Trackpad / 触控板 | Continuous displacement, velocity prediction, short-drag rebound, edge damping, and cancellation.<br>连续跟随、速度预测、短距离回弹、首尾阻尼及取消。 | NSEvent phase/state checks passed; physical trajectories not fully tested.<br>事件阶段与状态检查通过，真实轨迹未完整实测。 |
| Mouse drag paging / 鼠标拖动翻页 | Drag blank space horizontally, then snap or rebound on release.<br>从空白处横向拖动，松手吸附或回弹。 | Left/right round trips observed in v1.2.2.<br>v1.2.2 左右往返已实测。 |
| Mouse wheel / 鼠标滚轮 | One-step paging with same-direction throttling and page animation.<br>单格翻页、同向节流及页间滑动动画。 | Up/down round trips observed in v1.2.2.<br>v1.2.2 上下往返已实测。 |
| Icon pickup / 提起图标 | Press feedback, enlarged floating icon, shadow, and faded source position.<br>按压反馈、浮动图标放大与阴影，原位置变淡。 | Fast native dragging observed.<br>快速原生拖动已实测。 |
| Reordering / 拖拽排序 | Side-hover preview, spring movement, snapping, and save after completion.<br>侧边悬停让位、弹簧移动、落下吸附，完成后保存。 | Reordering, saving, and restoration observed.<br>换位、保存及还原已实测。 |
| New folders / 新建文件夹 | Center-hover preview, miniature-icon landing, expansion, then a naming request.<br>中心悬停预览、缩入小图标、展开后请求命名。 | State/timing/data checks passed; complete hover trajectory and text selection pending.<br>状态、延时和数据检查通过，完整悬停轨迹与文字选区待实测。 |
| Drag into folder / 拖进文件夹 | Hover to open; preview and settle inside the folder.<br>悬停后展开，在内部预览让位与落位。 | Hover and cancellation state checks passed.<br>悬停及取消状态检查通过。 |
| Drag out of folder / 拖出文件夹 | Outside-panel dwell collapses the folder while the floating icon continues tracking.<br>面板外停留后收拢，浮动图标继续跟随。 | Implemented; full UI trajectory not tested.<br>已实现，完整界面轨迹未实测。 |
| Cross-page icon drag / 跨页拖动 | Edge dwell or page-dot hover switches pages while retaining the pointer and ghost.<br>边缘停留或悬停页码翻页，保留指针及浮动图标。 | Timer, paging, and rollback checks passed.<br>计时器、分页及回滚检查通过。 |
| Drag cancellation / 取消拖动 | Escape or outside-window release restores layout and clears timers.<br>Esc 或窗口外释放恢复布局并清理计时器。 | Rollback, fast release, and interrupted settling checks passed.<br>回滚、快速释放及落位中断检查通过。 |
| Persistent editing / 持续编辑 | A stationary hold latches jiggle; blank click or Escape exits. Ordinary drag jiggle stops on release.<br>静止长按保持抖动，空白或 Esc 退出；普通拖动松手即停止。 | Observed in v1.2.1.<br>v1.2.1 已实测。 |
| Folder open/close / 文件夹展开与关闭 | Expand from the source icon, blur the root grid, and reverse on close.<br>从来源图标展开，主网格模糊，关闭时逆向收拢。 | Implemented; original-frame comparison incomplete.<br>已实现，原版逐帧比对未完成。 |
| Folder paging / 文件夹翻页 | Horizontal tracking and snapping inside the expanded panel.<br>展开面板内横向跟随与吸附。 | State checks passed; full UI regression above 21 apps pending.<br>状态检查通过，超过 21 个应用的完整界面回归待完成。 |
| Search / 搜索 | Result fading, rearrangement, and cleanup of previous gestures.<br>结果淡入淡出、重新排列并清理旧手势。 | Pinyin search observed.<br>拼音搜索已实测。 |
| Menus and text / 菜单与文字编辑 | Native menus, name editing, and error prompts; menus own Escape while open.<br>原生菜单、名称编辑和错误提示；菜单展开时优先处理 Esc。 | Native interaction retained; appearance varies by macOS version.<br>保留原生交互，外观随 macOS 版本变化。 |
| Reduce Motion / 减少动态效果 | Disable continuous displacement, scaling, and jiggle; use simplified transitions.<br>关闭连续位移、缩放和抖动，使用简化过渡。 | Implemented without changing system preferences.<br>已实现，未修改系统设置。 |

## Implementation locations / 实现位置

- `Sources/InteractionPhysics.swift`: timings, hover thresholds, damping, and velocity prediction.<br>时长、悬停阈值、阻尼及速度预测。
- `Sources/LauncherInteraction.swift`: state transitions, cancellation, and persistence boundaries.<br>状态转换、取消及保存边界。
- `Sources/NativeInteraction.swift`: native mouse, hold, and gesture tracking.<br>原生鼠标、长按及手势跟踪。
- `Sources/LauncherView.swift`: page, folder, floating-icon, and search-result rendering.<br>分页、文件夹、浮动图标及搜索结果渲染。

## Scope and references / 范围与参考

System pinch gestures, Dock drops, App Store installation progress, and system uninstall controls are not implemented. Existing pages can be traversed while dragging; creation of empty pages and the full original cross-page empty-slot rules are not implemented.

系统捏合、拖入 Dock、App Store 安装进度及系统卸载控件尚未接入。拖动可切换现有页面，尚未实现新建空白页及完整原版跨页空槽规则。

A claim of complete animation parity would require recordings of the original at the same version and resolution, covering pickup, hover, drop, cancellation, rapid reversal, boundaries, and folder operations, followed by curve and frame alignment.

若要宣称全部动画完全一致，还需同版本、同分辨率的原版录屏，覆盖提起、悬停、落下、取消、快速反向、边界和文件夹操作，并完成曲线与帧序对齐。

- [Apple Launchpad reference / 苹果 Launchpad 参考图](https://support.apple.com/en-ie/guide/mac-mini/aside/apd2d2a58738/2024/mac/15)
- [Apple gesture-recognizer guidance / 苹果手势识别说明](https://developer.apple.com/documentation/technotes/tn3212-adopting-gesture-recognizers-for-sidecar-touch-support)
