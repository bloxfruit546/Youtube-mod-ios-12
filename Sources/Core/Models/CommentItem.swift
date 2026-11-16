import Foundation

struct CommentItem: Codable, Equatable {
    let id: String
    let authorName: String
    let authorAvatarURL: URL?
    let text: String
    let likeCount: Int
    let publishedText: String
    let replyCount: Int
    let isPinned: Bool
    let isHearted: Bool

    init(
        id: String,
        authorName: String,
        authorAvatarURL: URL? = nil,
        text: String,
        likeCount: Int = 0,
        publishedText: String = "",
        replyCount: Int = 0,
        isPinned: Bool = false,
        isHearted: Bool = false
    ) {
        self.id = id
        self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL
        self.text = text
        self.likeCount = likeCount
        self.publishedText = publishedText
        self.replyCount = replyCount
        self.isPinned = isPinned
        self.isHearted = isHearted
    }
}
