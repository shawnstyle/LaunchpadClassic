import AppKit
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    typealias AppOpener = (URL, @escaping (Error?) -> Void) -> Void
    private let openApplication: AppOpener
    @Published var apps: [AppRecord] = []
    @Published var layout: LaunchLayout
    @Published var query = "" { didSet {
        page = 0; selected = 0; keyboardSelection = false
        scrollEndWork?.cancel(); scrollEndWork = nil
        swipeInProgress = false; mousePaging = false; swipeOffset = 0; rawSwipe = 0; swipeVelocity = 0; swipeWasHorizontal = false
    } }
    @Published var page = 0
    @Published var selected = 0
    @Published var keyboardSelection = false
    @Published var folderPage = 0
    @Published var editingFolderName = false
    @Published var folderRenameID: String?
    var folderRenameWork: DispatchWorkItem?
    @Published var folderID: String?
    @Published var scanning = false
    @Published var error: String?
    @Published var focusToken = UUID()
    @Published var shortcutAvailable = true
    @Published var launchAtLogin = false
    @Published var loginStatus = ""
    @Published var dragging: String?
    @Published var isPresented = false
    @Published var launchingAppID: String?
    @Published var swipeOffset: Double = 0
    @Published var swipeInProgress = false
    var mousePaging = false
    @Published var editing = false
    @Published var pressedID: String?
    @Published var dropTargetID: String?
    @Published var folderDropReady = false
    let dragVisual = DragVisualState()
    var dragPointerOffset = CGPoint.zero
    var dragOriginalPoint = CGPoint.zero
    var dragEventMonitor: Any?
    var dragSettling = false
    var dragSettleWork: DispatchWorkItem?
    var folderExitWork: DispatchWorkItem?
    var menuTrackingDepth = 0
    var pageWidth: Double = 1512
    var pageHeight: Double = 982
    var iconCanvasSize: Double = 96
    var itemFrames: [String: CGRect] = [:]
    var folderPanelRect = CGRect.zero
    var folderOrigin = CGPoint(x: 756, y: 491)
    var rawSwipe: Double = 0
    var swipeVelocity: Double = 0
    var lastSwipeTime: Double = 0
    var swipeWasHorizontal = false
    var lastWheelTime = -Double.infinity
    var lastWheelDirection = 0
    var scrollEndWork: DispatchWorkItem?
    var dragSnapshot: LaunchLayout?
    var dragInitialPage = 0
    var dragInitialFolder: String?
    var dragInitialFolderPage = 0
    var dragInitialEditing = false
    var dragCreatedFolderID: String?
    var dragCommitted = false
    var activeDragSource: AnyObject?
    var hoverWork: DispatchWorkItem?
    var autoOpenWork: DispatchWorkItem?
    var hoverKey: String?
    var edgeWork: DispatchWorkItem?
    var edgeDirection = 0
    private var icons: [String: NSImage] = [:]
    private var refreshPending = false
    var folderColumns = 7
    var folderCapacity = 21
    var columns = 7
    var capacity = 35
    var dismiss: (() -> Void)?
    var presentLaunchError: ((String) -> Void)?
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, openApplication: @escaping AppOpener = { url, completion in
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in completion(error) }
    }) {
        self.defaults = defaults
        self.openApplication = openApplication
        if let data = defaults.data(forKey: "layout"), let saved = try? JSONDecoder().decode(LaunchLayout.self, from: data) {
            layout = saved
        } else { layout = LaunchLayout() }
    }

    var appMap: [String: AppRecord] { Dictionary(uniqueKeysWithValues: apps.map { ($0.id, $0) }) }
    var searching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var visibleEntries: [LaunchEntry] {
        if searching { return apps.filter { $0.matches(query) }.map { .app($0.id) } }
        let available = Set(apps.map(\.id))
        return layout.entries.filter { $0.appIDs.contains { available.contains($0) } }
    }
    var openFolder: LaunchEntry? { layout.entries.first { $0.id == folderID && $0.isFolder } }
    var folderApps: [AppRecord] { (openFolder?.appIDs ?? []).compactMap { appMap[$0] } }
    var folders: [LaunchEntry] { layout.entries.filter(\.isFolder) }

    func title(_ entry: LaunchEntry) -> String { entry.folderName ?? appMap[entry.appIDs.first ?? ""]?.name ?? "应用" }
    func icon(_ id: String) -> NSImage {
        if let cached = icons[id] { return cached }
        let image = NSWorkspace.shared.icon(forFile: id)
        image.size = NSSize(width: 128, height: 128)
        icons[id] = image
        return image
    }

    func refresh() {
        guard dragging == nil else { refreshPending = true; return }
        guard !scanning else { refreshPending = true; return }
        scanning = true
        let extras = defaults.stringArray(forKey: "extraApps") ?? []
        DispatchQueue.global(qos: .userInitiated).async {
            let records = AppScanner.scan(extraPaths: extras)
            DispatchQueue.main.async {
                self.apps = records
                self.layout.reconcile(with: records.map(\.id))
                self.icons.removeAll()
                self.save()
                self.scanning = false
                if self.refreshPending { self.refreshPending = false; self.refresh() }
            }
        }
    }

    func resumePendingRefresh() {
        if refreshPending { refreshPending = false; refresh() }
    }
    func save() { guard dragging == nil else { return }; if let data = try? JSONEncoder().encode(layout) { defaults.set(data, forKey: "layout") } }
    func resetSession() { cancelFolderRename(); mousePaging = false; lastWheelTime = -Double.infinity; lastWheelDirection = 0; query = ""; page = 0; selected = 0; folderID = nil; folderPage = 0; keyboardSelection = false; editingFolderName = false; error = nil; launchingAppID = nil; swipeOffset = 0; swipeInProgress = false; editing = false; pressedID = nil; focusToken = UUID() }
    func launch(_ app: AppRecord) {
        // Hand the screen over on the click, even if Launch Services delays its callback.
        // A late success must never dismiss a subsequently reopened launcher session.
        launchingAppID = app.id
        dismiss?()
        openApplication(app.url) { [weak self] launchError in
            guard let launchError else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let message = "无法打开“\(app.name)”：\(launchError.localizedDescription)"
                if let present = self.presentLaunchError { present(message) }
                else { self.error = message }
            }
        }
    }
    func activate(_ entry: LaunchEntry) {
        if entry.isFolder { openFolder(entry.id) }
        else if let id = entry.appIDs.first, let app = appMap[id] { launch(app) }
    }
    func commitFolderName(_ id: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = layout.entries.firstIndex(where: { $0.id == id }) else { return }
        layout.entries[index].folderName = trimmed; save()
    }
    func renameFolder(_ id: String) {
        guard let index = layout.entries.firstIndex(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "文件夹名称"
        alert.addButton(withTitle: "保存"); alert.addButton(withTitle: "取消")
        let field = NSTextField(string: layout.entries[index].folderName ?? "新建文件夹")
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 26)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { layout.entries[index].folderName = name; save() }
        }
    }
    func dissolve(_ id: String) {
        guard let index = layout.entries.firstIndex(where: { $0.id == id }) else { return }
        let entry = layout.entries.remove(at: index)
        layout.entries.insert(contentsOf: entry.appIDs.map(LaunchEntry.app), at: index)
        folderID = nil; save()
    }
    func add(_ appID: String, to folderID: String) { layout.place(appID, in: folderID); save() }
    func ungroup(_ appID: String) { layout.ungroup(appID); save() }
    func handleDrop(source: String, onto target: LaunchEntry) {
        guard source != target.id else { return }
        if let sourceEntry = layout.entries.first(where: { $0.id == source }), sourceEntry.isFolder {
            layout.move(source, before: target.id)
        } else if target.isFolder { layout.place(source, in: target.id) }
        else if let targetApp = target.appIDs.first { layout.group(source, with: targetApp) }
        dragging = nil; save()
    }
    func moveToPage(_ entryID: String, page: Int, capacity: Int) {
        let visible = visibleEntries
        let offset = page * capacity
        guard let index = layout.entries.firstIndex(where: { $0.id == entryID }) else { return }
        let item = layout.entries.remove(at: index)
        let targets = visible.filter { $0.id != entryID }
        if offset < targets.count, let insert = layout.entries.firstIndex(where: { $0.id == targets[offset].id }) {
            layout.entries.insert(item, at: insert)
        } else { layout.entries.append(item) }
        save()
    }
    func sortApps() {
        let alert = NSAlert()
        alert.messageText = "恢复默认排列？"
        alert.informativeText = "文件夹会被展开，所有应用按名称重新排列。不会删除任何应用。"
        alert.addButton(withTitle: "恢复排列"); alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            layout.entries = apps.map { .app($0.id) }; folderID = nil; page = 0; selected = 0; save()
        }
    }
    func chooseApps() {
        let panel = NSOpenPanel()
        panel.message = "添加其他位置的应用"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.applicationBundle]
        if panel.runModal() == .OK {
            let existing = defaults.stringArray(forKey: "extraApps") ?? []
            defaults.set(Array(Set(existing + panel.urls.map(\.path))), forKey: "extraApps")
            refresh()
        }
    }
}
