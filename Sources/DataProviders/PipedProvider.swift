import Foundation

final class PipedProvider: YouTubeDataSourceProtocol {
    let providerName = "Piped"

    private var instances: [String] {
        let list = LocalStore.shared.settings.pipedInstances
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? AppSettings.defaultPipedInstances : list
    }

    private func requestAcrossInstances(
        pathAndQuery: String,
        index: Int = 0,
        errors: [String] = [],
        completion: @escaping (Result<(baseURL: String, json: Any), Error>) -> Void
    ) {
        let list = instances
        guard index < list.count else {
            let summary = errors.prefix(2).joined(separator: "; ")
            completion(.failure(DataProviderError.providerDetail(provider: providerName, detail: summary.isEmpty ? "Không phản hồi" : summary)))
            return
        }

        let base = list[index]
        guard let url = URL(string: base + pathAndQuery) else {
            let host = URL(string: base)?.host ?? base
            requestAcrossInstances(pathAndQuery: pathAndQuery, index: index + 1, errors: errors + ["\(host): URL sai"], completion: completion)
            return
        }

        HTTPClient.shared.requestJSONObject(url: url, timeout: 6.0) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                completion(.success((base, json)))
            case .failure(let err):
                let host = url.host ?? base
                let detail = "\(host): \(err.localizedDescription)"
                AppLogger.shared.warn("Failover Piped[\(detail)]")
                self.requestAcrossInstances(
                    pathAndQuery: pathAndQuery,
                    index: index + 1,
                    errors: errors + [detail],
                    completion: completion
                )
            }
        }
    }

    private func resolveURL(_ raw: String?, base: String) -> URL? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if let baseURL = URL(string: base), let resolved = URL(string: s, relativeTo: baseURL)?.absoluteURL {
            return resolved
        }
        return URL(string: s)
    }

    // MARK: - YouTubeDataSourceProtocol

    func fetchTrending(region: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let reg = region.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "VN"
        requestAcrossInstances(pathAndQuery: "/trending?region=\(reg)") { result in
            switch result {
            case .success((_, let json)):
                guard let array = json as? [[String: Any]] else {
                    completion(.failure(DataProviderError.decodingError("Piped trending không phải mảng JSON")))
                    return
                }
                let videos = VideoFilter.filterOutShorts(array.compactMap { self.parseStreamSummary($0) })
                completion(.success(videos))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        requestAcrossInstances(pathAndQuery: "/search?q=\(q)&filter=videos") { result in
            switch result {
            case .success((_, let json)):
                guard let dict = json as? [String: Any],
                      let items = dict["items"] as? [[String: Any]] else {
                    completion(.failure(DataProviderError.decodingError("Piped search thiếu items")))
                    return
                }
                let videos = VideoFilter.filterOutShorts(items.compactMap { self.parseStreamSummary($0) })
                completion(.success(videos))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchSearchSuggestions(query: String, completion: @escaping (Result<[String], Error>) -> Void) {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        requestAcrossInstances(pathAndQuery: "/suggestions?query=\(q)") { result in
            switch result {
            case .success((_, let json)):
                if let list = json as? [String] {
                    completion(.success(list))
                } else {
                    completion(.success([]))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void) {
        let cleanId = YouTubeParsing.extractCleanVideoId(videoId)
        guard !cleanId.isEmpty else {
            completion(.failure(DataProviderError.providerDetail(provider: providerName, detail: "Video ID rỗng")))
            return
        }
        let safeId = cleanId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanId
        let list = instances
        fetchStreamsAcrossInstances(instances: list, index: 0, safeId: safeId, cleanId: cleanId, errors: [], completion: completion)
    }

    private func fetchStreamsAcrossInstances(
        instances: [String],
        index: Int,
        safeId: String,
        cleanId: String,
        errors: [String],
        completion: @escaping (Result<StreamInfo, Error>) -> Void
    ) {
        guard index < instances.count else {
            let summary = errors.prefix(2).joined(separator: "; ")
            completion(.failure(DataProviderError.providerDetail(provider: providerName, detail: summary.isEmpty ? "Không phản hồi" : summary)))
            return
        }

        let base = instances[index]
        let host = URL(string: base)?.host ?? base
        guard let url = URL(string: "\(base)/streams/\(safeId)") else {
            fetchStreamsAcrossInstances(instances: instances, index: index + 1, safeId: safeId, cleanId: cleanId, errors: errors + ["\(host): URL sai"], completion: completion)
            return
        }

        HTTPClient.shared.requestJSONObject(url: url, timeout: 6.0) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let json):
                guard let dict = json as? [String: Any] else {
                    let msg = "\(host): JSON không hợp lệ"
                    self.fetchStreamsAcrossInstances(instances: instances, index: index + 1, safeId: safeId, cleanId: cleanId, errors: errors + [msg], completion: completion)
                    return
                }
                if let errStr = (dict["error"] as? String) ?? (dict["message"] as? String), !errStr.isEmpty {
                    let msg = "\(host): \(errStr)"
                    AppLogger.shared.warn("Failover Piped[\(msg)]")
                    self.fetchStreamsAcrossInstances(instances: instances, index: index + 1, safeId: safeId, cleanId: cleanId, errors: errors + [msg], completion: completion)
                    return
                }

                if let info = self.parseStreamInfo(dict: dict, base: base, cleanId: cleanId) {
                    completion(.success(info))
                } else {
                    let msg = "\(host): Không có luồng H.264/HLS"
                    AppLogger.shared.warn("Failover Piped[\(msg)]")
                    self.fetchStreamsAcrossInstances(instances: instances, index: index + 1, safeId: safeId, cleanId: cleanId, errors: errors + [msg], completion: completion)
                }
            case .failure(let err):
                let msg = "\(host): \(err.localizedDescription)"
                AppLogger.shared.warn("Failover Piped[\(msg)]")
                self.fetchStreamsAcrossInstances(instances: instances, index: index + 1, safeId: safeId, cleanId: cleanId, errors: errors + [msg], completion: completion)
            }
        }
    }

    private func parseStreamInfo(dict: [String: Any], base: String, cleanId: String) -> StreamInfo? {
        let title = (dict["title"] as? String) ?? "Không có tiêu đề"
        let uploader = (dict["uploader"] as? String) ?? ""
        let uploaderUrl = dict["uploaderUrl"] as? String
        let channelId = YouTubeParsing.extractChannelId(from: uploaderUrl) ?? ""
        let avatarURL = resolveURL(dict["uploaderAvatar"] as? String, base: base)
        let duration = (dict["duration"] as? Int) ?? 0
        let views = YouTubeParsing.parseInt64(dict["views"])
        let uploadDate = (dict["uploadDate"] as? String) ?? ""
        let isLive = (dict["livestream"] as? Bool) ?? false
        let desc = dict["description"] as? String

        let video = VideoItem(
            id: cleanId,
            title: title,
            channelId: channelId,
            channelName: uploader,
            channelAvatarURL: avatarURL,
            thumbnailURL: VideoItem.defaultThumbnailURL(for: cleanId),
            durationSeconds: duration,
            viewCount: views,
            uploadedText: uploadDate,
            isLive: isLive,
            isShort: false,
            descriptionText: desc
        )

        let hlsURL = resolveURL(dict["hls"] as? String, base: base)

        var progressive: [VideoStreamOption] = []
        if let vStreams = dict["videoStreams"] as? [[String: Any]] {
            for s in vStreams {
                let itag = s["itag"] as? Int
                let videoOnlyOpt = s["videoOnly"] as? Bool
                if videoOnlyOpt == true {
                    continue
                }
                if videoOnlyOpt == nil && itag != 18 && itag != 22 {
                    continue
                }
                guard let url = resolveURL(s["url"] as? String, base: base) else { continue }
                let mime = (s["mimeType"] as? String) ?? ""
                let codec = s["codec"] as? String
                let format = (s["format"] as? String) ?? ""
                let combined = (mime + " " + format + " " + (codec ?? "")).lowercased()

                let isExplicitH264 = combined.contains("avc1") || combined.contains("mpeg_4") || combined.contains("mp4") || itag == 18 || itag == 22
                guard isExplicitH264 && VideoStreamOption.isHardwareCompatible(mimeType: mime + " " + format, codec: codec) else {
                    continue
                }

                let qualityLabel = (s["quality"] as? String) ?? ""
                let height = (s["height"] as? Int) ?? YouTubeParsing.parseHeight(from: qualityLabel)
                let bitrate = (s["bitrate"] as? Int) ?? 0
                progressive.append(VideoStreamOption(
                    url: url,
                    itag: itag,
                    mimeType: mime,
                    qualityLabel: qualityLabel,
                    height: height,
                    bitrate: bitrate,
                    isHLS: false,
                    isAudioOnly: false,
                    isH264: true
                ))
            }
        }

        var audioOnly: [VideoStreamOption] = []
        if let aStreams = dict["audioStreams"] as? [[String: Any]] {
            for s in aStreams {
                guard let url = resolveURL(s["url"] as? String, base: base) else { continue }
                let mime = (s["mimeType"] as? String) ?? ""
                let codec = s["codec"] as? String
                let format = (s["format"] as? String) ?? ""
                let combined = (mime + " " + format + " " + (codec ?? "")).lowercased()
                guard combined.contains("m4a") || combined.contains("mp4a") || combined.contains("mp4") else {
                    continue
                }
                let bitrate = (s["bitrate"] as? Int) ?? 128_000
                let itag = s["itag"] as? Int
                audioOnly.append(VideoStreamOption(
                    url: url,
                    itag: itag,
                    mimeType: mime,
                    qualityLabel: (s["quality"] as? String) ?? "128kbps M4A",
                    height: 0,
                    bitrate: bitrate,
                    isHLS: false,
                    isAudioOnly: true,
                    isH264: true
                ))
            }
        }

        let relatedRaw = (dict["relatedStreams"] as? [[String: Any]]) ?? []
        let related = VideoFilter.filterOutShorts(relatedRaw.compactMap { self.parseStreamSummary($0) })

        guard hlsURL != nil || !progressive.isEmpty else {
            return nil
        }

        return StreamInfo(
            video: video,
            hlsURL: hlsURL,
            progressiveStreams: progressive,
            audioOnlyStreams: audioOnly,
            relatedVideos: related,
            providerName: "Piped (\(URL(string: base)?.host ?? base))",
            fetchedAt: Date()
        )
    }

    func fetchComments(videoId: String, completion: @escaping (Result<[CommentItem], Error>) -> Void) {
        let cleanId = YouTubeParsing.extractCleanVideoId(videoId)
        let safeId = cleanId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cleanId
        requestAcrossInstances(pathAndQuery: "/comments/\(safeId)") { result in
            switch result {
            case .success((_, let json)):
                guard let dict = json as? [String: Any],
                      let list = dict["comments"] as? [[String: Any]] else {
                    completion(.success([]))
                    return
                }
                let comments: [CommentItem] = list.compactMap { item in
                    guard let text = item["commentText"] as? String else { return nil }
                    let id = (item["commentId"] as? String) ?? UUID().uuidString
                    let author = (item["author"] as? String) ?? "Người dùng"
                    let avatar = (item["thumbnail"] as? String).flatMap { URL(string: $0) }
                    let likes = (item["likeCount"] as? Int) ?? 0
                    let time = (item["commentedTime"] as? String) ?? ""
                    let replies = (item["replyCount"] as? Int) ?? 0
                    let pinned = (item["pinned"] as? Bool) ?? false
                    let hearted = (item["hearted"] as? Bool) ?? false
                    return CommentItem(
                        id: id,
                        authorName: author,
                        authorAvatarURL: avatar,
                        text: text,
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
        requestAcrossInstances(pathAndQuery: "/channel/\(safeId)") { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success((let base, let json)):
                guard let dict = json as? [String: Any] else {
                    completion(.failure(DataProviderError.decodingError("Piped channel không hợp lệ")))
                    return
                }
                let id = (dict["id"] as? String) ?? channelId
                let name = (dict["name"] as? String) ?? "Kênh YouTube"
                let avatar = self.resolveURL(dict["avatarUrl"] as? String, base: base)
                let banner = self.resolveURL(dict["bannerUrl"] as? String, base: base)
                let subsCount = YouTubeParsing.parseInt64(dict["subscriberCount"])
                let subsText = subsCount > 0 ? "\(subsCount) người đăng ký" : ""
                let desc = (dict["description"] as? String) ?? ""
                let verified = (dict["verified"] as? Bool) ?? false
                let related = (dict["relatedStreams"] as? [[String: Any]]) ?? []
                let videos = VideoFilter.filterOutShorts(related.compactMap {
                    self.parseStreamSummary($0, fallbackChannelId: id, fallbackChannelName: name)
                })
                completion(.success(ChannelItem(
                    id: id,
                    name: name,
                    avatarURL: avatar,
                    bannerURL: banner,
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

    // MARK: - Mapping

    private func parseStreamSummary(
        _ dict: [String: Any],
        fallbackChannelId: String = "",
        fallbackChannelName: String = ""
    ) -> VideoItem? {
        if let type = dict["type"] as? String, type != "stream" {
            return nil
        }
        let rawUrlOrId = (dict["url"] as? String) ?? (dict["id"] as? String) ?? ""
        let videoId = YouTubeParsing.extractCleanVideoId(rawUrlOrId)
        guard !videoId.isEmpty else {
            return nil
        }
        let isShort = (dict["isShort"] as? Bool) ?? rawUrlOrId.contains("/shorts/")
        let title = (dict["title"] as? String) ?? ""
        let chName = (dict["uploaderName"] as? String) ?? fallbackChannelName
        let chId = YouTubeParsing.extractChannelId(from: dict["uploaderUrl"] as? String) ?? fallbackChannelId
        let chAvatar = (dict["uploaderAvatar"] as? String).flatMap { URL(string: $0) }
        let duration = (dict["duration"] as? Int) ?? 0
        let views = YouTubeParsing.parseInt64(dict["views"])
        let uploaded = (dict["uploadedDate"] as? String) ?? ""
        let isLive = (duration < 0) || ((dict["isLive"] as? Bool) ?? false)

        return VideoItem(
            id: videoId,
            title: title,
            channelId: chId,
            channelName: chName,
            channelAvatarURL: chAvatar,
            thumbnailURL: VideoItem.defaultThumbnailURL(for: videoId),
            durationSeconds: max(0, duration),
            viewCount: views,
            uploadedText: uploaded,
            isLive: isLive,
            isShort: isShort
        )
    }
}
