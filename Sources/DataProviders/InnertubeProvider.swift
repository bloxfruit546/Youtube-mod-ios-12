import Foundation

/// Direct Innertube (youtubei/v1) provider running straight from the iPhone's residential IP.
/// Implements multi-client fallback for `/player`:
/// 1. ANDROID_VR (returns direct Itag 18 MP4 H.264+AAC & HLS without PO Token or signatureCipher)
/// 2. IOS (with auto-fetched VISITOR_DATA for HLS manifest)
/// 3. TVHTML5_SIMPLY_EMBEDDED_PLAYER (embedded fallback)
final class InnertubeProvider: YouTubeDataSourceProtocol {
    let providerName = "Innertube"

    private let baseAPI = "https://www.youtube.com/youtubei/v1"
    private let visitorLock = NSLock()
    private var cachedVisitorData: String?

    private enum PlayerClientKind: String {
        case androidVR = "ANDROID_VR"
        case ios = "IOS"
        case tvEmbedded = "TVHTML5_SIMPLY_EMBEDDED_PLAYER"
    }

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

    private func playerRequestConfig(
        for client: PlayerClientKind,
        videoId: String,
        region: String,
        visitorData: String?
    ) -> (payload: [String: Any], headers: [String: String]) {
        switch client {
        case .androidVR:
            let payload: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "ANDROID_VR",
                        "clientVersion": "1.65.10",
                        "deviceMake": "Oculus",
                        "deviceModel": "Quest 3",
                        "osName": "Android",
                        "osVersion": "12L",
                        "androidSdkVersion": 32,
                        "hl": "vi",
                        "gl": region
                    ]
                ],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            let headers = [
                "Content-Type": "application/json",
                "User-Agent": "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip",
                "X-YouTube-Client-Name": "28",
                "X-YouTube-Client-Version": "1.65.10"
            ]
            return (payload, headers)

