import Foundation

/// Direct Innertube (youtubei/v1) emergency fallback provider.
/// Uses iOS & Web client contexts to retrieve HLS manifests and H.264/AAC (Itag 18 / 140)
/// when public Piped and Invidious instances are down or rate-limited.
final class InnertubeProvider: YouTubeDataSourceProtocol {
    let providerName = "Innertube (Direct)"

    private let baseAPI = "https://www.youtube.com/youtubei/v1"

    private func webContext(region: String) -> [String: Any] {
        return [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20240726.00.00",
                "hl": "vi",
                "gl": region
            ]
        ]
    }

    private func iosContext(region: String) -> [String: Any] {
        return [
            "client": [
                "clientName": "IOS",
                "clientVersion": "19.29.1",
                "deviceMake": "Apple",
                "deviceModel": "iPhone6,2",
                "osName": "iOS",
                "osVersion": "12.5.8",
                "hl": "vi",
                "gl": region
            ]
        ]
    }

    private func postInnertube(
        endpoint: String,
        payload: [String: Any],
        userAgent: String? = nil,
        completion: @escaping (Result<[String: Any], Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseAPI)/\(endpoint)?prettyPrint=false") else {
            completion(.failure(DataProviderError.invalidURL))
            return
        }
        guard let body = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            completion(.failure(DataProviderError.decodingError("Không thể mã hóa payload Innertube")))
            return
        }
        var headers = ["Content-Type": "application/json"]
        if let ua = userAgent {
            headers["User-Agent"] = ua
        }
        HTTPClient.shared.requestJSONObject(url: url, method: "POST", headers: headers, body: body, timeout: 6.0) { result in
            switch result {
            case .success(let obj):
                if let dict = obj as? [String: Any] {
                    completion(.success(dict))
                } else {
                    completion(.failure(DataProviderError.decodingError("Innertube không trả về object")))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchTrending(region: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "browseId": "FEtrending"
        ]
        postInnertube(endpoint: "browse", payload: payload) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let dict):
                var items: [VideoItem] = []
                self.collectVideoRenderers(in: dict, into: &items)
                completion(.success(VideoFilter.filterOutShorts(items)))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let region = LocalStore.shared.settings.regionCode
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "query": query,
            "params": "EgIQAQ==" // Videos only filter
        ]
        postInnertube(endpoint: "search", payload: payload) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let dict):
                var items: [VideoItem] = []
                self.collectVideoRenderers(in: dict, into: &items)
                completion(.success(VideoFilter.filterOutShorts(items)))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchSearchSuggestions(query: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=\(q)") else {
            completion(.success([]))
            return
        }
        HTTPClient.shared.requestJSONObject(url: url, timeout: 4.0) { result in
            switch result {
            case .success(let obj):
                if let arr = obj as? [Any], arr.count > 1, let suggestions = arr[1] as? [String] {
                    completion(.success(suggestions))
                } else {
                    completion(.success([]))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void) {
        let region = LocalStore.shared.settings.regionCode
        let payload: [String: Any] = [
            "context": iosContext(region: region),
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true
        ]
        let iosUA = "com.google.ios.youtube/19.29.1 (iPhone6,2; U; CPU iOS 12_5_8 like Mac OS X)"
        postInnertube(endpoint: "player", payload: payload, userAgent: iosUA) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let dict):
                guard let streamingData = dict["streamingData"] as? [String: Any] else {
                    completion(.failure(DataProviderError.noPlayableH264Stream))
                    return
                }
                let details = (dict["videoDetails"] as? [String: Any]) ?? [:]
                let title = (details["title"] as? String) ?? "Video YouTube"
                let author = (details["author"] as? String) ?? ""
                let channelId = (details["channelId"] as? String) ?? ""
                let duration = Int((details["lengthSeconds"] as? String) ?? "") ?? 0
                let views = YouTubeParsing.parseInt64(details["viewCount"])
                let isLive = (details["isLiveContent"] as? Bool) ?? false
                let desc = details["shortDescription"] as? String

                let video = VideoItem(
                    id: videoId,
                    title: title,
                    channelId: channelId,
                    channelName: author,
                    thumbnailURL: VideoItem.defaultThumbnailURL(for: videoId),
                    durationSeconds: duration,
                    viewCount: views,
                    uploadedText: "",
                    isLive: isLive,
                    isShort: false,
                    descriptionText: desc
                )

                let hlsURL = (streamingData["hlsManifestUrl"] as? String).flatMap { URL(string: $0) }
                var progressive: [VideoStreamOption] = []
                if let formats = streamingData["formats"] as? [[String: Any]] {
                    for f in formats {
                        guard let urlStr = f["url"] as? String, let url = URL(string: urlStr) else { continue }
                        let mime = (f["mimeType"] as? String) ?? ""
                        guard VideoStreamOption.isHardwareCompatible(mimeType: mime, codec: nil) else { continue }
                        let itag = f["itag"] as? Int
                        let height = (f["height"] as? Int) ?? 360
                        let label = (f["qualityLabel"] as? String) ?? "\(height)p"
                        let bitrate = (f["bitrate"] as? Int) ?? 0
                        progressive.append(VideoStreamOption(
                            url: url,
                            itag: itag,
                            mimeType: mime,
                            qualityLabel: label,
                            height: height,
                            bitrate: bitrate,
                            isHLS: false,
                            isAudioOnly: false,
                            isH264: true
                        ))
                    }
                }

                var audioOnly: [VideoStreamOption] = []
                if let adaptive = streamingData["adaptiveFormats"] as? [[String: Any]] {
                    for f in adaptive {
                        let mime = ((f["mimeType"] as? String) ?? "").lowercased()
                        guard mime.contains("audio/mp4") || mime.contains("mp4a") else { continue }
                        guard let urlStr = f["url"] as? String, let url = URL(string: urlStr) else { continue }
                        let itag = f["itag"] as? Int
                        let bitrate = (f["bitrate"] as? Int) ?? 128_000
                        audioOnly.append(VideoStreamOption(
                            url: url,
                            itag: itag,
                            mimeType: mime,
                            qualityLabel: "Audio M4A",
                            height: 0,
                            bitrate: bitrate,
                            isHLS: false,
                            isAudioOnly: true,
                            isH264: true
                        ))
                    }
                }

                guard hlsURL != nil || !progressive.isEmpty else {
                    completion(.failure(DataProviderError.noPlayableH264Stream))
                    return
                }

                // Fetch related videos via Innertube /next asynchronously if available, otherwise return immediately
                self.fetchRelatedOnly(videoId: videoId, region: region) { related in
                    let info = StreamInfo(
                        video: video,
                        hlsURL: hlsURL,
                        progressiveStreams: progressive,
                        audioOnlyStreams: audioOnly,
                        relatedVideos: related,
                        providerName: self.providerName,
                        fetchedAt: Date()
                    )
                    completion(.success(info))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func fetchRelatedOnly(videoId: String, region: String, completion: @escaping ([VideoItem]) -> Void) {
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "videoId": videoId
        ]
        postInnertube(endpoint: "next", payload: payload) { [weak self] result in
            guard let self = self else {
                completion([])
                return
            }
            switch result {
            case .success(let dict):
                var related: [VideoItem] = []
                self.collectVideoRenderers(in: dict, into: &related)
                completion(VideoFilter.filterOutShorts(related))
            case .failure:
                completion([])
            }
        }
    }

    func fetchComments(videoId: String, completion: @escaping (Result<[CommentItem], Error>) -> Void) {
        // Innertube comments require multi-step continuation tokens; return empty safely in direct fallback.
        completion(.success([]))
    }

    func fetchChannel(channelId: String, completion: @escaping (Result<ChannelItem, Error>) -> Void) {
        let region = LocalStore.shared.settings.regionCode
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "browseId": channelId,
            "params": "EgZ2aWRlb3PyBgQKAjoA" // Videos tab
        ]
        postInnertube(endpoint: "browse", payload: payload) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let dict):
                var name = "Kênh YouTube"
                var subsText = ""
                var avatarURL: URL?
                if let metadata = (dict["metadata"] as? [String: Any])?["channelMetadataRenderer"] as? [String: Any] {
                    name = (metadata["title"] as? String) ?? name
                    if let thumbs = (metadata["avatar"] as? [String: Any])?["thumbnails"] as? [[String: Any]],
                       let u = thumbs.first?["url"] as? String {
                        avatarURL = URL(string: u)
                    }
                }
                if let header = (dict["header"] as? [String: Any])?["c4TabbedHeaderRenderer"] as? [String: Any] {
                    subsText = self.extractText(header["subscriberCountText"])
                }
                var videos: [VideoItem] = []
                self.collectVideoRenderers(in: dict, into: &videos, fallbackChannelId: channelId, fallbackChannelName: name)
                completion(.success(ChannelItem(
                    id: channelId,
                    name: name,
                    avatarURL: avatarURL,
                    subscriberCountText: subsText,
                    videos: VideoFilter.filterOutShorts(videos)
                )))
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    // MARK: - Recursive Renderer Extractor

    private func collectVideoRenderers(
        in node: Any,
        into out: inout [VideoItem],
        fallbackChannelId: String = "",
        fallbackChannelName: String = ""
    ) {
        if out.count >= 40 { return } // Cap memory & traversal depth on A7

        if let dict = node as? [String: Any] {
            for key in ["videoRenderer", "compactVideoRenderer", "gridVideoRenderer"] {
                if let r = dict[key] as? [String: Any],
                   let item = parseRenderer(r, fallbackChannelId: fallbackChannelId, fallbackChannelName: fallbackChannelName),
                   !out.contains(where: { $0.id == item.id }) {
                    out.append(item)
                }
            }
            for value in dict.values {
                collectVideoRenderers(in: value, into: &out, fallbackChannelId: fallbackChannelId, fallbackChannelName: fallbackChannelName)
            }
        } else if let array = node as? [Any] {
            for element in array {
                collectVideoRenderers(in: element, into: &out, fallbackChannelId: fallbackChannelId, fallbackChannelName: fallbackChannelName)
            }
        }
    }

    private func parseRenderer(
        _ r: [String: Any],
        fallbackChannelId: String,
        fallbackChannelName: String
    ) -> VideoItem? {
        guard let videoId = r["videoId"] as? String, !videoId.isEmpty else { return nil }
        let title = extractText(r["title"])
        guard !title.isEmpty else { return nil }

        let chName = extractText(r["ownerText"]).isEmpty
            ? (extractText(r["longBylineText"]).isEmpty ? fallbackChannelName : extractText(r["longBylineText"]))
            : extractText(r["ownerText"])

        var chId = fallbackChannelId
        if let runs = (r["ownerText"] as? [String: Any])?["runs"] as? [[String: Any]],
           let browseId = ((runs.first?["navigationEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String {
            chId = browseId
        }

        let lengthText = extractText(r["lengthText"])
        let duration = YouTubeParsing.parseDurationString(lengthText)
        let viewsText = extractText(r["viewCountText"])
        let views = YouTubeParsing.parseInt64(viewsText)
        let published = extractText(r["publishedTimeText"])

        return VideoItem(
            id: videoId,
            title: title,
            channelId: chId,
            channelName: chName,
            thumbnailURL: VideoItem.defaultThumbnailURL(for: videoId),
            durationSeconds: duration,
            viewCount: views,
            uploadedText: published,
            isLive: duration == 0 && lengthText.isEmpty,
            isShort: false
        )
    }

    private func extractText(_ obj: Any?) -> String {
        guard let dict = obj as? [String: Any] else { return "" }
        if let simple = dict["simpleText"] as? String {
            return simple
        }
        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }
        return ""
    }
}
