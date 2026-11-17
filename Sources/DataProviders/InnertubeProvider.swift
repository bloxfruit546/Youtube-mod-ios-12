import Foundation

/// Direct Innertube (youtubei/v1) provider running from the iPhone's residential IP.
/// Client fallback order (yt-dlp aligned):
/// 1. VISIONOS (1.02, client ID 101, Mac/Safari UA + visitorData)
/// 2. WEB_EMBEDDED_PLAYER (client ID 56, for kids/embed/itag 18)
/// 3. MWEB (client ID 2, iPad Safari UA + visitorData)
/// 4. ANDROID_VR (1.71.26, client ID 28)
final class InnertubeProvider: YouTubeDataSourceProtocol {
    let providerName = "Innertube"

    private let baseAPI = "https://www.youtube.com/youtubei/v1"
    private let visitorLock = NSLock()
    private var cachedVisitorData: String?

    private let visionOSUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
    private let mwebUserAgent = "Mozilla/5.0 (iPad; CPU OS 16_7_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1"
    private let androidVRUserAgent = "com.google.android.apps.youtube.vr.oculus/1.71.26 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"

    private enum PlayerClientKind: String {
        case visionOS = "VISIONOS"
        case webEmbedded = "WEB_EMBEDDED_PLAYER"
        case mweb = "MWEB"
        case androidVR = "ANDROID_VR"
    }

