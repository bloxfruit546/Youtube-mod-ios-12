import Foundation

enum DataProviderError: LocalizedError {
    case invalidURL
    case networkError(String)
    case httpStatus(Int)
    case rateLimited
    case decodingError(String)
    case noPlayableH264Stream
    case allProvidersFailed([String])

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL không hợp lệ."
        case .networkError(let msg):
            return "Lỗi mạng: \(msg)"
        case .httpStatus(let code):
            return "Máy chủ trả về mã lỗi HTTP \(code)."
        case .rateLimited:
            return "Máy chủ giới hạn tần suất (HTTP 429)."
        case .decodingError(let msg):
            return "Lỗi đọc dữ liệu: \(msg)"
        case .noPlayableH264Stream:
            return "Không tìm thấy luồng H.264/HLS tương thích phần cứng Apple A7."
        case .allProvidersFailed(let details):
            return "Tất cả nguồn dữ liệu đều lỗi:\n" + details.joined(separator: "\n")
        }
    }
}

protocol YouTubeDataSourceProtocol {
    var providerName: String { get }

    func fetchTrending(region: String, completion: @escaping (Result<[VideoItem], Error>) -> Void)
    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void)
    func fetchSearchSuggestions(query: String, completion: @escaping (Result<[String], Error>) -> Void)
    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void)
    func fetchComments(videoId: String, completion: @escaping (Result<[CommentItem], Error>) -> Void)
    func fetchChannel(channelId: String, completion: @escaping (Result<ChannelItem, Error>) -> Void)
}

enum VideoFilter {
    /// Completely removes YouTube Shorts to protect iPhone 5s A7 RAM and UX.
    static func filterOutShorts(_ items: [VideoItem]) -> [VideoItem] {
        return items.filter { item in
            if item.isShort { return false }
            let lowerTitle = item.title.lowercased()
            if lowerTitle.contains("#shorts") { return false }
            return !item.id.isEmpty
        }
    }
}

enum YouTubeParsing {
    static func extractVideoId(from urlOrPath: String?) -> String? {
        guard let str = urlOrPath, !str.isEmpty else { return nil }
        if str.count == 11 && !str.contains("/") && !str.contains("?") {
            return str
        }
        if let range = str.range(of: "v=") {
            let sub = String(str[range.upperBound...])
            return sub.components(separatedBy: "&").first
        }
        if let range = str.range(of: "/watch/") {
            let sub = String(str[range.upperBound...])
            return sub.components(separatedBy: "?").first
        }
        if let range = str.range(of: "youtu.be/") {
            let sub = String(str[range.upperBound...])
            return sub.components(separatedBy: "?").first
        }
        return nil
    }

    static func extractChannelId(from urlOrPath: String?) -> String? {
        guard let str = urlOrPath, !str.isEmpty else { return nil }
        if str.hasPrefix("UC") && !str.contains("/") {
            return str
        }
        if let range = str.range(of: "/channel/") {
            let sub = String(str[range.upperBound...])
            return sub.components(separatedBy: "/").first?.components(separatedBy: "?").first
        }
        return str.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func parseHeight(from label: String?) -> Int {
        guard let label = label?.lowercased() else { return 0 }
        let digits = label.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        return Int(digits) ?? 0
    }

    static func parseDurationString(_ text: String?) -> Int {
        guard let text = text, !text.isEmpty else { return 0 }
        let parts = text.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: ":")
        let nums = parts.compactMap { Int($0) }
        guard nums.count == parts.count else { return 0 }
        if nums.count == 3 {
            return nums[0] * 3600 + nums[1] * 60 + nums[2]
        } else if nums.count == 2 {
            return nums[0] * 60 + nums[1]
        } else if nums.count == 1 {
            return nums[0]
        }
        return 0
    }

    static func parseInt64(_ any: Any?) -> Int64 {
        if let v = any as? Int64 { return v }
        if let v = any as? Int { return Int64(v) }
        if let v = any as? Double { return Int64(v) }
        if let s = any as? String {
            let digits = s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            return Int64(digits) ?? 0
        }
        return 0
    }
}
