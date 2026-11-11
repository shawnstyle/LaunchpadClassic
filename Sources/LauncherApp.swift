import AppKit
import SwiftUI
import Carbon
import ServiceManagement

final class LauncherWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = LauncherModel()
    private var window: LauncherWindow?
    private var statusItem: NSStatusItem?
    private var keyboardMonitor: Any?
    private var scrollMonitor: Any?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var menuObservers: [NSObjectProtocol] = []
    private var scanTimer: Timer?
    private var pendingHide: DispatchWorkItem?
    private var presentationRequest = UUID()

    func applicationDidFinishLaunching(_ notification: Notification) {
        createMenu()
        model.dismiss = { [weak self] in self?.hide() }
        model.presentLaunchError = { [weak self] message in
            guard let self else { return }
            self.show()
            self.model.error = message
        }
        registerShortcut()
        for (name, delta) in [(NSMenu.didBeginTrackingNotification, 1), (NSMenu.didEndTrackingNotification, -1)] {
            menuObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.model.menuTrackingDepth = max(0, self.model.menuTrackingDepth + delta)
                }
            })
        }
        updateLoginStatus()
        model.refresh()
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in DispatchQueue.main.async { self?.model.refresh() } })
        }
        // Keep the current page and folder when another app temporarily takes focus.
        // App launch, Escape, the background, Dock and the shortcut still dismiss it.
        scanTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in DispatchQueue.main.async { self?.model.refresh() } }
        if !CommandLine.arguments.contains("--background") && !wasLaunchedAtLogin { show() }
    }

    private var wasLaunchedAtLogin: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    private func createMenu() {
        let menu = NSMenu()
        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "显示 Launchpad", action: #selector(show), keyEquivalent: "l").target = self
        appMenu.addItem(withTitle: "刷新应用列表", action: #selector(refresh), keyEquivalent: "r").target = self
        appMenu.addItem(withTitle: "添加其他位置的应用…", action: #selector(chooseApps), keyEquivalent: "").target = self
        appMenu.addItem(withTitle: "恢复默认排列…", action: #selector(resetLayout), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Launchpad Classic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        // Standard Edit menu keeps copy/paste and IME editing working inside search.
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", "undo:", "z"), ("剪切", "cut:", "x"), ("拷贝", "copy:", "c"), ("粘贴", "paste:", "v"), ("全选", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = edit; menu.addItem(editItem); NSApp.mainMenu = menu

        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "Launchpad Classic")
        status.button?.target = self
        status.button?.action = #selector(statusClicked)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "Launchpad Classic（⌃⌥空格）\n右键打开菜单"
        statusItem = status
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "显示 Launchpad", action: #selector(show), keyEquivalent: "").target = self
            menu.addItem(withTitle: "刷新应用", action: #selector(refresh), keyEquivalent: "").target = self
            menu.addItem(withTitle: "添加其他位置的应用…", action: #selector(chooseApps), keyEquivalent: "").target = self
            menu.addItem(withTitle: "恢复默认排列…", action: #selector(resetLayout), keyEquivalent: "").target = self
            menu.addItem(withTitle: "登录时启动", action: #selector(toggleLoginItem), keyEquivalent: "").target = self
            menu.items.last?.state = model.launchAtLogin ? .on : .off
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            if let button = statusItem?.button { menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button) }
        } else { toggle() }
    }

    @objc func refresh() { model.refresh() }
    @objc func chooseApps() { show(); model.chooseApps() }
    @objc func resetLayout() { show(); model.sortApps() }
    private func changePage(_ direction: Int) { model.navigate(to: model.currentPage + direction) }
    @objc func show() {
        guard NSApp.modalWindow == nil else { return }
        pendingHide?.cancel(); pendingHide = nil
        let request = UUID(); presentationRequest = request
        if let window, window.isVisible {
            model.animate(.timingCurve(0.16, 0.80, 0.28, 1, duration: MotionTiming.present)) { model.isPresented = true }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        if window == nil {
            let created = LauncherWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            created.title = "Launchpad Classic"
            created.isOpaque = false
            created.backgroundColor = .clear
            created.hasShadow = false
            created.level = .normal
            created.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            created.isReleasedWhenClosed = false
            created.appearance = NSAppearance(named: .darkAqua)
            window = created
            installKeyboardMonitor()
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self, weak created] event in
                guard let self, let created, created.isVisible, self.model.isPresented,
                      self.model.menuTrackingDepth == 0, NSApp.modalWindow == nil,
                      event.window === created || event.window == nil else { return event }
                self.model.scroll(event)
                return nil
            }
        }
        guard let window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        var wallpaper: NSImage?
        if let url = NSWorkspace.shared.desktopImageURL(for: screen) { wallpaper = NSImage(contentsOf: url) }
        model.resetSession()
        window.setFrame(screen.frame, display: true)
        window.contentView = LauncherHostingView(rootView: LauncherView(model: model, wallpaper: wallpaper), model: model)
        window.contentView?.layoutSubtreeIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            guard self.presentationRequest == request, self.pendingHide == nil else { return }
            self.model.focusToken = UUID()
            self.model.animate(.timingCurve(0.16, 0.80, 0.28, 1, duration: MotionTiming.present)) { self.model.isPresented = true }
        }
        updateLoginStatus()
    }
    func hide() {
        presentationRequest = UUID()
        pendingHide?.cancel()
        model.finishSwipe(cancelled: true)
        if model.dragging != nil { model.finishDrag(operationSucceeded: false) }
        model.animate(.timingCurve(0.35, 0, 0.6, 1, duration: MotionTiming.dismiss)) { model.isPresented = false }
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.model.isPresented else { return }
            self.window?.orderOut(nil); self.model.pressedID = nil
        }
        pendingHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (model.reduceMotion ? 0 : MotionTiming.dismiss), execute: work)
    }
    @objc func toggle() { if model.isPresented && NSApp.isActive { hide() } else { show() } }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard NSApp.modalWindow == nil else { return false }
        // Dock reopens are a visibility toggle, independent of activation timing.
        if model.isPresented { hide() }
        else { show() }
        return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func registerShortcut() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, pointer in
            guard let pointer else { return OSStatus(eventNotHandledErr) }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(pointer).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggle() }
            return noErr
        }, 1, &type, context, &handler)
        guard result == noErr else { model.shortcutAvailable = false; return }
        let id = EventHotKeyID(signature: 0x4c50434c, id: 1)
        model.shortcutAvailable = RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey) == noErr
    }

    private func installKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isVisible == true, event.window === self.window,
                  NSApp.modalWindow == nil else { return event }
            // Let the input method commit/cancel marked text before interpreting navigation keys.
            if let editor = self.window?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            if self.model.menuTrackingDepth > 0 || self.model.editingFolderName { return event }
            if event.modifierFlags.contains(.command) {
                if Int(event.keyCode) == kVK_LeftArrow || Int(event.keyCode) == kVK_RightArrow {
                    self.changePage(Int(event.keyCode) == kVK_RightArrow ? 1 : -1); return nil
                }
                if event.charactersIgnoringModifiers == "f" { self.model.closeFolder(); self.model.focusToken = UUID(); return nil }
                if event.charactersIgnoringModifiers == "r" { self.model.refresh(); return nil }
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                if self.model.dragging != nil { self.model.cancelInternalDrag(); return nil }
                if self.model.mousePaging { self.model.finishSwipe(cancelled: true) }
                else if self.model.editing { self.model.stopEditing() }
                else if self.model.folderID != nil { self.model.closeFolder(); self.model.selected = 0 }
                else if !self.model.query.isEmpty { self.model.query = "" }
                else { self.hide() }
                return nil
            }
            let inFolder = self.model.folderID != nil
            let count = inFolder ? self.model.folderApps.count : self.model.visibleEntries.count
            let columns = inFolder ? self.model.folderColumns : self.model.columns
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if inFolder {
                    if self.model.folderApps.indices.contains(self.model.selected) { self.model.launch(self.model.folderApps[self.model.selected]) }
                } else if self.model.visibleEntries.indices.contains(self.model.selected) {
                    self.model.activate(self.model.visibleEntries[self.model.selected])
                }
                return nil
            case kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow:
                if !inFolder && !self.model.query.isEmpty && (Int(event.keyCode) == kVK_LeftArrow || Int(event.keyCode) == kVK_RightArrow) { return event }
                let direction: Int
                switch Int(event.keyCode) {
                case kVK_UpArrow: direction = -columns
                case kVK_DownArrow: direction = columns
                case kVK_LeftArrow: direction = -1
                default: direction = 1
                }
                self.model.selected = max(0, min(max(0, count - 1), self.model.selected + direction))
                self.model.keyboardSelection = true
                if inFolder { self.model.folderPage = self.model.selected / self.model.folderCapacity }
                else { self.model.page = self.model.selected / self.model.capacity }
                return nil
            case kVK_PageDown, kVK_PageUp:
                self.changePage(Int(event.keyCode) == kVK_PageDown ? 1 : -1)
                return nil
            default: return event
            }
        }
    }

    @objc func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            updateLoginStatus()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } catch {
            model.error = "无法更改登录启动：\(error.localizedDescription)"
        }
    }
    private func updateLoginStatus() {
        model.launchAtLogin = SMAppService.mainApp.status == .enabled
        model.loginStatus = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置中允许登录启动" : ""
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor) }
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        for observer in menuObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        scanTimer?.invalidate(); pendingHide?.cancel()
        model.finishDrag(operationSucceeded: false)
        model.save()
    }
}

