import Foundation

struct ChannelItem: Codable, Equatable {
    let id: String
    let name: String
    let avatarURL: URL?
    let bannerURL: URL?
    let subscriberCountText: String
    let descriptionText: String
    let isVerified: Bool
    let videos: [VideoItem]

    init(
        id: String,
        name: String,
        avatarURL: URL? = nil,
        bannerURL: URL? = nil,
        subscriberCountText: String = "",
        descriptionText: String = "",
        isVerified: Bool = false,
        videos: [VideoItem] = []
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.bannerURL = bannerURL
        self.subscriberCountText = subscriberCountText
        self.descriptionText = descriptionText
        self.isVerified = isVerified
        self.videos = videos
    }
}
