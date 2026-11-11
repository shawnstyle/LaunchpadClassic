import AppKit
import SwiftUI

private func interactionTrace(_ message: String) {
    #if LAUNCHPAD_TRACE
    let url = URL(fileURLWithPath: "/tmp/LaunchpadClassic-interaction.log")
    let line = Data(("\(Date().timeIntervalSince1970) \(message)\n").utf8)
    if !FileManager.default.fileExists(atPath: url.path) { _ = FileManager.default.createFile(atPath: url.path, contents: nil) }
    if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(line); try? handle.close() }
    #endif
}

@MainActor
struct IconInteraction: NSViewRepresentable {
    let model: LauncherModel
    let entry: LaunchEntry
    let folderID: String?
    let iconSize: Double
    let isInteractive: Bool
    func makeNSView(context: Context) -> IconInteractionView {
        let view = IconInteractionView()
        updateNSView(view, context: context)
        view.setAccessibilityElement(false)
        return view
    }
    func updateNSView(_ view: IconInteractionView, context: Context) {
        view.model = model; view.entry = entry; view.folderID = folderID
        view.iconSize = iconSize; view.isInteractive = isInteractive
    }
}

@MainActor
final class IconInteractionView: NSView {
    weak var model: LauncherModel?
    var entry = LaunchEntry.app("")
    var folderID: String?
    var iconSize: Double = 96
    var isInteractive = true
    private var mouseStart: CGPoint?
    private var downRoot = CGPoint.zero
    private weak var dragRoot: NSView?
    private var held = false
    private var holdTimer: Timer?
    private var contextActions: [() -> Void] = []
    override var isFlipped: Bool { true }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.buttonMask = 1
        pan.delaysPrimaryMouseButtonEvents = false
        addGestureRecognizer(pan)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isInteractive, model?.isPresented == true, model?.folderID == folderID else { return nil }
        return super.hitTest(point)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private func rootPoint(_ point: CGPoint, from view: NSView?) -> CGPoint {
        guard let root = dragRoot ?? window?.contentView else { return point }
        let point = root.convert(point, from: view)
        return CGPoint(x: point.x, y: root.isFlipped ? point.y : root.bounds.height - point.y)
    }
    @objc private func panned(_ gesture: NSPanGestureRecognizer) {
        guard let model, !model.searching, let root = dragRoot ?? window?.contentView else { return }
        let location = gesture.location(in: root)
        let point = CGPoint(x: location.x, y: root.isFlipped ? location.y : root.bounds.height - location.y)
        switch gesture.state {
        case .began, .changed:
            if model.dragging == nil && hypot(point.x - downRoot.x, point.y - downRoot.y) > 4 { startDrag(at: point) }
            if model.dragging == entry.id { model.trackInternalDrag(at: point) }
        case .ended:
            if model.dragging == entry.id { model.endInternalDrag(at: point) }
        case .cancelled, .failed:
            if model.dragging == entry.id && (model.dragEventMonitor == nil || !NSApp.isActive) { model.cancelInternalDrag() }
        default: break
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let model else { return }
        interactionTrace("down \(entry.id)")
        mouseStart = convert(event.locationInWindow, from: nil)
        dragRoot = window?.contentView
        downRoot = rootPoint(event.locationInWindow, from: nil); held = false
        model.animate(.easeOut(duration: 0.10)) { model.pressedID = entry.id }
        holdTimer?.invalidate()
        let timer = Timer(timeInterval: MotionTiming.hold, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let model = self.model, self.mouseStart != nil, !model.searching else { return }
                self.held = true; model.enterEditing()
            }
        }
        holdTimer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let model, !model.searching else { return }
        let point = rootPoint(event.locationInWindow, from: nil)
        if model.dragging == nil, mouseStart != nil, hypot(point.x - downRoot.x, point.y - downRoot.y) > 4 { startDrag(at: point) }
        if model.dragging == entry.id { model.trackInternalDrag(at: point) }
    }
    private func startDrag(at point: CGPoint) {
        guard let model, model.dragging == nil else { return }
        holdTimer?.invalidate(); holdTimer = nil; mouseStart = nil
        interactionTrace("internal begin \(entry.id)")
        let rect = model.itemFrames[entry.id]
        let center = rect.map { CGPoint(x: $0.midX, y: $0.minY + iconSize / 2) } ?? downRoot
        model.dragPointerOffset = CGPoint(x: downRoot.x - center.x, y: downRoot.y - center.y)
        model.dragOriginalPoint = center
        model.dragVisual.image = model.dragImage(entry, size: iconSize)
        model.dragVisual.point = center; model.dragVisual.scale = 1; model.dragVisual.opacity = 1
        model.beginDrag(entry.id, source: self)
        if let hostWindow = window, let root = hostWindow.contentView {
            model.dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak model, weak root, weak hostWindow] event in
                guard let model, let root, let hostWindow, model.dragging != nil else { return event }
                let location = event.window === hostWindow ? event.locationInWindow : hostWindow.convertPoint(fromScreen: NSEvent.mouseLocation)
                let raw = root.convert(location, from: nil)
                let point = CGPoint(x: raw.x, y: root.isFlipped ? raw.y : root.bounds.height - raw.y)
                if event.type == .leftMouseUp { model.endInternalDrag(at: point) }
                else { model.trackInternalDrag(at: point) }
                return event
            }
        }
        model.animate(.easeOut(duration: 0.12)) { model.dragVisual.scale = 1.08 }
        model.trackInternalDrag(at: point)
    }
    override func mouseUp(with event: NSEvent) {
        holdTimer?.invalidate(); holdTimer = nil
        guard let model else { return }
        if model.dragging == entry.id {
            interactionTrace("internal drop \(entry.id)")
            model.endInternalDrag(at: rootPoint(event.locationInWindow, from: nil))
            mouseStart = nil; return
        }
        guard mouseStart != nil else { return }
        mouseStart = nil
        model.animate(.easeOut(duration: 0.12)) { model.pressedID = nil }
        guard !held, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        model.activate(entry)
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let model else { return nil }
        let entry = self.entry
        let menu = NSMenu(); contextActions = []
        func add(_ title: String, _ action: @escaping () -> Void) {
            let item = NSMenuItem(title: title, action: #selector(runContextAction(_:)), keyEquivalent: "")
            item.target = self; item.tag = contextActions.count; contextActions.append(action); menu.addItem(item)
        }
        if entry.isFolder {
            add("打开文件夹") { model.activate(entry) }
            add("重命名文件夹…") { model.renameFolder(entry.id) }
            add("展开文件夹") { model.animate { model.dissolve(entry.id) } }
        } else if let app = model.appMap[entry.appIDs.first ?? ""] {
            add("打开") { model.launch(app) }
            add("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([app.url]); model.dismiss?() }
            if folderID != nil { add("移出文件夹") { model.animate { model.ungroup(app.id) } } }
            for folder in model.folders where folder.id != folderID {
                add("移入“\(folder.folderName ?? "文件夹")”") { model.animate { model.add(app.id, to: folder.id) } }
            }
        }
        if !model.searching && folderID == nil {
            let pages = max(1, (model.visibleEntries.count + model.capacity - 1) / model.capacity)
            for page in 0..<pages {
                add("移到第 \(page + 1) 页") { model.animate { model.moveToPage(entry.id, page: page, capacity: model.capacity) } }
            }
        }
        menu.addItem(.separator())
        add(model.editing ? "完成排列" : "编辑排列") { if model.editing { model.stopEditing() } else { model.enterEditing() } }
        return menu
    }
    @objc private func runContextAction(_ sender: NSMenuItem) {
        guard contextActions.indices.contains(sender.tag) else { return }
        contextActions[sender.tag]()
    }
    deinit { holdTimer?.invalidate() }
}

// A native surface catches blank areas that SwiftUI's paged grid otherwise absorbs.
@MainActor
struct BackgroundInteraction: NSViewRepresentable {
    let model: LauncherModel
    let exclusions: [CGRect]
    let clicked: (CGPoint) -> Void
    func makeNSView(context: Context) -> BackgroundInteractionView {
        let view = BackgroundInteractionView(); view.setAccessibilityElement(false)
        updateNSView(view, context: context); return view
    }
    func updateNSView(_ view: BackgroundInteractionView, context: Context) {
        view.model = model; view.exclusions = exclusions; view.clicked = clicked
    }
}

@MainActor
final class BackgroundInteractionView: NSView {
    weak var model: LauncherModel?
    var exclusions: [CGRect] = []
    var clicked: ((CGPoint) -> Void)?
    private var down: CGPoint?
    private var downTime: TimeInterval = 0
    private var didPageDrag = false
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let model, model.isPresented, model.dragging == nil else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local), !exclusions.contains(where: { $0.contains(local) }),
              !model.itemFrames.contains(where: { $0.key != "__folderPanel" && $0.value.contains(local) }) else { return nil }
        return super.hitTest(point)
    }
    override func mouseDown(with event: NSEvent) {
        down = convert(event.locationInWindow, from: nil); downTime = event.timestamp; didPageDrag = false
    }
    override func mouseDragged(with event: NSEvent) {
        guard let down, let model else { return }
        let point = convert(event.locationInWindow, from: nil)
        let dx = point.x - down.x, dy = point.y - down.y
        if !didPageDrag, abs(dx) > 6, abs(dx) > abs(dy) * 1.1 {
            didPageDrag = model.beginMousePaging(timestamp: downTime)
        }
        if didPageDrag { model.updateMousePaging(displacement: dx, timestamp: event.timestamp) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { down = nil; didPageDrag = false }
        let point = convert(event.locationInWindow, from: nil)
        guard let down else { return }
        if didPageDrag {
            model?.endMousePaging(displacement: point.x - down.x, timestamp: event.timestamp)
            return
        }
        guard hypot(point.x - down.x, point.y - down.y) < 4 else { return }
        clicked?(point)
    }
}

@MainActor
final class LauncherHostingView: NSHostingView<LauncherView> {
    weak var model: LauncherModel?
    init(rootView: LauncherView, model: LauncherModel) { self.model = model; super.init(rootView: rootView) }
    @available(*, unavailable) required init(rootView: LauncherView) { fatalError() }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override func scrollWheel(with event: NSEvent) {
        guard let model, model.isPresented, !model.editingFolderName, NSApp.modalWindow == nil else { super.scrollWheel(with: event); return }
        model.scroll(event)
    }
}
