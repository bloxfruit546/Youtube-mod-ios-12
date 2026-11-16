import Foundation

struct PlaylistItem: Codable, Equatable {
    let id: String
    var title: String
    var videos: [VideoItem]
    let createdAt: Date

    init(id: String = UUID().uuidString, title: String, videos: [VideoItem] = [], createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.videos = videos
        self.createdAt = createdAt
    }
}

struct SubscribedChannel: Codable, Equatable {
    let id: String
    var name: String
    var avatarURL: URL?
    let subscribedAt: Date

    init(id: String, name: String, avatarURL: URL? = nil, subscribedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.subscribedAt = subscribedAt
    }
}

struct WatchHistoryEntry: Codable, Equatable {
    let video: VideoItem
    var watchedAt: Date
    var lastPositionSeconds: Double

    init(video: VideoItem, watchedAt: Date = Date(), lastPositionSeconds: Double = 0) {
        self.video = video
        self.watchedAt = watchedAt
        self.lastPositionSeconds = lastPositionSeconds
    }
}
