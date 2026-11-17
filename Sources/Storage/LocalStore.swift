import Foundation

extension Notification.Name {
    static let subscriptionsDidChange = Notification.Name("com.litetube5s.subscriptionsDidChange")
    static let historyDidChange = Notification.Name("com.litetube5s.historyDidChange")
    static let playlistsDidChange = Notification.Name("com.litetube5s.playlistsDidChange")
    static let settingsDidChange = Notification.Name("com.litetube5s.settingsDidChange")
}

enum PreferredProvider: String, Codable, CaseIterable {
    case autoPipedFirst = "piped"
    case invidiousFirst = "invidious"
    case innertubeFirst = "innertube"

    var displayName: String {
        switch self {
        case .autoPipedFirst: return "Piped -> Invidious -> Innertube"
        case .invidiousFirst: return "Invidious -> Piped -> Innertube"
        case .innertubeFirst: return "Innertube -> Piped -> Invidious"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var maxQuality: MaxVideoQuality
    var audioOnlyDefault: Bool
    var regionCode: String
    var preferredProvider: PreferredProvider
    var pipedInstances: [String]
    var invidiousInstances: [String]
    var remoteConfigURL: String
    var instancesVersion: Int?

    static let currentInstancesVersion = 3

    static let defaultPipedInstances: [String] = [
        "https://pipedapi.nosebs.ru",
        "https://pipedapi.adminforge.de",
        "https://pipedapi.drgns.space",
        "https://api.piped.private.coffee"
    ]

    static let defaultInvidiousInstances: [String] = [
        "https://inv.nadeko.net",
        "https://yewtu.be",
        "https://invidious.nerdvpn.de",
        "https://iv.datura.network"
    ]

    static var `default`: AppSettings {
        return AppSettings(
            maxQuality: .p480,
            audioOnlyDefault: false,
            regionCode: "VN",
            preferredProvider: .autoPipedFirst,
            pipedInstances: defaultPipedInstances,
            invidiousInstances: defaultInvidiousInstances,
            remoteConfigURL: "",
            instancesVersion: currentInstancesVersion
        )
    }
}

final class LocalStore {
    static let shared = LocalStore()

    private let queue = DispatchQueue(label: "com.litetube5s.localstore")
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    let storageDirectory: URL
    private let subscriptionsURL: URL
    private let historyURL: URL
    private let playlistsURL: URL
    private let settingsURL: URL
    private let searchHistoryURL: URL

    private var subscriptionsCache: [SubscribedChannel] = []
    private var historyCache: [WatchHistoryEntry] = []
    private var playlistsCache: [PlaylistItem] = []
    private var settingsCache: AppSettings = .default
    private var searchHistoryCache: [String] = []

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.storageDirectory = docs.appendingPathComponent("LiteTube5s", isDirectory: true)
        self.subscriptionsURL = storageDirectory.appendingPathComponent("subscriptions.json")
        self.historyURL = storageDirectory.appendingPathComponent("history.json")
        self.playlistsURL = storageDirectory.appendingPathComponent("playlists.json")
        self.settingsURL = storageDirectory.appendingPathComponent("settings.json")
        self.searchHistoryURL = storageDirectory.appendingPathComponent("searches.json")

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true, attributes: nil)
        loadAllFromDisk()
    }

    private func loadAllFromDisk() {
        queue.sync {
            subscriptionsCache = readJSON([SubscribedChannel].self, from: subscriptionsURL) ?? []
            historyCache = readJSON([WatchHistoryEntry].self, from: historyURL) ?? []
            playlistsCache = readJSON([PlaylistItem].self, from: playlistsURL) ?? [
                PlaylistItem(id: "watch_later", title: "Xem sau", videos: [])
            ]
            if playlistsCache.isEmpty {
                playlistsCache = [PlaylistItem(id: "watch_later", title: "Xem sau", videos: [])]
            }
            settingsCache = readJSON(AppSettings.self, from: settingsURL) ?? .default
            if (settingsCache.instancesVersion ?? 0) < AppSettings.currentInstancesVersion {
                settingsCache.pipedInstances = AppSettings.defaultPipedInstances
                settingsCache.invidiousInstances = AppSettings.defaultInvidiousInstances
                settingsCache.instancesVersion = AppSettings.currentInstancesVersion
                writeAtomic(settingsCache, to: settingsURL)
            }
            searchHistoryCache = readJSON([String].self, from: searchHistoryURL) ?? []
        }
    }

