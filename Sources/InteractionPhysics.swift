import Foundation

// Calibration values for the classic Launchpad interaction model, not Apple constants.
enum MotionTiming {
    static let present = 0.28
    static let dismiss = 0.22
    static let page = 0.30
    static let folder = 0.32
    static let reorder = 0.22
    static let hold = 0.55
    static let folderHover = 0.50
    static let folderOpen = 0.95
    static let edgeHover = 0.65
}

struct PageSwipePhysics {
    static func displacement(_ raw: Double, page: Int, count: Int, width: Double) -> Double {
        guard width > 0 else { return 0 }
        if (page == 0 && raw > 0) || (page >= count - 1 && raw < 0) {
            return raw * 0.32 / (1 + abs(raw) / (width * 0.18))
        }
        return max(-width * 0.98, min(width * 0.98, raw))
    }
    static func destination(offset: Double, velocity: Double, page: Int, count: Int, width: Double, cancelled: Bool = false) -> Int {
        guard !cancelled, width > 0 else { return page }
        let projected = offset + max(-2400, min(2400, velocity)) * 0.16
        guard abs(offset) > width * 0.18 || (abs(offset) > 8 && abs(projected) > width * 0.22) else { return page }
        return max(0, min(max(0, count - 1), page + (projected < 0 ? 1 : -1)))
    }
}

extension LaunchLayout {
    mutating func insertAtRoot(_ appID: String, before targetID: String?) {
        if let current = entries.first(where: { $0.id == appID && !$0.isFolder }), current.appIDs == [appID] {
            if let targetID { move(appID, before: targetID) }
            else { entries.removeAll { $0.id == appID }; entries.append(current) }
            return
        }
        for index in entries.indices { entries[index].appIDs.removeAll { $0 == appID } }
        entries.removeAll { $0.appIDs.isEmpty }
        let entry = LaunchEntry.app(appID)
        if let targetID, let index = entries.firstIndex(where: { $0.id == targetID }) { entries.insert(entry, at: index) }
        else { entries.append(entry) }
    }
    mutating func moveInsideFolder(_ appID: String, before targetID: String?, folderID: String) {
        guard entries.contains(where: { $0.id == folderID && $0.isFolder }) else { return }
        if entries.first(where: { $0.id == folderID })?.appIDs.contains(appID) != true { place(appID, in: folderID) }
        guard let index = entries.firstIndex(where: { $0.id == folderID }), appID != targetID else { return }
        entries[index].appIDs.removeAll { $0 == appID }
        if let targetID, let to = entries[index].appIDs.firstIndex(of: targetID) { entries[index].appIDs.insert(appID, at: to) }
        else { entries[index].appIDs.append(appID) }
    }
}
