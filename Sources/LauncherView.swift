import AppKit
import SwiftUI

struct FrostedBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct ItemFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}

struct LauncherView: View {
    @ObservedObject var model: LauncherModel
    var wallpaper: NSImage?
    @FocusState private var searchFocused: Bool
    @FocusState private var folderTitleFocused: Bool
    @State private var folderName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let grid = GridGeometry(width: proxy.size.width, height: proxy.size.height)
            ZStack {
                background(size: proxy.size, scale: grid.scale)
                    .opacity(model.isPresented ? 1 : 0)
                    .contentShape(Rectangle()).onTapGesture { model.backgroundClicked() }
                ZStack(alignment: .topLeading) {
                    rootPages(grid)
                    searchField(grid).position(x: grid.width / 2, y: grid.searchCenterY)
                    if model.scanning && model.apps.isEmpty {
                        ProgressView().controlSize(.small).position(x: grid.width / 2, y: grid.height * 0.45)
                    } else if model.visibleEntries.isEmpty {
                        Text("无结果").font(.system(size: 24 * grid.scale, weight: .light))
                            .foregroundStyle(.white.opacity(0.85))
                            .position(x: grid.width / 2, y: grid.height * 0.45).transition(.opacity)
                    }
                    pageDots(count: grid.pageCount(for: model.visibleEntries.count), current: model.page, scale: grid.scale) { model.navigate(to: $0) }
                        .position(x: grid.width / 2, y: grid.pageCenterY)
                }
                .frame(width: grid.width, height: grid.height)
                .blur(radius: model.folderID == nil ? 0 : 7 * grid.scale)
                .opacity(model.folderID == nil ? 1 : 0.34)
                .allowsHitTesting(model.folderID == nil && model.isPresented)
                .accessibilityHidden(model.folderID != nil)
                .scaleEffect(presentationScale, anchor: launchAnchor(grid))
                .opacity(model.isPresented ? 1 : 0)
                if let folder = model.openFolder {
                    folderOverlay(folder, grid: grid)
                        .opacity(model.isPresented ? 1 : 0)
                        .allowsHitTesting(model.isPresented)
                }
            }
            .frame(width: grid.width, height: grid.height)
            .overlay(BackgroundInteraction(model: model, exclusions: backgroundExclusions(grid)) { point in
                folderTitleFocused = false
                if model.folderID != nil && model.folderPanelRect.contains(point) {
                    model.cancelFolderRename(); model.stopEditing()
                } else if model.editing {
                    model.stopEditing()
                } else if model.folderID != nil {
                    closeFolder()
                } else {
                    model.backgroundClicked()
                }
            })
            .overlay(DragGhost(visual: model.dragVisual, size: grid.iconSize).allowsHitTesting(false).accessibilityHidden(true))
            .coordinateSpace(name: "launcher")
            .onPreferenceChange(ItemFrames.self) { frames in
                model.itemFrames = frames
                if let panel = frames["__folderPanel"] { model.folderPanelRect = panel }
            }
            .onAppear { updateGrid(grid) }
            .onChange(of: proxy.size) { updateGrid(grid) }
            .onChange(of: model.visibleEntries.count) { updateGrid(grid) }
            .preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .launcherFolder, value: model.folderID)
        }
        .ignoresSafeArea()
        .onAppear { searchFocused = true }
        .onChange(of: model.focusToken) { searchFocused = true }
        .onChange(of: model.folderID) { old, id in
            if let old { model.commitFolderName(old, name: folderName) }
            folderTitleFocused = false; model.editingFolderName = false; searchFocused = id == nil
            if let id { folderName = model.layout.entries.first { $0.id == id }?.folderName ?? "文件夹" }
            else { model.selected = model.page * model.capacity }
        }
        .onChange(of: model.folderRenameID) { _, id in
            guard let id, id == model.folderID, model.isPresented else { return }
            searchFocused = false; folderTitleFocused = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard folderTitleFocused, model.folderID == id, model.folderRenameID == id,
                      let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
                editor.selectAll(nil)
                model.folderRenameID = nil
            }
        }
        .onChange(of: folderTitleFocused) { _, focused in
            model.editingFolderName = focused
            if !focused, let id = model.folderID { model.commitFolderName(id, name: folderName) }
        }
        .onChange(of: model.query) {
            if model.searching {
                model.closeFolder(); model.stopEditing(); model.swipeOffset = 0
            }
        }
        .onChange(of: model.folderApps.count) {
            let count = model.folderApps.count
            let last = max(0, (count + model.folderCapacity - 1) / model.folderCapacity - 1)
            if model.folderPage > last { model.folderPage = last }
            if model.folderID != nil && model.selected >= count { model.selected = max(0, count - 1) }
        }
        .alert("应用没有打开", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
    private var presentationScale: CGFloat {
        if reduceMotion { return 1 }
        if model.isPresented { return 1 }
        return model.launchingAppID == nil ? 0.90 : 1.14
    }
    private func launchAnchor(_ grid: GridGeometry) -> UnitPoint {
        guard let id = model.launchingAppID, let frame = model.itemFrames[id] else { return .center }
        return UnitPoint(x: frame.midX / grid.width, y: (frame.minY + grid.iconSize / 2) / grid.height)
    }
    @ViewBuilder private func background(size: CGSize, scale: Double) -> some View {
        if let wallpaper {
            Image(nsImage: wallpaper).resizable().aspectRatio(contentMode: .fill)
                .frame(width: size.width + 80 * scale, height: size.height + 80 * scale)
                .blur(radius: reduceMotion ? 24 * scale : model.isPresented ? (model.folderID == nil ? 24 : 30) * scale : 0, opaque: true)
                .overlay(Color.black.opacity(model.isPresented ? 0.13 : 0))
                .frame(width: size.width, height: size.height).clipped().accessibilityHidden(true)
        } else { FrostedBackground().overlay(Color.black.opacity(0.10)) }
    }
    private func searchField(_ grid: GridGeometry) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4 * grid.scale).fill(.white.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 4 * grid.scale).strokeBorder(.white.opacity(0.22), lineWidth: 1))
            if model.query.isEmpty {
                HStack(spacing: 5 * grid.scale) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11 * grid.scale, weight: .medium))
                    Text("搜索").font(.system(size: 13 * grid.scale))
                }.foregroundStyle(.white.opacity(0.65)).allowsHitTesting(false).transition(.opacity)
            }
            HStack(spacing: 5 * grid.scale) {
                if !model.query.isEmpty {
                    Image(systemName: "magnifyingglass").font(.system(size: 11 * grid.scale)).foregroundStyle(.white.opacity(0.7)).transition(.opacity)
                }
                TextField("", text: $model.query).textFieldStyle(.plain).font(.system(size: 13 * grid.scale))
                    .foregroundStyle(.white).tint(model.query.isEmpty ? .clear : .white)
                    .focused($searchFocused).accessibilityLabel("搜索应用，支持名称和拼音")
                if !model.query.isEmpty {
                    Button { model.query = ""; searchFocused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 11 * grid.scale)).foregroundStyle(.white.opacity(0.65))
                    }.buttonStyle(.plain).accessibilityLabel("清空搜索").transition(.opacity)
                }
            }.padding(.horizontal, 7 * grid.scale)
        }
        .frame(width: grid.searchWidth, height: grid.searchHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: model.query.isEmpty)
        .contextMenu { settingsMenu }
    }
    @ViewBuilder private var settingsMenu: some View {
        Button("刷新应用列表", action: model.refresh)
        Button("添加其他位置的应用…", action: model.chooseApps)
        Button(model.editing ? "完成排列" : "编辑排列") { if model.editing { model.stopEditing() } else { model.enterEditing() } }
        Divider()
        Toggle("登录时启动", isOn: Binding(get: { model.launchAtLogin }, set: { _ in (NSApp.delegate as? AppDelegate)?.toggleLoginItem() }))
        Text("快捷键：⌃⌥空格")
        if !model.shortcutAvailable { Text("快捷键被其他软件占用") }
        Divider()
        Button("恢复默认排列…", action: model.sortApps)
        Button("退出 Launchpad Classic") { NSApp.terminate(nil) }
    }
    private func rootPages(_ grid: GridGeometry) -> some View {
        let entries = model.visibleEntries
        let count = grid.pageCount(for: entries.count)
        return HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                rootPage(index, entries: entries, grid: grid)
                    .frame(width: grid.width, height: grid.height)
                    .allowsHitTesting(index == model.page && !model.swipeInProgress)
                    .accessibilityHidden(index != model.page)
            }
        }
        .frame(width: Double(count) * grid.width, height: grid.height, alignment: .leading)
        .offset(x: -Double(model.page) * grid.width + model.swipeOffset)
        .frame(width: grid.width, height: grid.height, alignment: .leading).clipped()
        .animation(reduceMotion || model.swipeInProgress || model.searching ? nil : .launcherPage, value: model.page)
    }
    private func rootPage(_ page: Int, entries: [LaunchEntry], grid: GridGeometry) -> some View {
        let start = min(page * grid.capacity, entries.count), end = min((page + 1) * grid.capacity, entries.count)
        let tileHeight = grid.iconSize + grid.labelGap + grid.labelHeight
        let fullHeight = tileHeight + Double(grid.rows - 1) * grid.rowPitch
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.cellWidth), spacing: 0), count: grid.columns), spacing: grid.rowPitch - tileHeight) {
            ForEach(Array(entries[start..<end].enumerated()), id: \.element.id) { offset, entry in
                tile(entry, selected: model.keyboardSelection && model.selected == start + offset, grid: grid, folder: nil, visible: page == model.page)
                    .frame(width: grid.cellWidth - 12 * grid.scale, height: tileHeight)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ItemFrames.self, value: page == model.page ? [entry.id: geo.frame(in: .named("launcher"))] : [:])
                    })
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .frame(width: grid.gridWidth, height: fullHeight, alignment: .top)
        .position(x: grid.width / 2, y: grid.firstIconCenterY - grid.iconSize / 2 + fullHeight / 2)
        .animation(reduceMotion ? nil : .launcherReorder, value: entries.map(\.id))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: model.query)
    }
    private func tile(_ entry: LaunchEntry, selected: Bool, grid: GridGeometry, folder: String?, visible: Bool) -> some View {
        let candidate = model.dropTargetID == entry.id
        let ready = candidate && model.folderDropReady
        let lifted = model.dragging == entry.id
        let pressed = model.pressedID == entry.id
        return VStack(spacing: grid.labelGap) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !model.editing || !visible || reduceMotion)) { timeline in
                let phase = Double(abs(entry.id.hashValue % 13))
                let angle = model.editing && visible && !reduceMotion && !lifted ? sin(timeline.date.timeIntervalSinceReferenceDate * 30 + phase) * 1.15 : 0
                ZStack {
                    RoundedRectangle(cornerRadius: 16 * grid.scale)
                        .fill(.white.opacity(selected ? 0.20 : candidate ? 0.18 : 0))
                        .scaleEffect(ready ? 1.10 : 1)
                    if entry.isFolder || ready {
                        folderIcon(entry, includingDrag: ready && !entry.isFolder, grid: grid)
                    } else if let id = entry.appIDs.first {
                        Image(nsImage: model.icon(id)).resizable().aspectRatio(contentMode: .fit)
                    }
                }
                .frame(width: grid.iconSize, height: grid.iconSize)
                .rotationEffect(.degrees(angle))
            }
            .frame(width: grid.iconSize, height: grid.iconSize)
            Text(model.title(entry)).font(.system(size: grid.labelSize, weight: .regular)).foregroundStyle(.white)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity).frame(height: grid.labelHeight, alignment: .top)
                .shadow(color: .black.opacity(0.45), radius: 1.5 * grid.scale, y: grid.scale)
        }
        .scaleEffect(pressed && !reduceMotion ? 0.96 : 1)
        .opacity(lifted ? 0.25 : 1)
        .overlay(IconInteraction(model: model, entry: entry, folderID: folder, iconSize: grid.iconSize, isInteractive: visible && !model.swipeInProgress))
        .animation(reduceMotion ? nil : .easeOut(duration: 0.13), value: pressed)
        .animation(reduceMotion ? nil : .launcherReorder, value: ready)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: lifted)
        .accessibilityElement(children: .ignore).accessibilityLabel(model.title(entry)).accessibilityAddTraits(.isButton)
        .accessibilityAction { model.activate(entry) }.help(model.title(entry))
        .accessibilityHidden(!visible || model.folderID != folder)
    }
    private func folderIcon(_ entry: LaunchEntry, includingDrag: Bool, grid: GridGeometry) -> some View {
        let box = grid.iconSize * 0.835
        var ids = entry.appIDs.filter { model.appMap[$0] != nil }
        if includingDrag, let source = model.dragging, !ids.contains(source) { ids.append(source) }
        let shown = Array(ids.prefix(9))
        return ZStack {
            RoundedRectangle(cornerRadius: box * 0.22).fill(.white.opacity(0.38))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2 * grid.scale), count: 3), spacing: 2 * grid.scale) {
                ForEach(shown, id: \.self) { id in Image(nsImage: model.icon(id)).resizable().aspectRatio(contentMode: .fit) }
                ForEach(shown.count..<9, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
            }.padding(7 * grid.scale)
        }.frame(width: box, height: box).frame(width: grid.iconSize, height: grid.iconSize)
    }
    private func pageDots(count: Int, current: Int, scale: Double, select: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 10 * scale) {
            ForEach(0..<count, id: \.self) { page in
                Button { select(page) } label: {
                    Circle().fill(.white.opacity(current == page ? 1 : 0.32)).frame(width: 6 * scale, height: 6 * scale)
                        .frame(width: 10 * scale, height: 20 * scale).contentShape(Rectangle())
                }
                .buttonStyle(.plain).focusable(false).accessibilityLabel("第 \(page + 1) 页，共 \(count) 页")
                .accessibilityAddTraits(current == page ? .isSelected : [])
            }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: current)
    }
    private func folderOverlay(_ folder: LaunchEntry, grid: GridGeometry) -> some View {
        let count = model.folderApps.count
        let pages = max(1, (count + model.folderCapacity - 1) / model.folderCapacity)
        let rows = min(3, max(1, (min(count, model.folderCapacity) + 6) / 7))
        let height = Double(rows) * grid.rowPitch + 28 * grid.scale + (pages > 1 ? 24 * grid.scale : 0)
        let tileHeight = grid.iconSize + grid.labelGap + grid.labelHeight
        return ZStack {
            Color.black.opacity(0.08).contentShape(Rectangle()).onTapGesture {
                folderTitleFocused = false
                if model.editing { model.stopEditing() } else { closeFolder() }
            }.transition(.opacity)
            ZStack {
                TextField("文件夹", text: $folderName).textFieldStyle(.plain).font(.system(size: 24 * grid.scale, weight: .regular))
                    .multilineTextAlignment(.center).foregroundStyle(.white)
                    .frame(width: grid.gridWidth * 0.7, height: 40 * grid.scale)
                    .focused($folderTitleFocused).accessibilityLabel("文件夹名称")
                    .onSubmit { model.commitFolderName(folder.id, name: folderName); folderTitleFocused = false }
                    .onExitCommand { folderTitleFocused = false }
                    .position(x: grid.width / 2, y: grid.height / 2 - height / 2 - 34 * grid.scale)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 20 * grid.scale).fill(.white.opacity(0.24))
                        .overlay(RoundedRectangle(cornerRadius: 20 * grid.scale).strokeBorder(.white.opacity(0.10), lineWidth: 1))
                        .onTapGesture { folderTitleFocused = false; model.cancelFolderRename(); model.stopEditing() }
                    HStack(spacing: 0) {
                        ForEach(0..<pages, id: \.self) { page in
                            let start = min(page * model.folderCapacity, count), end = min((page + 1) * model.folderCapacity, count)
                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(grid.cellWidth), spacing: 0), count: 7), spacing: grid.rowPitch - tileHeight) {
                                ForEach(Array(model.folderApps[start..<end].enumerated()), id: \.element.id) { offset, app in
                                    tile(.app(app.id), selected: model.keyboardSelection && model.selected == start + offset, grid: grid, folder: folder.id, visible: page == model.folderPage)
                                        .frame(width: grid.cellWidth - 12 * grid.scale, height: tileHeight)
                                        .background(GeometryReader { geo in
                                            Color.clear.preference(key: ItemFrames.self, value: page == model.folderPage ? [app.id: geo.frame(in: .named("launcher"))] : [:])
                                        })
                                }
                            }
                            .padding(.top, 14 * grid.scale + (grid.rowPitch - tileHeight) / 2)
                            .frame(width: grid.gridWidth, height: height, alignment: .top)
                            .allowsHitTesting(page == model.folderPage && !model.swipeInProgress)
                            .accessibilityHidden(page != model.folderPage)
                        }
                    }
                    .frame(width: Double(pages) * grid.gridWidth, height: height, alignment: .leading)
                    .offset(x: -Double(model.folderPage) * grid.gridWidth + model.swipeOffset * 0.8)
                    .frame(width: grid.gridWidth, height: height, alignment: .leading).clipped()
                    .animation(reduceMotion || model.swipeInProgress ? nil : .launcherPage, value: model.folderPage)
                    .animation(reduceMotion ? nil : .launcherReorder, value: model.folderApps.map(\.id))
                    if pages > 1 {
                        pageDots(count: pages, current: model.folderPage, scale: grid.scale) { model.navigate(to: $0) }
                            .position(x: grid.gridWidth / 2, y: height - 18 * grid.scale)
                    }
                }
                .frame(width: grid.gridWidth, height: height)
                .background(GeometryReader { geo in Color.clear.preference(key: ItemFrames.self, value: ["__folderPanel": geo.frame(in: .named("launcher"))]) })
                .shadow(color: .black.opacity(0.08), radius: 12 * grid.scale, y: 6 * grid.scale)
                .position(x: grid.width / 2, y: grid.height / 2)
            }
            .frame(width: grid.width, height: grid.height)
            .transition(reduceMotion ? .opacity : .modifier(
                active: FolderExpansion(progress: 0, origin: model.folderOrigin, center: CGPoint(x: grid.width / 2, y: grid.height / 2), smallX: grid.iconSize * 0.835 / grid.gridWidth, smallY: grid.iconSize * 0.835 / height),
                identity: FolderExpansion(progress: 1, origin: model.folderOrigin, center: CGPoint(x: grid.width / 2, y: grid.height / 2), smallX: grid.iconSize * 0.835 / grid.gridWidth, smallY: grid.iconSize * 0.835 / height)))
        }
    }
    private func closeFolder() {
        if let id = model.folderID { model.commitFolderName(id, name: folderName) }
        model.closeFolder()
    }
    private func backgroundExclusions(_ grid: GridGeometry) -> [CGRect] {
        if model.folderID == nil {
            return [CGRect(x: (grid.width - grid.searchWidth) / 2 - 8, y: grid.searchCenterY - grid.searchHeight / 2 - 8, width: grid.searchWidth + 16, height: grid.searchHeight + 16),
                    CGRect(x: grid.width / 2 - Double(model.currentPageCount) * 10 * grid.scale, y: grid.pageCenterY - 14 * grid.scale, width: Double(model.currentPageCount) * 20 * grid.scale, height: 28 * grid.scale)]
        }
        let count = model.folderApps.count
        let pages = max(1, (count + model.folderCapacity - 1) / model.folderCapacity)
        let rows = min(3, max(1, (min(count, model.folderCapacity) + 6) / 7))
        let height = Double(rows) * grid.rowPitch + 28 * grid.scale + (pages > 1 ? 24 * grid.scale : 0)
        var rects = [CGRect(x: grid.width / 2 - grid.gridWidth * 0.35, y: grid.height / 2 - height / 2 - 54 * grid.scale, width: grid.gridWidth * 0.7, height: 40 * grid.scale)]
        if pages > 1 { rects.append(CGRect(x: grid.width / 2 - Double(pages) * 10 * grid.scale, y: grid.height / 2 + height / 2 - 32 * grid.scale, width: Double(pages) * 20 * grid.scale, height: 28 * grid.scale)) }
        return rects
    }
    private func updateGrid(_ grid: GridGeometry) {
        model.columns = grid.columns; model.capacity = grid.capacity
        model.pageWidth = grid.width; model.pageHeight = grid.height; model.iconCanvasSize = grid.iconSize
        let page = min(model.page, grid.pageCount(for: model.visibleEntries.count) - 1)
        if page != model.page { model.page = page }
        let selected = min(max(0, model.selected), max(0, model.visibleEntries.count - 1))
        if selected != model.selected { model.selected = selected }
    }
}

private struct FolderExpansion: AnimatableModifier {
    var progress: Double
    let origin: CGPoint
    let center: CGPoint
    let smallX: Double
    let smallY: Double
    var animatableData: Double { get { progress } set { progress = newValue } }
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: smallX + (1 - smallX) * progress, y: smallY + (1 - smallY) * progress)
            .offset(x: (origin.x - center.x) * (1 - progress), y: (origin.y - center.y) * (1 - progress))
            .opacity(progress)
    }
}

private struct DragGhost: View {
    @ObservedObject var visual: DragVisualState
    let size: Double
    var body: some View {
        GeometryReader { _ in
            if let image = visual.image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size).scaleEffect(visual.scale)
                    .shadow(color: .black.opacity(0.30), radius: 7, y: 5)
                    .opacity(visual.opacity).position(visual.point).transition(.opacity)
            }
        }
    }
}
