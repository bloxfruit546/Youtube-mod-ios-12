import Foundation

final class InvidiousProvider: YouTubeDataSourceProtocol {
    let providerName = "Invidious"

    private var instances: [String] {
        let list = LocalStore.shared.settings.invidiousInstances
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? AppSettings.defaultInvidiousInstances : list
    }

    private func requestAcrossInstances(
        pathAndQuery: String,
        index: Int = 0,
        errors: [String] = [],
        completion: @escaping (Result<(baseURL: String, json: Any), Error>) -> Void
    ) {
        let list = instances
        guard index < list.count else {
            completion(.failure(DataProviderError.allProvidersFailed(errors)))
            return
        }

        let base = list[index]
        guard let url = URL(string: base + pathAndQuery) else {
            requestAcrossInstances(pathAndQuery: pathAndQuery, index: index + 1, errors: errors + ["\(base): URL sai"], completion: completion)
            return
        }

        HTTPClient.shared.requestJSONObject(url: url, timeout: 6.0) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                completion(.success((base, json)))
            case .failure(let err):
                let detail = "Invidious[\(base)]: \(err.localizedDescription)"
                AppLogger.shared.warn("Failover \(detail)")
                self.requestAcrossInstances(
                    pathAndQuery: pathAndQuery,
                    index: index + 1,
                    errors: errors + [detail],
                    completion: completion
                )
            }
        }
    }

    func fetchTrending(region: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let reg = region.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "VN"
        requestAcrossInstances(pathAndQuery: "/api/v1/trending?region=\(reg)") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success((_, let json)):
                guard let array = json as? [[String: Any]] else {
                    completion(.failure(DataProviderError.decodingError("Invidious trending không hợp lệ")))
                    return
                }
                let videos = VideoFilter.filterOutShorts(array.compactMap { self.parseVideoSummary($0) })
                completion(.success(videos))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        requestAcrossInstances(pathAndQuery: "/api/v1/search?q=\(q)&type=video") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success((_, let json)):
                guard let array = json as? [[String: Any]] else {
                    completion(.failure(DataProviderError.decodingError("Invidious search không hợp lệ")))
                    return
                }
                let videos = VideoFilter.filterOutShorts(array.compactMap { self.parseVideoSummary($0) })
                completion(.success(videos))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchSearchSuggestions(query: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        requestAcrossInstances(pathAndQuery: "/api/v1/search/suggestions?q=\(q)") { result in
            switch result {
            case .success((_, let json)):
                if let dict = json as? [String: Any], let suggestions = dict["suggestions"] as? [String] {
                    completion(.success(suggestions))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void) {
        let safeId = videoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoId
        requestAcrossInstances(pathAndQuery: "/api/v1/videos/\(safeId)") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success((let base, let json)):
                guard let dict = json as? [String: Any] else {
                    completion(.failure(DataProviderError.decodingError("Invidious video JSON sai")))
                    return
                }

                let title = (dict["title"] as? String) ?? "Không có tiêu đề"
                let author = (dict["author"] as? String) ?? ""
                let authorId = (dict["authorId"] as? String) ?? ""
                let lengthSeconds = (dict["lengthSeconds"] as? Int) ?? 0
                let views = YouTubeParsing.parseInt64(dict["viewCount"])
                let publishedText = (dict["publishedText"] as? String) ?? ""
                let isLive = (dict["liveNow"] as? Bool) ?? false
                let desc = dict["description"] as? String

                var avatarURL: URL?
                if let thumbs = dict["authorThumbnails"] as? [[String: Any]], let firstUrl = thumbs.first?["url"] as? String {
                    avatarURL = URL(string: firstUrl)
                }

                let video = VideoItem(
                    id: videoId,
                    title: title,
                    channelId: authorId,
                    channelName: author,
                    channelAvatarURL: avatarURL,
                    thumbnailURL: VideoItem.defaultThumbnailURL(for: videoId),
                    durationSeconds: lengthSeconds,
                    viewCount: views,
                    uploadedText: publishedText,
                    isLive: isLive,
                    isShort: false,
                    descriptionText: desc
                )

                let hlsURL = (dict["hlsUrl"] as? String).flatMap { URL(string: $0) }

                var progressive: [VideoStreamOption] = []
                if let formats = dict["formatStreams"] as? [[String: Any]] {
                    for f in formats {
                        guard let urlStr = f["url"] as? String, let url = URL(string: urlStr) else { continue }
                        let typeStr = (f["type"] as? String) ?? ""
                        let container = (f["container"] as? String) ?? ""
                        guard VideoStreamOption.isHardwareCompatible(mimeType: typeStr + " " + container, codec: nil) else {
                            continue
                        }
                        let qualityLabel = (f["qualityLabel"] as? String) ?? (f["resolution"] as? String) ?? ""
                        let height = YouTubeParsing.parseHeight(from: qualityLabel)
                        let itag = (f["itag"] as? Int) ?? Int((f["itag"] as? String) ?? "")
                        progressive.append(VideoStreamOption(
                            url: url,
                            itag: itag,
                            mimeType: typeStr,
                            qualityLabel: qualityLabel,
                            height: height,
                            bitrate: Int((f["bitrate"] as? String) ?? "") ?? 0,
                            isHLS: false,
                            isAudioOnly: false,
                            isH264: true
                        ))
                    }
                }

                var audioOnly: [VideoStreamOption] = []
                if let adaptive = dict["adaptiveFormats"] as? [[String: Any]] {
                    for f in adaptive {
                        let typeStr = ((f["type"] as? String) ?? "").lowercased()
                        guard typeStr.contains("audio/mp4") || typeStr.contains("mp4a") else { continue }
                        guard let urlStr = f["url"] as? String, let url = URL(string: urlStr) else { continue }
                        let itag = (f["itag"] as? Int) ?? Int((f["itag"] as? String) ?? "")
                        let bitrate = Int((f["bitrate"] as? String) ?? "") ?? 128_000
                        audioOnly.append(VideoStreamOption(
                            url: url,
                            itag: itag,
                            mimeType: typeStr,
                            qualityLabel: "Audio M4A",
                            height: 0,
                            bitrate: bitrate,
                            isHLS: false,
                            isAudioOnly: true,
                            isH264: true
                        ))
                    }
                }

                let recRaw = (dict["recommendedVideos"] as? [[String: Any]]) ?? []
                let related = VideoFilter.filterOutShorts(recRaw.compactMap { self.parseVideoSummary($0) })

                let info = StreamInfo(
                    video: video,
                    hlsURL: hlsURL,
                    progressiveStreams: progressive,
                    audioOnlyStreams: audioOnly,
                    relatedVideos: related,
                    providerName: "Invidious (\(URL(string: base)?.host ?? base))",
                    fetchedAt: Date()
                )
                if info.hlsURL == nil && info.progressiveStreams.isEmpty {
                    completion(.failure(DataProviderError.noPlayableH264Stream))
                    return
                }
                completion(.success(info))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchComments(videoId: String, completion: @escaping (Result<[CommentItem], Error>) -> Void) {
        let safeId = videoId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? videoId
        requestAcrossInstances(pathAndQuery: "/api/v1/comments/\(safeId)") { result in
            switch result {
            case .success((_, let json)):
                guard let dict = json as? [String: Any],
                      let list = dict["comments"] as? [[String: Any]] else {
                    completion(.success([]))
                    return
                }
                let comments: [CommentItem] = list.compactMap { item in
                    guard let content = item["content"] as? String else { return nil }
                    let id = (item["commentId"] as? String) ?? UUID().uuidString
                    let author = (item["author"] as? String) ?? "Người dùng"
                    var avatarURL: URL?
                    if let thumbs = item["authorThumbnails"] as? [[String: Any]], let u = thumbs.first?["url"] as? String {
                        avatarURL = URL(string: u)
                    }
                    let likes = (item["likeCount"] as? Int) ?? 0
                    let time = (item["publishedText"] as? String) ?? ""
                    let replies = (item["replies"] as? [String: Any])?["replyCount"] as? Int ?? 0
                    let pinned = (item["isPinned"] as? Bool) ?? false
                    let hearted = (item["creatorHeart"] as? [String: Any]) != nil
                    return CommentItem(
                        id: id,
                        authorName: author,
                        authorAvatarURL: avatarURL,
                        text: content,
                        likeCount: likes,
                        publishedText: time,
                        replyCount: replies,
                        isPinned: pinned,
                        isHearted: hearted
                    )
                }
                completion(.success(comments))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchChannel(channelId: String, completion: @escaping (Result<ChannelItem, Error>) -> Void) {
        let safeId = channelId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? channelId
        requestAcrossInstances(pathAndQuery: "/api/v1/channels/\(safeId)") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success((_, let json)):
                guard let dict = json as? [String: Any] else {
                    completion(.failure(DataProviderError.decodingError("Invidious channel sai")))
                    return
                }
                let id = (dict["authorId"] as? String) ?? channelId
                let name = (dict["author"] as? String) ?? "Kênh YouTube"
                var avatarURL: URL?
                if let thumbs = dict["authorThumbnails"] as? [[String: Any]], let u = thumbs.last?["url"] as? String {
                    avatarURL = URL(string: u)
                }
                let subCount = YouTubeParsing.parseInt64(dict["subCount"])
                let subsText = subCount > 0 ? "\(subCount) người đăng ký" : ""
                let desc = (dict["description"] as? String) ?? ""
                let verified = (dict["authorVerified"] as? Bool) ?? false
                let latestRaw = (dict["latestVideos"] as? [[String: Any]]) ?? []
                let videos = VideoFilter.filterOutShorts(latestRaw.compactMap {
                    self.parseVideoSummary($0, fallbackChannelId: id, fallbackChannelName: name)
                })
                completion(.success(ChannelItem(
                    id: id,
                    name: name,
                    avatarURL: avatarURL,
                    bannerURL: nil,
                    subscriberCountText: subsText,
                    descriptionText: desc,
                    isVerified: verified,
                    videos: videos
                )))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    private func parseVideoSummary(
        _ dict: [String: Any],
        fallbackChannelId: String = "",
        fallbackChannelName: String = ""
    ) -> VideoItem? {
        if let type = dict["type"] as? String, type != "video" && type != "shortVideo" {
            return nil
        }
        guard let videoId = dict["videoId"] as? String, !videoId.isEmpty else {
            return nil
        }
        let typeStr = (dict["type"] as? String) ?? ""
        let isShort = typeStr == "shortVideo"
        let title = (dict["title"] as? String) ?? ""
        let author = (dict["author"] as? String) ?? fallbackChannelName
        let authorId = (dict["authorId"] as? String) ?? fallbackChannelId
        let length = (dict["lengthSeconds"] as? Int) ?? 0
        let views = YouTubeParsing.parseInt64(dict["viewCount"])
        let published = (dict["publishedText"] as? String) ?? ""
        let isLive = (dict["liveNow"] as? Bool) ?? false

        return VideoItem(
            id: videoId,
            title: title,
            channelId: authorId,
            channelName: author,
            channelAvatarURL: nil,
            thumbnailURL: VideoItem.defaultThumbnailURL(for: videoId),
            durationSeconds: max(0, length),
            viewCount: views,
            uploadedText: published,
            isLive: isLive,
            isShort: isShort
        )
    }
}
