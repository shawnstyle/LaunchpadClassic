import AppKit
import SwiftUI

extension Animation {
    static var launcherPage: Animation { .timingCurve(0.18, 0.78, 0.26, 1, duration: MotionTiming.page) }
    static var launcherFolder: Animation { .timingCurve(0.18, 0.80, 0.25, 1, duration: MotionTiming.folder) }
    static var launcherReorder: Animation { .interpolatingSpring(mass: 1, stiffness: 310, damping: 30, initialVelocity: 0) }
}

@MainActor
final class DragVisualState: ObservableObject {
    @Published var point = CGPoint.zero
    @Published var scale: Double = 1
    @Published var opacity: Double = 1
    @Published var image: NSImage?
}

@MainActor
extension LauncherModel {
    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    func animate(_ animation: Animation = .launcherReorder, _ changes: () -> Void) {
        withAnimation(reduceMotion ? nil : animation, changes)
    }
    var currentPage: Int { folderID == nil ? page : folderPage }
    var currentPageCount: Int {
        let total = folderID == nil ? visibleEntries.count : folderApps.count
        let capacity = folderID == nil ? capacity : folderCapacity
        return max(1, (total + capacity - 1) / capacity)
    }
    func navigate(to target: Int) {
        scrollEndWork?.cancel(); scrollEndWork = nil
        swipeInProgress = false; mousePaging = false; rawSwipe = 0; swipeVelocity = 0; swipeWasHorizontal = false
        let next = max(0, min(currentPageCount - 1, target))
        animate(.launcherPage) {
            if folderID == nil { page = next; selected = next * capacity }
            else { folderPage = next; selected = next * folderCapacity }
            swipeOffset = 0
            keyboardSelection = false
        }
    }
    func scroll(_ event: NSEvent) {
        guard !editingFolderName, dragging == nil, !mousePaging, menuTrackingDepth == 0 else { return }
        // Momentum is accounted for by the release velocity, never as a second gesture.
        if !event.momentumPhase.isEmpty { return }
        // Detented wheels and phase-less vertical high-resolution wheels page per gesture.
        // Phased horizontal input retains continuous trackpad / Magic Mouse tracking.
        let vertical = abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX)
        if !event.hasPreciseScrollingDeltas || (event.phase.isEmpty && vertical) {
            let delta = vertical ? event.scrollingDeltaY : event.scrollingDeltaX
            guard abs(delta) > 0.01 else { return }
            let direction = delta < 0 ? 1 : -1
            guard direction != lastWheelDirection || event.timestamp - lastWheelTime >= MotionTiming.page || event.timestamp < lastWheelTime else { return }
            lastWheelTime = event.timestamp; lastWheelDirection = direction
            navigate(to: currentPage + direction)
            return
        }
        if event.phase.contains(.began) {
            rawSwipe = 0; swipeVelocity = 0; lastSwipeTime = event.timestamp
            swipeInProgress = true; swipeWasHorizontal = false
        }
        if event.phase.contains(.cancelled) { finishSwipe(cancelled: true); return }
        if event.phase.contains(.ended) { finishSwipe(cancelled: false); return }
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 0.8 || swipeWasHorizontal else { return }
        swipeWasHorizontal = true
        if !swipeInProgress { rawSwipe = 0; swipeVelocity = 0; swipeInProgress = true }
        let delta = Double(event.scrollingDeltaX)
        let dt = max(0.006, min(0.05, event.timestamp - lastSwipeTime))
        lastSwipeTime = event.timestamp
        swipeVelocity = swipeVelocity * 0.35 + (delta / dt) * 0.65
        rawSwipe += delta
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            swipeOffset = reduceMotion ? 0 : PageSwipePhysics.displacement(rawSwipe, page: currentPage, count: currentPageCount, width: pageWidth)
        }
        scrollEndWork?.cancel()
        if event.phase.isEmpty {
            let work = DispatchWorkItem { [weak self] in self?.finishSwipe(cancelled: false) }
            scrollEndWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
        }
    }
    @discardableResult
    func beginMousePaging(timestamp: TimeInterval) -> Bool {
        guard !editingFolderName, dragging == nil, menuTrackingDepth == 0, currentPageCount > 1 else { return false }
        finishSwipe(cancelled: true)
        scrollEndWork?.cancel(); scrollEndWork = nil
        mousePaging = true; swipeInProgress = true; swipeWasHorizontal = true
        rawSwipe = 0; swipeVelocity = 0; lastSwipeTime = timestamp
        return true
    }
    func updateMousePaging(displacement: Double, timestamp: TimeInterval) {
        guard mousePaging else { return }
        let dt = max(0.006, min(0.05, timestamp - lastSwipeTime))
        swipeVelocity = swipeVelocity * 0.35 + (displacement - rawSwipe) / dt * 0.65
        rawSwipe = displacement; lastSwipeTime = timestamp
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            swipeOffset = reduceMotion ? 0 : PageSwipePhysics.displacement(rawSwipe, page: currentPage, count: currentPageCount, width: pageWidth)
        }
    }
    func endMousePaging(displacement: Double, timestamp: TimeInterval, cancelled: Bool = false) {
        guard mousePaging else { return }
        // Waiting before release must not retain the velocity from the initial flick.
        if timestamp - lastSwipeTime > 0.10 { swipeVelocity = 0 }
        if abs(displacement - rawSwipe) > 0.01 { updateMousePaging(displacement: displacement, timestamp: timestamp) }
        finishSwipe(cancelled: cancelled)
    }
    func finishSwipe(cancelled: Bool) {
        guard swipeInProgress else { return }
        scrollEndWork?.cancel(); scrollEndWork = nil
        let next = PageSwipePhysics.destination(offset: rawSwipe, velocity: swipeVelocity, page: currentPage, count: currentPageCount, width: pageWidth, cancelled: cancelled)
        swipeInProgress = false
        navigate(to: next)
        rawSwipe = 0; swipeVelocity = 0; swipeWasHorizontal = false
    }
    func cancelFolderRename() {
        folderRenameWork?.cancel(); folderRenameWork = nil; folderRenameID = nil
    }
    func openFolder(_ id: String, rename: Bool = false) {
        guard let folder = layout.entries.first(where: { $0.id == id && $0.isFolder }) else { return }
        finishSwipe(cancelled: true)
        cancelFolderRename()
        if let rect = itemFrames[id] { folderOrigin = CGPoint(x: rect.midX, y: rect.minY + iconCanvasSize / 2) }
        else { folderOrigin = CGPoint(x: pageWidth / 2, y: pageHeight / 2) }
        animate(.launcherFolder) { folderID = folder.id; folderPage = 0; selected = 0; keyboardSelection = false; swipeOffset = 0 }
        if rename {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.folderID == id, self.dragging == nil else { return }
                self.folderRenameWork = nil; self.folderRenameID = id
            }
            folderRenameWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : MotionTiming.folder), execute: work)
        }
    }
    func closeFolder() {
        finishSwipe(cancelled: true)
        cancelFolderRename()
        animate(.launcherFolder) { folderID = nil; keyboardSelection = false; swipeOffset = 0 }
    }
    func enterEditing() { animate { editing = true; pressedID = nil } }
    func stopEditing() { cancelFolderRename(); animate { editing = false; dragInitialEditing = false; pressedID = nil } }
    func backgroundClicked() {
        if editing { stopEditing() }
        else if folderID != nil { closeFolder() }
        else { dismiss?() }
    }

    func beginDrag(_ id: String, source: AnyObject) {
        guard !searching, dragging == nil else { return }
        dragSnapshot = layout; dragInitialPage = page; dragInitialFolder = folderID; dragInitialFolderPage = folderPage
        cancelFolderRename()
        dragInitialEditing = editing; dragCreatedFolderID = nil
        dragCommitted = false; activeDragSource = source
        animate { dragging = id; pressedID = nil; editing = true }
    }
    func clearHover() {
        hoverWork?.cancel(); hoverWork = nil; autoOpenWork?.cancel(); autoOpenWork = nil
        hoverKey = nil
        if dropTargetID != nil || folderDropReady { animate { dropTargetID = nil; folderDropReady = false } }
    }
    func hover(_ target: LaunchEntry, center: Bool, inFolder: String?) {
        guard let source = dragging, source != target.id else { return }
        let key = "\(inFolder ?? "root"):\(target.id):\(center)"
        guard key != hoverKey else { return }
        clearHover(); hoverKey = key
        let sourceIsFolder = layout.entries.first { $0.id == source }?.isFolder == true
        if inFolder == nil && center && !sourceIsFolder {
            animate { dropTargetID = target.id }
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverKey == key, self.dragging != nil else { return }
                self.animate { self.folderDropReady = true }
            }
            hoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + MotionTiming.folderHover, execute: work)
            if target.isFolder {
                let open = DispatchWorkItem { [weak self] in
                    guard let self, self.hoverKey == key, self.dragging != nil else { return }
                    self.clearHover(); self.openFolder(target.id)
                }
                autoOpenWork = open; DispatchQueue.main.asyncAfter(deadline: .now() + MotionTiming.folderOpen, execute: open)
            }
        } else {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.hoverKey == key, self.dragging != nil else { return }
                self.animate {
                    if let inFolder, !sourceIsFolder { self.layout.moveInsideFolder(source, before: target.appIDs.first, folderID: inFolder) }
                    else if sourceIsFolder { self.layout.move(source, before: target.id) }
                    else { self.layout.insertAtRoot(source, before: target.id) }
                }
            }
            hoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.13, execute: work)
        }
    }
    func drop(on target: LaunchEntry, inFolder: String?) -> Bool {
        guard let source = dragging else { return false }
        let ready = folderDropReady && dropTargetID == target.id
        let sourceIsFolder = layout.entries.first { $0.id == source }?.isFolder == true
        clearHover(); cancelEdge()
        animate {
            if source != target.id {
                if let inFolder, !sourceIsFolder { layout.moveInsideFolder(source, before: target.appIDs.first, folderID: inFolder) }
                else if ready && !sourceIsFolder {
                    if target.isFolder { layout.place(source, in: target.id) }
                    else if let id = target.appIDs.first {
                        layout.group(source, with: id)
                        dragCreatedFolderID = layout.entries.first { $0.isFolder && $0.appIDs.contains(source) && $0.appIDs.contains(id) }?.id
                    }
                } else if sourceIsFolder { layout.move(source, before: target.id) }
                else { layout.insertAtRoot(source, before: target.id) }
            }
        }
        dragCommitted = true
        return true
    }
    func dropOnBackground() -> Bool {
        guard let source = dragging else { return false }
        clearHover(); cancelEdge()
        let sourceIsFolder = layout.entries.first { $0.id == source }?.isFolder == true
        animate {
            if folderID != nil {
                // The host receives drops outside the expanded folder; inside is handled by its tile/surface.
                layout.insertAtRoot(source, before: visibleEntries.dropFirst(page * capacity).first?.id)
                closeFolder()
            } else if !sourceIsFolder {
                let candidates = visibleEntries.filter { $0.id != source }
                let target = candidates.dropFirst(page * capacity).first?.id
                layout.insertAtRoot(source, before: target)
            }
        }
        dragCommitted = true
        return true
    }
    func dropIntoFolderBackground(_ folder: String) -> Bool {
        guard let source = dragging, layout.entries.first(where: { $0.id == source })?.isFolder != true else { return false }
        clearHover(); cancelEdge()
        animate { layout.moveInsideFolder(source, before: nil, folderID: folder) }
        dragCommitted = true
        return true
    }
    func finishDrag(operationSucceeded: Bool) {
        guard dragging != nil else { return }
        if let monitor = dragEventMonitor { NSEvent.removeMonitor(monitor); dragEventMonitor = nil }
        dragSettleWork?.cancel(); dragSettleWork = nil; folderExitWork?.cancel(); folderExitWork = nil
        dragSettling = false
        clearHover(); cancelEdge()
        let committed = operationSucceeded && dragCommitted
        let createdFolder = committed ? dragCreatedFolderID : nil
        if !committed, let snapshot = dragSnapshot {
            animate {
                layout = snapshot; page = dragInitialPage; folderID = dragInitialFolder; folderPage = dragInitialFolderPage
            }
        }
        animate { dragging = nil; editing = dragInitialEditing; pressedID = nil; dragVisual.image = nil }
        if committed { save() }
        dragSnapshot = nil; activeDragSource = nil; dragCommitted = false; dragCreatedFolderID = nil
        if let createdFolder { openFolder(createdFolder, rename: true) }
        resumePendingRefresh()
    }
    func cancelEdge() { edgeWork?.cancel(); edgeWork = nil; edgeDirection = 0 }
    func dragMoved(to point: CGPoint) {
        guard dragging != nil else { return }
        guard point.x >= 0, point.x <= pageWidth, point.y >= 0, point.y <= pageHeight else { cancelEdge(); return }
        let direction = point.x < 44 ? -1 : point.x > pageWidth - 44 ? 1 : 0
        guard direction != 0 else { cancelEdge(); return }
        guard direction != edgeDirection else { return }
        cancelEdge(); edgeDirection = direction
        scheduleEdge(direction)
    }
    func scheduleEdge(_ direction: Int) {
        guard currentPage + direction >= 0, currentPage + direction < currentPageCount else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.dragging != nil, self.edgeDirection == direction else { return }
            self.clearHover(); self.navigate(to: self.currentPage + direction)
            self.scheduleEdge(direction)
        }
        edgeWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + MotionTiming.edgeHover, execute: work)
    }
    func hoverPage(_ target: Int) {
        guard dragging != nil, hoverKey != "page:\(target)" else { return }
        clearHover(); hoverKey = "page:\(target)"
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.hoverKey == "page:\(target)", self.dragging != nil else { return }
            self.navigate(to: target)
        }
        hoverWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
    func internalTarget(at point: CGPoint) -> LaunchEntry? {
        let entries: [LaunchEntry]
        if folderID != nil {
            entries = Array(folderApps.dropFirst(folderPage * folderCapacity).prefix(folderCapacity)).map { .app($0.id) }
        } else { entries = Array(visibleEntries.dropFirst(page * capacity).prefix(capacity)) }
        return entries.first { itemFrames[$0.id]?.contains(point) == true }
    }
    func trackInternalDrag(at point: CGPoint) {
        guard dragging != nil, !dragSettling else { return }
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            let visualPoint = CGPoint(x: point.x - dragPointerOffset.x, y: point.y - dragPointerOffset.y)
            if dragVisual.point != visualPoint { dragVisual.point = visualPoint }
        }
        dragMoved(to: point)
        if let folderID, !folderPanelRect.contains(point) {
            if folderExitWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.dragging != nil, self.folderID == folderID, !self.dragSettling else { return }
                    self.closeFolder(); self.folderExitWork = nil
                }
                folderExitWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
            }
        } else { folderExitWork?.cancel(); folderExitWork = nil }
        if folderID == nil, abs(point.y - pageHeight * 0.878) < 20 {
            let scale = max(0.5, min(1.5, min(pageWidth / 1512, pageHeight / 982)))
            let first = pageWidth / 2 - Double(currentPageCount - 1) * 10 * scale
            let target = Int(((point.x - first) / (20 * scale)).rounded())
            if target >= 0 && target < currentPageCount { hoverPage(target); return }
        }
        guard let target = internalTarget(at: point), target.id != dragging, let rect = itemFrames[target.id] else {
            if hoverKey != nil { clearHover() }; return
        }
        let center = abs(point.x - rect.midX) < iconCanvasSize * 0.37 && point.y < rect.minY + iconCanvasSize
        hover(target, center: center, inFolder: folderID)
    }
    func endInternalDrag(at point: CGPoint) {
        guard dragging != nil, !dragSettling else { return }
        guard CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight).contains(point) else { cancelInternalDrag(); return }
        let accepted: Bool
        if let target = internalTarget(at: point) { accepted = drop(on: target, inFolder: folderID) }
        else if let folderID, folderPanelRect.contains(point) { accepted = dropIntoFolderBackground(folderID) }
        else { accepted = dropOnBackground() }
        guard accepted else { cancelInternalDrag(); return }
        animate { editing = dragInitialEditing }
        dragSettling = true; folderExitWork?.cancel(); folderExitWork = nil
        let work = DispatchWorkItem { [weak self] in
            guard let self, let source = self.dragging else { return }
            var point = self.dragVisual.point
            var scale = 1.0
            if self.folderID == nil, let folder = self.layout.entries.first(where: { $0.isFolder && $0.appIDs.contains(source) }), let rect = self.itemFrames[folder.id] {
                let slot = min(8, folder.appIDs.firstIndex(of: source) ?? 0)
                let unit = self.iconCanvasSize / 96
                let box = self.iconCanvasSize * 0.835
                let mini = (box - 18 * unit) / 3
                point = CGPoint(x: rect.midX - box / 2 + 7 * unit + mini / 2 + Double(slot % 3) * (mini + 2 * unit),
                                y: rect.minY + (self.iconCanvasSize - box) / 2 + 7 * unit + mini / 2 + Double(slot / 3) * (mini + 2 * unit))
                scale = mini / self.iconCanvasSize
            } else if let rect = self.itemFrames[source] {
                point = CGPoint(x: rect.midX, y: rect.minY + self.iconCanvasSize / 2)
            }
            self.animate(.easeOut(duration: MotionTiming.reorder)) {
                self.dragVisual.point = point; self.dragVisual.scale = scale; self.dragVisual.opacity = 0.75
            }
            let finish = DispatchWorkItem { [weak self] in self?.finishDrag(operationSucceeded: true) }
            self.dragSettleWork = finish
            DispatchQueue.main.asyncAfter(deadline: .now() + (self.reduceMotion ? 0 : MotionTiming.reorder), execute: finish)
        }
        dragSettleWork = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
    }
    func cancelInternalDrag() {
        guard dragging != nil, !dragSettling else { return }
        animate { editing = dragInitialEditing }
        dragSettling = true; clearHover(); cancelEdge(); folderExitWork?.cancel(); folderExitWork = nil
        if let snapshot = dragSnapshot {
            animate {
                layout = snapshot; page = dragInitialPage; folderID = dragInitialFolder; folderPage = dragInitialFolderPage
                dragVisual.point = dragOriginalPoint; dragVisual.scale = 1; dragVisual.opacity = 0.85
            }
        }
        let work = DispatchWorkItem { [weak self] in self?.finishDrag(operationSucceeded: false) }
        dragSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0 : MotionTiming.reorder), execute: work)
    }
    func dragImage(_ entry: LaunchEntry, size: CGFloat) -> NSImage {
        if !entry.isFolder, let id = entry.appIDs.first { return icon(id) }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let box = size * 0.835
        let origin = (size - box) / 2
        NSColor.white.withAlphaComponent(0.38).setFill()
        NSBezierPath(roundedRect: NSRect(x: origin, y: origin, width: box, height: box), xRadius: box * 0.22, yRadius: box * 0.22).fill()
        let mini = box * 0.235, gap = box * 0.02, inset = box * 0.10
        for (index, id) in entry.appIDs.prefix(9).enumerated() {
            icon(id).draw(in: NSRect(x: origin + inset + CGFloat(index % 3) * (mini + gap), y: origin + box - inset - mini - CGFloat(index / 3) * (mini + gap), width: mini, height: mini))
        }
        image.unlockFocus(); return image
    }
}