    private func webContext(region: String) -> [String: Any] {
        return [
            "client": [
                "clientName": "WEB",
                "clientVersion": "2.20250310.01.00",
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
    ) -> (payload: [String: Any], headers: [String: String], avPlayerHeaders: [String: String]) {
        switch client {
        case .visionOS:
            var clientDict: [String: Any] = [
                "clientName": "VISIONOS",
                "clientVersion": "1.02",
                "hl": "vi",
                "gl": region
            ]
            if let vd = visitorData, !vd.isEmpty {
                clientDict["visitorData"] = vd
            }
            let payload: [String: Any] = [
                "context": ["client": clientDict],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            var headers = [
                "Content-Type": "application/json",
                "User-Agent": visionOSUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
                "X-YouTube-Client-Name": "101",
                "X-YouTube-Client-Version": "1.02"
            ]
            if let vd = visitorData, !vd.isEmpty {
                headers["X-Goog-Visitor-Id"] = vd
            }
            let avHeaders = [
                "User-Agent": visionOSUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/"
            ]
            return (payload, headers, avHeaders)

        case .webEmbedded:
            var clientDict: [String: Any] = [
                "clientName": "WEB_EMBEDDED_PLAYER",
                "clientVersion": "1.20250310.01.00",
                "hl": "vi",
                "gl": region
            ]
            if let vd = visitorData, !vd.isEmpty {
                clientDict["visitorData"] = vd
            }
            let payload: [String: Any] = [
                "context": [
                    "client": clientDict,
                    "thirdParty": [
                        "embedUrl": "https://www.youtube.com/"
                    ]
                ],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            var headers = [
                "Content-Type": "application/json",
                "User-Agent": visionOSUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
                "X-YouTube-Client-Name": "56",
                "X-YouTube-Client-Version": "1.20250310.01.00"
            ]
            if let vd = visitorData, !vd.isEmpty {
                headers["X-Goog-Visitor-Id"] = vd
            }
            let avHeaders = [
                "User-Agent": visionOSUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/"
            ]
            return (payload, headers, avHeaders)

        case .mweb:
            var clientDict: [String: Any] = [
                "clientName": "MWEB",
                "clientVersion": "2.20250310.01.00",
                "hl": "vi",
                "gl": region
            ]
            if let vd = visitorData, !vd.isEmpty {
                clientDict["visitorData"] = vd
            }
            let payload: [String: Any] = [
                "context": ["client": clientDict],
                "videoId": videoId,
                "contentCheckOk": true,
                "racyCheckOk": true
            ]
            var headers = [
                "Content-Type": "application/json",
                "User-Agent": mwebUserAgent,
                "Origin": "https://m.youtube.com",
                "Referer": "https://m.youtube.com/",
                "X-YouTube-Client-Name": "2",
                "X-YouTube-Client-Version": "2.20250310.01.00"
            ]
            if let vd = visitorData, !vd.isEmpty {
                headers["X-Goog-Visitor-Id"] = vd
            }
            let avHeaders = [
                "User-Agent": mwebUserAgent,
                "Origin": "https://m.youtube.com",
                "Referer": "https://m.youtube.com/"
            ]
            return (payload, headers, avHeaders)

        case .androidVR:
            let payload: [String: Any] = [
                "context": [
                    "client": [
                        "clientName": "ANDROID_VR",
                        "clientVersion": "1.71.26",
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
                "User-Agent": androidVRUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/",
                "X-YouTube-Client-Name": "28",
                "X-YouTube-Client-Version": "1.71.26"
            ]
            let avHeaders = [
                "User-Agent": androidVRUserAgent,
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/"
            ]
            return (payload, headers, avHeaders)
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

    /// Fetches visitorData cleanly from `/youtubei/v1/visitor_id`, falling back to `/youtubei/v1/guide`.
    private func ensureVisitorData(region: String, completion: @escaping (String?) -> Void) {
        visitorLock.lock()
        let existing = cachedVisitorData
        visitorLock.unlock()

        if let existing = existing, !existing.isEmpty {
            completion(existing)
            return
        }

        let payload: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "VISIONOS",
                    "clientVersion": "1.02",
                    "hl": "vi",
                    "gl": region
                ]
            ]
        ]
        let headers = [
            "Content-Type": "application/json",
            "User-Agent": visionOSUserAgent,
            "Origin": "https://www.youtube.com",
            "Referer": "https://www.youtube.com/",
            "X-YouTube-Client-Name": "101",
            "X-YouTube-Client-Version": "1.02"
        ]

        postInnertube(endpoint: "visitor_id", payload: payload, headers: headers) { [weak self] result in
            if case .success(let dict) = result,
               let respCtx = dict["responseContext"] as? [String: Any],
               let vd = respCtx["visitorData"] as? String,
               !vd.isEmpty {
                self?.visitorLock.lock()
                self?.cachedVisitorData = vd
                self?.visitorLock.unlock()
                AppLogger.shared.info("Fetched visitorData via /visitor_id")
                completion(vd)
                return
            }

            // Fallback to /youtubei/v1/guide
            self?.postInnertube(endpoint: "guide", payload: payload, headers: headers) { guideResult in
                if case .success(let dict) = guideResult,
                   let respCtx = dict["responseContext"] as? [String: Any],
                   let vd = respCtx["visitorData"] as? String,
                   !vd.isEmpty {
                    self?.visitorLock.lock()
                    self?.cachedVisitorData = vd
                    self?.visitorLock.unlock()
                    AppLogger.shared.info("Fetched visitorData via /guide")
                    completion(vd)
                    return
                }
                completion(nil)
            }
        }
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
                let filtered = VideoFilter.filterOutShorts(items)
                if !filtered.isEmpty {
                    completion(.success(filtered))
                } else {
                    // Fallback if YouTube hides FEtrending when logged out
                    let query = region.uppercased() == "VN" ? "thịnh hành việt nam mới nhất" : "trending music news"
                    self.search(query: query, completion: completion)
                }
            case .failure:
                let query = region.uppercased() == "VN" ? "thịnh hành việt nam mới nhất" : "trending music news"
                self.search(query: query, completion: completion)
            }
        }
    }

    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let region = LocalStore.shared.settings.regionCode
        let payload: [String: Any] = [
            "context": webContext(region: region),
            "query": query,
            "params": "EgIQAQ=="
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
        let clients: [PlayerClientKind] = [.visionOS, .webEmbedded, .mweb, .androidVR]

        ensureVisitorData(region: region) { [weak self] visitorData in
            self?.attemptPlayerClient(
                clients: clients,
                index: 0,
                videoId: cleanId,
                region: region,
                visitorData: visitorData,
                errors: [],
                completion: completion
            )
        }
    }

    private func attemptPlayerClient(
        clients: [PlayerClientKind],
        index: Int,
        videoId: String,
        region: String,
        visitorData: String?,
        errors: [String],
        completion: @escaping (Result<StreamInfo, Error>) -> Void
    ) {
        guard index < clients.count else {
            let joined = errors.joined(separator: "; ")
            completion(.failure(DataProviderError.providerDetail(provider: "Innertube", detail: joined)))
            return
        }

        let client = clients[index]
        let cfg = playerRequestConfig(for: client, videoId: videoId, region: region, visitorData: visitorData)

        postInnertube(endpoint: "player", payload: cfg.payload, headers: cfg.headers) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let dict):
                switch self.parsePlayerDict(dict, videoId: videoId, client: client, avHeaders: cfg.avPlayerHeaders) {
                case .success(let partialInfo):
                    self.fetchRelatedOnly(videoId: videoId, region: region) { related in
                        let full = StreamInfo(
                            video: partialInfo.video,
                            hlsURL: partialInfo.hlsURL,
                            progressiveStreams: partialInfo.progressiveStreams,
                            audioOnlyStreams: partialInfo.audioOnlyStreams,
                            relatedVideos: related,
                            providerName: partialInfo.providerName,
                            fetchedAt: Date(),
                            httpHeaders: partialInfo.httpHeaders
                        )
                        completion(.success(full))
                    }
                case .failure(let parseErr):
                    if case DataProviderError.terminalUnplayable = parseErr {
                        AppLogger.shared.warn("Innertube fast-fail [\(client.rawValue)]: \(parseErr.localizedDescription)")
                        completion(.failure(parseErr))
                        return
                    }
                    let detail = "\(client.rawValue): \(parseErr.localizedDescription)"
                    AppLogger.shared.warn("Innertube client failover -> \(detail)")
                    self.attemptPlayerClient(
                        clients: clients,
                        index: index + 1,
                        videoId: videoId,
                        region: region,
                        visitorData: visitorData,
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
                    visitorData: visitorData,
                    errors: errors + [detail],
                    completion: completion
                )
            }
        }
    }

    private func parsePlayerDict(
        _ dict: [String: Any],
        videoId: String,
        client: PlayerClientKind,
        avHeaders: [String: String]
    ) -> Result<StreamInfo, Error> {
        if let playability = dict["playabilityStatus"] as? [String: Any] {
            let status = (playability["status"] as? String) ?? "UNKNOWN"
            if status != "OK" {
                let reason = ((playability["reason"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if (status == "UNPLAYABLE" || status == "LIVE_STREAM_OFFLINE" || status == "ERROR") && !reason.isEmpty {
                    return .failure(DataProviderError.terminalUnplayable("Video không khả dụng: \(reason)"))
                }
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

        // Master .m3u8 (supports both VOD & Livestream without JS cipher or PO Token)
        let hlsStr = (streamingData["hlsManifestUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hlsURL = hlsStr.flatMap { $0.isEmpty ? nil : URL(string: $0) }

        var progressive: [VideoStreamOption] = []
        if let formats = streamingData["formats"] as? [[String: Any]] {
            for f in formats {
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
                let itag = f["itag"] as? Int
                let mime = ((f["mimeType"] as? String) ?? "").lowercased()
                let isAudioItag = (itag == 140 || itag == 139)
                guard isAudioItag || mime.contains("audio/mp4") || mime.contains("mp4a") else { continue }
                guard let urlStr = f["url"] as? String, !urlStr.isEmpty, let url = URL(string: urlStr) else { continue }
                let bitrate = (f["bitrate"] as? Int) ?? (itag == 139 ? 48_000 : 128_000)
                audioOnly.append(VideoStreamOption(
                    url: url,
                    itag: itag,
                    mimeType: mime,
                    qualityLabel: itag == 139 ? "48kbps M4A" : "Audio M4A",
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
            fetchedAt: Date(),
            httpHeaders: avHeaders
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