        case .ios:
            var clientDict: [String: Any] = [
                "clientName": "IOS",
                "clientVersion": "20.11.6",
                "deviceMake": "Apple",
                "deviceModel": "iPhone10,4",
                "osName": "iOS",
                "osVersion": "16.7.7.20H330",
                "hl": "vi",
                "gl": region
            ]
            if let vd = visitorData, !vd.isEmpty {
                clientDict["visitorData"] = vd
            }
            let payload: [String: Any] = [
                "context": [
                    "client": clientDict
                ],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            var headers = [
                "Content-Type": "application/json",
                "User-Agent": "com.google.ios.youtube/20.11.6 (iPhone10,4; U; CPU iOS 16_7_7 like Mac OS X)",
                "X-YouTube-Client-Name": "5",
                "X-YouTube-Client-Version": "20.11.6"
            ]
            if let vd = visitorData, !vd.isEmpty {
                headers["X-Goog-Visitor-Id"] = vd
            }
            return (payload, headers)

        case .tvEmbedded:
            let payload: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
                        "clientVersion": "2.0",
                        "hl": "vi",
                        "gl": region
                    ],
                    "thirdParty": [
                        "embedUrl": "https://www.youtube.com/"
                    ]
                ],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            let headers = [
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (SMART-TV; Linux; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/4.0 Chrome/76.0.3809.146 TV Safari/537.36",
                "X-YouTube-Client-Name": "85",
                "X-YouTube-Client-Version": "2.0"
            ]
            return (payload, headers)
        }
    }

    private func postInnertube(
        endpoint: String,
        payload: [String: Any],
        headers customHeaders: [String: String]? = nil,
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
        if let customHeaders = customHeaders {
            for (k, v) in customHeaders {
                headers[k] = v
            }
        }
        HTTPClient.shared.requestJSONObject(url: url, method: "POST", headers: headers, body: body, timeout: 6.0) { result in
            switch result {
            case .success(let obj):
                if let dict = obj as? [String: Any] {
                    completion(.success(dict))
                } else {
                    completion(.failure(DataProviderError.decodingError("Innertube không trả về JSON object")))
                }
            case .failure(let err):
                completion(.failure(err))
            }
        }
    }

    private func ensureVisitorData(region: String, completion: @escaping (String?) -> Void) {
        visitorLock.lock()
        let existing = cachedVisitorData
        visitorLock.unlock()

        if let existing = existing, !existing.isEmpty {
            completion(existing)
            return
        }

        let guidePayload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": "20.11.6",
                    "deviceMake": "Apple",
                    "deviceModel": "iPhone10,4",
                    "osName": "iOS",
                    "osVersion": "16.7.7.20H330",
                    "hl": "vi",
                    "gl": region
                ]
            ]
        ]
        let guideHeaders = [
            "Content-Type": "application/json",
            "User-Agent": "com.google.ios.youtube/20.11.6 (iPhone10,4; U; CPU iOS 16_7_7 like Mac OS X)",
            "X-YouTube-Client-Name": "5",
            "X-YouTube-Client-Version": "20.11.6"
        ]

        postInnertube(endpoint: "guide", payload: guidePayload, headers: guideHeaders) { [weak self] result in
            if case .success(let dict) = result,
               let respCtx = dict["responseContext"] as? [String: Any],
               let vd = respCtx["visitorData"] as? String,
               !vd.isEmpty {
                self?.visitorLock.lock()
                self?.cachedVisitorData = vd
                self?.visitorLock.unlock()
                AppLogger.shared.info("Fetched Innertube VISITOR_DATA")
                completion(vd)
                return
            }

            // Fallback: extract visitorData from YouTube embed HTML page
            guard let embedURL = URL(string: "https://www.youtube.com/") else {
                completion(nil)
                return
            }
            HTTPClient.shared.requestData(url: embedURL, timeout: 5.0) { htmlResult in
                if case .success(let data) = htmlResult,
                   let html = String(data: data, encoding: .utf8),
                   let vd = self?.extractVisitorDataFromHTML(html) {
                    self?.visitorLock.lock()
                    self?.cachedVisitorData = vd
                    self?.visitorLock.unlock()
                    completion(vd)
                } else {
                    completion(nil)
                }
            }
        }
    }

    private func extractVisitorDataFromHTML(_ html: String) -> String? {
        let marker = "\"visitorData\":\""
        guard let r = html.range(of: marker) else { return nil }
        let rest = html[r.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        let val = String(rest[..<end])
        return val.isEmpty ? nil : val
    }

    // MARK: - Feed / Search / Channel

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

    // MARK: - Video Streams with Multi-Client Fallback

    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void) {
        let cleanId = YouTubeParsing.extractCleanVideoId(videoId)
        guard !cleanId.isEmpty else {
            completion(.failure(DataProviderError.providerDetail(provider: providerName, detail: "Video ID rỗng")))
            return
        }

        let region = LocalStore.shared.settings.regionCode
        let clients: [PlayerClientKind] = [.androidVR, .ios, .tvEmbedded]
        attemptPlayerClient(
            clients: clients,
            index: 0,
            videoId: cleanId,
            region: region,
            errors: [],
            completion: completion
        )
    }

    private func attemptPlayerClient(
        clients: [PlayerClientKind],
        index: Int,
        videoId: String,
        region: String,
        errors: [String],
        completion: @escaping (Result<StreamInfo, Error>) -> Void
    ) {
        guard index < clients.count else {
            let joined = errors.joined(separator: "; ")
            completion(.failure(DataProviderError.providerDetail(provider: "Innertube", detail: joined)))
            return
        }

        let client = clients[index]
        let runCall: (String?) -> Void = { [weak self] visitorData in
            guard let self = self else { return }
            let cfg = self.playerRequestConfig(for: client, videoId: videoId, region: region, visitorData: visitorData)
            self.postInnertube(endpoint: "player", payload: cfg.payload, headers: cfg.headers) { result in
                switch result {
                case .success(let dict):
                    switch self.parsePlayerDict(dict, videoId: videoId, client: client) {
                    case .success(let partialInfo):
                        self.fetchRelatedOnly(videoId: videoId, region: region) { related in
                            let full = StreamInfo(
                                video: partialInfo.video,
                                hlsURL: partialInfo.hlsURL,
                                progressiveStreams: partialInfo.progressiveStreams,
                                audioOnlyStreams: partialInfo.audioOnlyStreams,
                                relatedVideos: related,
                                providerName: partialInfo.providerName,
                                fetchedAt: Date()
                            )
                            completion(.success(full))
                        }
                    case .failure(let parseErr):
                        let detail = "\(client.rawValue): \(parseErr.localizedDescription)"
                        AppLogger.shared.warn("Innertube client failover -> \(detail)")
                        self.attemptPlayerClient(
                            clients: clients,
                            index: index + 1,
                            videoId: videoId,
                            region: region,
                            errors: errors + [detail],
                            completion: completion
                        )
                    }
                case .failure(let err):
                    let detail = "\(client.rawValue): \(err.localizedDescription)"
                    AppLogger.shared.warn("Innertube client failover -> \(detail)")
                    self.attemptPlayerClient(
                        clients: clients,
                        index: index + 1,
                        videoId: videoId,
                        region: region,
                        errors: errors + [detail],
                        completion: completion
                    )
                }
            }
        }

        if client == .ios {
            ensureVisitorData(region: region) { vd in
                runCall(vd)
            }
        } else {
            runCall(nil)
        }
    }

    private func parsePlayerDict(
        _ dict: [String: Any],
        videoId: String,
        client: PlayerClientKind
    ) -> Result<StreamInfo, Error> {
        if let playability = dict["playabilityStatus"] as? [String: Any] {
            let status = (playability["status"] as? String) ?? "UNKNOWN"
            if status != "OK" {
                let reason = (playability["reason"] as? String) ?? ""
                let msg = reason.isEmpty ? status : "\(status) (\(reason))"
                return .failure(DataProviderError.networkError(msg))
            }
        }

        guard let streamingData = dict["streamingData"] as? [String: Any] else {
            return .failure(DataProviderError.noPlayableH264Stream)
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

        let hlsStr = (streamingData["hlsManifestUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hlsURL = hlsStr.flatMap { $0.isEmpty ? nil : URL(string: $0) }

        var progressive: [VideoStreamOption] = []
        if let formats = streamingData["formats"] as? [[String: Any]] {
            for f in formats {
                // Skip encrypted signatureCipher entries that have no direct url
                guard let urlStr = f["url"] as? String, !urlStr.isEmpty, let url = URL(string: urlStr) else {
                    continue
                }
                let mime = (f["mimeType"] as? String) ?? ""
                let itag = f["itag"] as? Int
                let isItag18Or22 = (itag == 18 || itag == 22)
                guard isItag18Or22 || VideoStreamOption.isHardwareCompatible(mimeType: mime, codec: nil) else {
                    continue
                }
                let height = (f["height"] as? Int) ?? (itag == 22 ? 720 : 360)
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
                guard let urlStr = f["url"] as? String, !urlStr.isEmpty, let url = URL(string: urlStr) else { continue }
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
            return .failure(DataProviderError.noPlayableH264Stream)
        }

        return .success(StreamInfo(
            video: video,
            hlsURL: hlsURL,
            progressiveStreams: progressive,
            audioOnlyStreams: audioOnly,
            relatedVideos: [],
            providerName: "Innertube (\(client.rawValue))",
            fetchedAt: Date()
        ))
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
        completion(.success([]))
    }

    func fetchChannel(channelId: String, completion: @escaping (Result<ChannelItem, Error>) -> Void) {
        let region = LocalStore.shared.settings.regionCode
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "browseId": channelId,
            "params": "EgZ2aWRlb3PyBgQKAjoA"
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
        if out.count >= 40 { return }

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
        guard let rawId = r["videoId"] as? String else { return nil }
        let videoId = YouTubeParsing.extractCleanVideoId(rawId)
        guard !videoId.isEmpty else { return nil }
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
