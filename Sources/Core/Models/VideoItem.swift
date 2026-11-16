import Foundation

struct VideoItem: Codable, Equatable {
    let id: String
    let title: String
    let channelId: String
    let channelName: String
    let channelAvatarURL: URL?
    let thumbnailURL: URL?
    let durationSeconds: Int
    let viewCount: Int64
    let uploadedText: String
    let isLive: Bool
    let isShort: Bool
    let descriptionText: String?

    init(
        id: String,
        title: String,
        channelId: String,
        channelName: String,
        channelAvatarURL: URL? = nil,
        thumbnailURL: URL? = nil,
        durationSeconds: Int = 0,
        viewCount: Int64 = 0,
        uploadedText: String = "",
        isLive: Bool = false,
        isShort: Bool = false,
        descriptionText: String? = nil
    ) {
        self.id = id
        self.title = title
        self.channelId = channelId
        self.channelName = channelName
        self.channelAvatarURL = channelAvatarURL
        self.thumbnailURL = thumbnailURL ?? VideoItem.defaultThumbnailURL(for: id)
        self.durationSeconds = durationSeconds
        self.viewCount = viewCount
        self.uploadedText = uploadedText
        self.isLive = isLive
        self.isShort = isShort
        self.descriptionText = descriptionText
    }

    /// Always prefer mqdefault (320x180) for iPhone 5s 4-inch Retina display & 1GB RAM budget.
    static func defaultThumbnailURL(for videoId: String) -> URL? {
        guard !videoId.isEmpty else { return nil }
        return URL(string: "https://i.ytimg.com/vi/\(videoId)/mqdefault.jpg")
    }

    var formattedDuration: String {
        if isLive {
            return "TRỰC TIẾP"
        }
        guard durationSeconds > 0 else { return "" }
        let hours = durationSeconds / 3600
        let minutes = (durationSeconds % 3600) / 60
        let seconds = durationSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedViews: String {
        if viewCount <= 0 {
            return isLive ? "Đang phát trực tiếp" : ""
        }
        if viewCount >= 1_000_000_000 {
            return String(format: "%.1f T lượt xem", Double(viewCount) / 1_000_000_000.0)
        } else if viewCount >= 1_000_000 {
            return String(format: "%.1f Tr lượt xem", Double(viewCount) / 1_000_000.0)
        } else if viewCount >= 1_000 {
            return String(format: "%.0f N lượt xem", Double(viewCount) / 1_000.0)
        }
        return "\(viewCount) lượt xem"
    }

    var metadataLine: String {
        var parts: [String] = []
        if !channelName.isEmpty {
            parts.append(channelName)
        }
        let views = formattedViews
        if !views.isEmpty {
            parts.append(views)
        }
        if !uploadedText.isEmpty {
            parts.append(uploadedText)
        }
        return parts.joined(separator: " • ")
    }
}
