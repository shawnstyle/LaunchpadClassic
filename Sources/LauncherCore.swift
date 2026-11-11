import Foundation

struct AppRecord: Identifiable, Equatable {
    let id: String
    let name: String
    let bundleID: String
    let searchKey: String
    var url: URL { URL(fileURLWithPath: id) }

    init(path: String, name: String, bundleID: String = "", aliases: [String] = []) {
        self.id = path
        self.name = name
        self.bundleID = bundleID
        let names = [name, URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent] + aliases
        let searchTerms = names.flatMap { value -> [String] in
            let latin = value.applyingTransform(.toLatin, reverse: false) ?? value
            let syllables = latin.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let initials = syllables.compactMap(\.first).map(String.init).joined()
            return [value, latin, initials]
        }
        self.searchKey = Self.fold((searchTerms + [bundleID]).joined(separator: " "))
    }

    static func fold(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }

    func matches(_ query: String) -> Bool {
        let words = Self.fold(query).split(whereSeparator: { $0.isWhitespace })
        let compact = searchKey.replacingOccurrences(of: " ", with: "")
        return words.allSatisfy { searchKey.contains($0) || compact.contains($0) }
    }
}

struct LaunchEntry: Identifiable, Codable, Equatable {
    var id: String
    var folderName: String?
    var appIDs: [String]
    var isFolder: Bool { folderName != nil }
    static func app(_ id: String) -> LaunchEntry { LaunchEntry(id: id, appIDs: [id]) }
}

struct LaunchLayout: Codable, Equatable {
    var entries: [LaunchEntry] = []

    mutating func reconcile(with appIDs: [String]) {
        // Retain unavailable apps so a temporarily unmounted volume doesn't erase its layout.
        var seen = Set<String>()
        entries = entries.compactMap { entry in
            var result = entry
            result.appIDs = entry.appIDs.filter { seen.insert($0).inserted }
            return result.appIDs.isEmpty ? nil : result
        }
        for id in appIDs where seen.insert(id).inserted { entries.append(.app(id)) }
    }

    mutating func place(_ appID: String, in folderID: String) {
        guard let target = entries.first(where: { $0.id == folderID }), target.isFolder,
              !target.appIDs.contains(appID) else { return }
        remove(appID)
        guard let index = entries.firstIndex(where: { $0.id == folderID }) else { return }
        entries[index].appIDs.append(appID)
    }

    mutating func group(_ sourceID: String, with targetID: String) {
        guard sourceID != targetID,
              entries.contains(where: { !$0.isFolder && $0.appIDs == [targetID] }) else { return }
        remove(sourceID)
        guard let index = entries.firstIndex(where: { !$0.isFolder && $0.appIDs == [targetID] }) else { return }
        entries[index] = LaunchEntry(id: UUID().uuidString, folderName: "新建文件夹", appIDs: [targetID, sourceID])
    }

    mutating func ungroup(_ appID: String) {
        remove(appID)
        entries.append(.app(appID))
    }

    mutating func move(_ entryID: String, before targetID: String) {
        guard entryID != targetID, let from = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let item = entries.remove(at: from)
        if let to = entries.firstIndex(where: { $0.id == targetID }) { entries.insert(item, at: to) }
        else { entries.append(item) }
    }

    private mutating func remove(_ appID: String) {
        for index in entries.indices { entries[index].appIDs.removeAll { $0 == appID } }
        entries.removeAll { $0.appIDs.isEmpty }
    }
}

// Proportions measured from Apple's Sequoia Launchpad reference image.
// All values are logical points; Retina scaling is left to AppKit.
struct GridGeometry: Equatable {
    let width: Double
    let height: Double
    let columns = 7
    let rows = 5
    var capacity: Int { columns * rows }
    var scale: Double { max(0.5, min(1.5, min(width / 1512, height / 982))) }
    var gridWidth: Double { width * 0.80 }
    var cellWidth: Double { gridWidth / Double(columns) }
    var iconSize: Double { 96 * scale }
    var labelSize: Double { 13 * scale }
    var labelHeight: Double { 19 * scale }
    var labelGap: Double { 3 * scale }
    var searchWidth: Double { 250 * scale }
    var searchHeight: Double { 26 * scale }
    var searchCenterY: Double { height * 0.067 }
    var firstIconCenterY: Double { height * 0.154 }
    var rowPitch: Double { height * 0.151 }
    var pageCenterY: Double { height * 0.878 }
    init(width: Double, height: Double) { self.width = width; self.height = height }
    func pageCount(for count: Int) -> Int { max(1, (count + capacity - 1) / capacity) }
}

struct AppScanner {
    private static func localizedAliases(_ bundle: Bundle) -> [String] {
        guard let resources = bundle.resourceURL else { return [] }
        func dictionary(_ url: URL) -> [String: Any] {
            guard let data = try? Data(contentsOf: url),
                  let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return [:] }
            return plist
        }
        func names(_ dictionary: [String: Any]) -> [String] {
            [dictionary["CFBundleDisplayName"], dictionary["CFBundleName"]].compactMap { $0 as? String }
        }
        var aliases: [String] = []
        for language in ["zh-Hans", "zh_CN", "zh-Hant", "zh_TW", "en", "English"] {
            aliases += names(dictionary(resources.appendingPathComponent("\(language).lproj/InfoPlist.strings")))
        }
        let table = dictionary(resources.appendingPathComponent("InfoPlist.loctable"))
        for (language, value) in table where language.hasPrefix("zh") || language.hasPrefix("en") {
            if let values = value as? [String: Any] { aliases += names(values) }
        }
        return Array(Set(aliases))
    }

    static func scan(extraPaths: [String] = []) -> [AppRecord] {
        let fm = FileManager.default
        let roots = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                     "/Applications", "/System/Applications", "/System/Library/CoreServices/Applications",
                     "/System/Cryptexes/App/System/Applications"]
        var urls: [URL] = extraPaths.map { URL(fileURLWithPath: $0) }
        for root in roots {
            guard let walker = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey],
                                              options: [.skipsHiddenFiles]) else { continue }
            while let url = walker.nextObject() as? URL {
                if url.pathExtension.lowercased() == "app" {
                    urls.append(url)
                    walker.skipDescendants()
                } else if (try? url.resourceValues(forKeys: [.isPackageKey]).isPackage) == true {
                    walker.skipDescendants()
                }
            }
        }
        let launcherIdentifier = Bundle.main.bundleIdentifier ?? "org.launchpadclassic.app"
        var seenPaths = Set<String>(), seenIDs = Set<String>()
        var apps: [AppRecord] = []
        for candidate in urls {
            let url = candidate.standardizedFileURL.resolvingSymlinksInPath()
            guard fm.fileExists(atPath: url.path), seenPaths.insert(url.path).inserted,
                  let bundle = Bundle(url: url) else { continue }
            let identifier = bundle.bundleIdentifier ?? url.path
            guard identifier != launcherIdentifier, seenIDs.insert(identifier).inserted else { continue }
            let localized = bundle.localizedInfoDictionary ?? [:]
            let info = bundle.infoDictionary ?? [:]
            let name = (localized["CFBundleDisplayName"] as? String)
                ?? (localized["CFBundleName"] as? String)
                ?? (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? candidate.deletingPathExtension().lastPathComponent
            apps.append(AppRecord(path: url.path, name: name, bundleID: identifier, aliases: localizedAliases(bundle)))
        }
        return apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