@main
struct LauncherMain {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let apps = AppScanner.scan()
            print("扫描完成：\(apps.count) 个应用")
            for query in ["Safari", "微信", "weixin", "wx", "终端", "zd"] {
                print("\(query)：\(apps.filter { $0.matches(query) }.map(\.name).joined(separator: ", "))")
            }
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--generate-icon"), CommandLine.arguments.count > index + 1 {
            generateIcon(at: CommandLine.arguments[index + 1]); return
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
    @MainActor private static func generateIcon(at path: String) {
        let image = NSImage(size: NSSize(width: 1024, height: 1024))
        image.lockFocus()
        let bounds = NSRect(x: 64, y: 64, width: 896, height: 896)
        let shape = NSBezierPath(roundedRect: bounds, xRadius: 196, yRadius: 196)
        NSGradient(starting: NSColor(calibratedWhite: 0.86, alpha: 1), ending: NSColor(calibratedWhite: 1, alpha: 1))!.draw(in: shape, angle: 90)
        NSColor(calibratedWhite: 0.72, alpha: 0.5).setStroke()
        shape.lineWidth = 2; shape.stroke()
        let colors: [NSColor] = [.systemGreen, .systemYellow, .systemOrange,
                                 .systemRed, .systemPink, .systemBlue,
                                 .systemPurple, .systemIndigo, .systemTeal]
        for row in 0..<3 {
            for column in 0..<3 {
                let rect = NSRect(x: 221 + column * 210, y: 643 - row * 210, width: 162, height: 162)
                colors[row * 3 + column].setFill()
                NSBezierPath(roundedRect: rect, xRadius: 38, yRadius: 38).fill()
                NSColor.white.withAlphaComponent(0.20).setStroke()
                NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 38, yRadius: 38).stroke()
            }
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