    private func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func writeAtomic<T: Encodable>(_ value: T, to url: URL) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            AppLogger.shared.error("LocalStore write failed (\(url.lastPathComponent)): \(error.localizedDescription)")
        }
    }

    // MARK: - Settings

    var settings: AppSettings {
        return queue.sync { settingsCache }
    }

    func updateSettings(_ block: (inout AppSettings) -> Void) {
        queue.sync {
            block(&settingsCache)
            writeAtomic(settingsCache, to: settingsURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .settingsDidChange, object: self)
        }
    }

    // MARK: - Subscriptions

    func getSubscriptions() -> [SubscribedChannel] {
        return queue.sync { subscriptionsCache }
    }

    func isSubscribed(channelId: String) -> Bool {
        return queue.sync {
            subscriptionsCache.contains(where: { $0.id == channelId })
        }
    }

    func subscribe(channel: SubscribedChannel) {
        queue.sync {
            if !subscriptionsCache.contains(where: { $0.id == channel.id }) {
                subscriptionsCache.insert(channel, at: 0)
                writeAtomic(subscriptionsCache, to: subscriptionsURL)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .subscriptionsDidChange, object: self)
        }
    }

    func unsubscribe(channelId: String) {
        queue.sync {
            subscriptionsCache.removeAll { $0.id == channelId }
            writeAtomic(subscriptionsCache, to: subscriptionsURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .subscriptionsDidChange, object: self)
        }
    }

    func toggleSubscription(channelId: String, name: String, avatarURL: URL?) -> Bool {
        if isSubscribed(channelId: channelId) {
            unsubscribe(channelId: channelId)
            return false
        } else {
            subscribe(channel: SubscribedChannel(id: channelId, name: name, avatarURL: avatarURL))
            return true
        }
    }

    /// Supports Google Takeout subscriptions.json or subscriptions.csv
    func importSubscriptions(from fileURL: URL) -> Result<Int, Error> {
        let didStartAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var imported: [SubscribedChannel] = []

            if fileURL.pathExtension.lowercased() == "csv" {
                imported = parseTakeoutCSV(data: data)
            } else {
                imported = parseTakeoutJSON(data: data)
                if imported.isEmpty {
                    imported = parseTakeoutCSV(data: data)
                }
            }

            guard !imported.isEmpty else {
                return .failure(DataProviderError.decodingError("Không tìm thấy kênh hợp lệ trong file JSON/CSV."))
            }

            var addedCount = 0
            queue.sync {
                for ch in imported {
                    if !subscriptionsCache.contains(where: { $0.id == ch.id }) {
                        subscriptionsCache.append(ch)
                        addedCount += 1
                    }
                }
                writeAtomic(subscriptionsCache, to: subscriptionsURL)
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .subscriptionsDidChange, object: self)
            }
            AppLogger.shared.info("Imported \(addedCount) subscriptions from \(fileURL.lastPathComponent)")
            return .success(addedCount)
        } catch {
            AppLogger.shared.error("Import subscriptions failed: \(error.localizedDescription)")
            return .failure(error)
        }
    }

    private func parseTakeoutJSON(data: Data) -> [SubscribedChannel] {
        // Check LiteTube5s backup format first
        if let direct = try? decoder.decode([SubscribedChannel].self, from: data), !direct.isEmpty {
            return direct
        }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) else {
            return []
        }

        var result: [SubscribedChannel] = []
        let items: [[String: Any]]
        if let arr = json as? [[String: Any]] {
            items = arr
        } else if let dict = json as? [String: Any], let subs = dict["subscriptions"] as? [[String: Any]] {
            items = subs
        } else {
            return []
        }

        for item in items {
            // Google Takeout YouTube JSON format: snippet.resourceId.channelId + snippet.title
            if let snippet = item["snippet"] as? [String: Any] {
                let title = (snippet["title"] as? String) ?? "Kênh YouTube"
                let res = snippet["resourceId"] as? [String: Any]
                if let channelId = res?["channelId"] as? String, !channelId.isEmpty {
                    result.append(SubscribedChannel(id: channelId, name: title))
                }
            } else if let urlStr = item["url"] as? String,
                      let chId = extractChannelId(from: urlStr) {
                let title = (item["name"] as? String) ?? (item["title"] as? String) ?? "Kênh YouTube"
                result.append(SubscribedChannel(id: chId, name: title))
            } else if let chId = (item["channelId"] as? String) ?? (item["id"] as? String), chId.hasPrefix("UC") {
                let title = (item["name"] as? String) ?? (item["title"] as? String) ?? "Kênh YouTube"
                result.append(SubscribedChannel(id: chId, name: title))
            }
        }
        return result
    }

    private func parseTakeoutCSV(data: Data) -> [SubscribedChannel] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var result: [SubscribedChannel] = []
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.lowercased().hasPrefix("channel id") { continue }
            let cols = splitCSVLine(trimmed)
            if cols.count >= 3 {
                let chId = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cols[2].trimmingCharacters(in: .whitespacesAndNewlines)
                if chId.hasPrefix("UC") {
                    result.append(SubscribedChannel(id: chId, name: title.isEmpty ? chId : title))
                }
            } else if cols.count == 2 {
                let chId = cols[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let title = cols[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if chId.hasPrefix("UC") {
                    result.append(SubscribedChannel(id: chId, name: title.isEmpty ? chId : title))
                }
            }
        }
        return result
    }

    private func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }

    private func extractChannelId(from urlString: String) -> String? {
        if let range = urlString.range(of: "/channel/") {
            let sub = String(urlString[range.upperBound...])
            return sub.components(separatedBy: "/").first
        }
        return nil
    }

    // MARK: - Watch History

    func getHistory() -> [WatchHistoryEntry] {
        return queue.sync { historyCache }
    }

    func savedPosition(for videoId: String) -> Double {
        return queue.sync {
            historyCache.first(where: { $0.video.id == videoId })?.lastPositionSeconds ?? 0
        }
    }

    func recordHistory(video: VideoItem, positionSeconds: Double) {
        queue.sync {
            historyCache.removeAll { $0.video.id == video.id }
            historyCache.insert(WatchHistoryEntry(video: video, watchedAt: Date(), lastPositionSeconds: positionSeconds), at: 0)
            if historyCache.count > 200 {
                historyCache = Array(historyCache.prefix(200))
            }
            writeAtomic(historyCache, to: historyURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyDidChange, object: self)
        }
    }

    func clearHistory() {
        queue.sync {
            historyCache.removeAll()
            writeAtomic(historyCache, to: historyURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyDidChange, object: self)
        }
    }

    // MARK: - Playlists

    func getPlaylists() -> [PlaylistItem] {
        return queue.sync { playlistsCache }
    }

    func isInWatchLater(videoId: String) -> Bool {
        return queue.sync {
            playlistsCache.first(where: { $0.id == "watch_later" })?.videos.contains(where: { $0.id == videoId }) ?? false
        }
    }

    func toggleWatchLater(video: VideoItem) -> Bool {
        var added = false
        queue.sync {
            if let idx = playlistsCache.firstIndex(where: { $0.id == "watch_later" }) {
                if let vIdx = playlistsCache[idx].videos.firstIndex(where: { $0.id == video.id }) {
                    playlistsCache[idx].videos.remove(at: vIdx)
                    added = false
                } else {
                    playlistsCache[idx].videos.insert(video, at: 0)
                    added = true
                }
            } else {
                playlistsCache.insert(PlaylistItem(id: "watch_later", title: "Xem sau", videos: [video]), at: 0)
                added = true
            }
            writeAtomic(playlistsCache, to: playlistsURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playlistsDidChange, object: self)
        }
        return added
    }

    func createPlaylist(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.sync {
            playlistsCache.append(PlaylistItem(title: trimmed))
            writeAtomic(playlistsCache, to: playlistsURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playlistsDidChange, object: self)
        }
    }

    func addVideo(_ video: VideoItem, toPlaylistId playlistId: String) {
        queue.sync {
            guard let idx = playlistsCache.firstIndex(where: { $0.id == playlistId }) else { return }
            if !playlistsCache[idx].videos.contains(where: { $0.id == video.id }) {
                playlistsCache[idx].videos.insert(video, at: 0)
                writeAtomic(playlistsCache, to: playlistsURL)
            }
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playlistsDidChange, object: self)
        }
    }

    func removeVideo(videoId: String, fromPlaylistId playlistId: String) {
        queue.sync {
            guard let idx = playlistsCache.firstIndex(where: { $0.id == playlistId }) else { return }
            playlistsCache[idx].videos.removeAll { $0.id == videoId }
            writeAtomic(playlistsCache, to: playlistsURL)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .playlistsDidChange, object: self)
        }
    }

    // MARK: - Recent Searches

    func getRecentSearches() -> [String] {
        return queue.sync { searchHistoryCache }
    }

    func addSearchQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        queue.sync {
            searchHistoryCache.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
            searchHistoryCache.insert(trimmed, at: 0)
            if searchHistoryCache.count > 20 {
                searchHistoryCache = Array(searchHistoryCache.prefix(20))
            }
            writeAtomic(searchHistoryCache, to: searchHistoryURL)
        }
    }

    func clearSearchHistory() {
        queue.sync {
            searchHistoryCache.removeAll()
            writeAtomic(searchHistoryCache, to: searchHistoryURL)
        }
    }
}
