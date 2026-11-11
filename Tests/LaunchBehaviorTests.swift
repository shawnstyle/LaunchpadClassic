import Foundation

@main
struct LaunchBehaviorTests {
    @MainActor static func main() async {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            precondition(condition(), message)
        }
        var events: [String] = []
        var completion: ((Error?) -> Void)?
        var openedURL: URL?
        let model = LauncherModel(openApplication: { url, callback in
            events.append("open")
            openedURL = url
            completion = callback
        })
        model.dismiss = { events.append("hide") }
        let app = AppRecord(path: "/Applications/Example.app", name: "示例应用")
        model.apps = [app]

        // No completion yet: the launcher must already have yielded the screen.
        model.launch(app)
        check(events == ["hide", "open"], "启动前立即收起，不等待系统回调")
        check(openedURL == app.url, "传入正确的应用 URL")
        check(completion != nil, "系统启动请求已提交")
        events.append("reopen")
        completion?(nil)
        await drainMainQueue()
        check(events == ["hide", "open", "reopen"], "延迟成功回调不关闭新打开的启动器")
        check(model.error == nil, "成功不产生错误")

        var presentedError: String?
        model.presentLaunchError = { presentedError = $0; events.append("show-error") }
        model.launch(app)
        completion?(NSError(domain: "LaunchTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "应用不可用"]))
        await drainMainQueue()
        check(presentedError?.contains("示例应用") == true, "失败提示包含应用名称")
        check(presentedError?.contains("应用不可用") == true, "失败提示包含系统错误")
        check(events.suffix(3) == ["hide", "open", "show-error"], "启动失败后恢复错误界面")

        let beforeFolder = events.count
        let folder = LaunchEntry(id: "folder", folderName: "工具", appIDs: [app.id])
        model.layout = LaunchLayout(entries: [folder])
        model.activate(folder)
        check(model.folderID == folder.id, "点击文件夹仍然展开")
        check(events.count == beforeFolder, "点击文件夹不收起也不启动应用")

        model.activate(.app(app.id))
        check(events.suffix(2) == ["hide", "open"], "搜索、文件夹与键盘共用立即收起路径")
        print("通过 \(checks) 项启动行为检查")
    }

    static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }
}
