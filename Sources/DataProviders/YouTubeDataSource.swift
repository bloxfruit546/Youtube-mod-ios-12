import Foundation

enum DataProviderError: LocalizedError {
    case invalidURL
    case networkError(String)
    case httpStatus(Int)
    case rateLimited
    case decodingError(String)
    case noPlayableH264Stream
    case terminalUnplayable(String)
    case providerDetail(provider: String, detail: String)
    case allProvidersFailed([String])

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL không hợp lệ."
        case .networkError(let msg):
            return "Lỗi mạng: \(msg)"
        case .httpStatus(let code):
            return "HTTP \(code)"
        case .rateLimited:
            return "HTTP 429 (Rate Limit)"
        case .decodingError(let msg):
            return "DecodingError: \(msg)"
        case .noPlayableH264Stream:
            return "Không tìm thấy luồng H.264/HLS tương thích A7"
        case .terminalUnplayable(let reason):
            return reason
        case .providerDetail(let provider, let detail):
            return "\(provider): \(detail)"
        case .allProvidersFailed(let details):
            return details.joined(separator: " | ")
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
    /// Extracts a clean 11-character YouTube video ID from raw IDs, `/watch?v=...`, `youtu.be/...`, `/shorts/...`, etc.
    static func extractCleanVideoId(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !str.isEmpty else { return "" }

        if let hashIdx = str.firstIndex(of: "#") {
            str = String(str[..<hashIdx])
        }

        // Handle query parameter `v=` (e.g. `/watch?v=XXXXXXXXXXX&list=...` or `https://youtube.com/watch?v=...`)
        if let vRange = str.range(of: "v=") {
            let afterV = String(str[vRange.upperBound...])
            let clean = afterV.components(separatedBy: CharacterSet(charactersIn: "&/?#")).first ?? ""
            if clean.count == 11 {
                return clean
            }
            if !clean.isEmpty {
                return String(clean.prefix(11))
            }
        }

        // Handle path-based URLs: `youtu.be/ID`, `/shorts/ID`, `/embed/ID`, `/live/ID`, `/watch/ID`
        for marker in ["youtu.be/", "/shorts/", "/embed/", "/live/", "/watch/", "/v/"] {
            if let range = str.range(of: marker) {
                let after = String(str[range.upperBound...])
                let clean = after.components(separatedBy: CharacterSet(charactersIn: "?&/#")).first ?? ""
                if !clean.isEmpty {
                    return clean.count >= 11 ? String(clean.prefix(11)) : clean
                }
            }
        }

        // Strip any trailing query string if already an ID
        let stripped = str.components(separatedBy: CharacterSet(charactersIn: "?&/#")).first ?? str
        if stripped.count == 11 {
            return stripped
        }
        return stripped
    }

    static func extractVideoId(from urlOrPath: String?) -> String? {
        guard let str = urlOrPath, !str.isEmpty else { return nil }
        let clean = extractCleanVideoId(str)
        return clean.isEmpty ? nil : clean
    }

    static func extractChannelId(from urlOrPath: String?) -> String? {
        guard let str = urlOrPath, !str.isEmpty else { return nil }
        if str.hasPrefix("UC") && !str.contains("/") && !str.contains("?") {
            return str
        }
        if let range = str.range(of: "/channel/") {
            let sub = String(str[range.upperBound...])
            return sub.components(separatedBy: CharacterSet(charactersIn: "/?&")).first
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
