import Foundation

enum MaxVideoQuality: Int, Codable, CaseIterable {
    case p360 = 360
    case p480 = 480
    case p720 = 720

    var displayName: String {
        switch self {
        case .p360: return "360p (Siêu nhẹ RAM)"
        case .p480: return "480p (Khuyên dùng A7)"
        case .p720: return "720p (Tối đa)"
        }
    }

    var shortLabel: String {
        return "\(rawValue)p"
    }

    var preferredPeakBitRate: Double {
        switch self {
        case .p360: return 750_000
        case .p480: return 1_400_000
        case .p720: return 2_800_000
        }
    }
}

struct VideoStreamOption: Codable, Equatable {
    let url: URL
    let itag: Int?
    let mimeType: String
    let qualityLabel: String
    let height: Int
    let bitrate: Int
    let isHLS: Bool
    let isAudioOnly: Bool
    let isH264: Bool

    /// Strict Apple A7 hardware compatibility filter: NEVER allow VP9, AV1, or WebM.
    static func isHardwareCompatible(mimeType: String, codec: String?) -> Bool {
        let combined = (mimeType + " " + (codec ?? "")).lowercased()
        if combined.contains("vp9") || combined.contains("vp09") || combined.contains("vp8") {
            return false
        }
        if combined.contains("av01") || combined.contains("av1") {
            return false
        }
        if combined.contains("webm") || combined.contains("opus") {
            return false
        }
        if combined.contains("avc1") || combined.contains("h264") || combined.contains("mp4a") || combined.contains("mp4") || combined.contains("mpegurl") {
            return true
        }
        return false
    }
}

struct StreamSelection {
    let url: URL
    let isHLS: Bool
    let isAudioOnly: Bool
    let qualityLabel: String
    let peakBitRate: Double
}

struct StreamInfo {
    let video: VideoItem
    let hlsURL: URL?
    let progressiveStreams: [VideoStreamOption]
    let audioOnlyStreams: [VideoStreamOption]
    let relatedVideos: [VideoItem]
    let providerName: String
    let fetchedAt: Date
    let httpHeaders: [String: String]

    init(
        video: VideoItem,
        hlsURL: URL?,
        progressiveStreams: [VideoStreamOption],
        audioOnlyStreams: [VideoStreamOption],
        relatedVideos: [VideoItem],
        providerName: String,
        fetchedAt: Date,
        httpHeaders: [String: String] = [:]
    ) {
        self.video = video
        self.hlsURL = hlsURL
        self.progressiveStreams = progressiveStreams
        self.audioOnlyStreams = audioOnlyStreams
        self.relatedVideos = relatedVideos
        self.providerName = providerName
        self.fetchedAt = fetchedAt
        self.httpHeaders = httpHeaders
    }

    /// Selects the safest hardware-accelerated stream for iPhone 5s (A7).
    /// Priority:
    /// 1. Audio-only M4A/AAC (Itag 140 / 139) when audioOnly == true (fallback to HLS with video track disabled).
    /// 2. HLS (.m3u8) with preferredPeakBitRate capped to maxQuality (480p default, 720p max).
    /// 3. Progressive MP4 (H.264 + AAC, e.g. Itag 18 360p or Itag 22 720p).
    func bestSelection(maxQuality: MaxVideoQuality, audioOnly: Bool) -> StreamSelection? {
        if audioOnly {
            let validAudio = audioOnlyStreams
                .filter { $0.isH264 || $0.mimeType.lowercased().contains("mp4") || $0.itag == 140 || $0.itag == 139 }
                .sorted { abs($0.bitrate - 128_000) < abs($1.bitrate - 128_000) }
            if let bestAudio = validAudio.first {
                return StreamSelection(
                    url: bestAudio.url,
                    isHLS: false,
                    isAudioOnly: true,
                    qualityLabel: "Audio M4A",
                    peakBitRate: 0
                )
            }
            if let hls = hlsURL {
                return StreamSelection(
                    url: hls,
                    isHLS: true,
                    isAudioOnly: true,
                    qualityLabel: "Audio (HLS)",
                    peakBitRate: 192_000
                )
            }
        }

        if let hls = hlsURL {
            return StreamSelection(
                url: hls,
                isHLS: true,
                isAudioOnly: false,
                qualityLabel: "HLS \(maxQuality.shortLabel)",
                peakBitRate: maxQuality.preferredPeakBitRate
            )
        }

        let validProgressive = progressiveStreams.filter { $0.isH264 && !$0.isAudioOnly }
        // Prefer streams <= maxQuality.rawValue, closest to maxQuality, fallback to Itag 18 (360p)
        let withinCap = validProgressive
            .filter { $0.height <= maxQuality.rawValue || $0.itag == 18 }
            .sorted { $0.height > $1.height }
        if let chosen = withinCap.first {
            let label = chosen.qualityLabel.isEmpty ? "\(chosen.height)p MP4" : chosen.qualityLabel
            return StreamSelection(
                url: chosen.url,
                isHLS: false,
                isAudioOnly: false,
                qualityLabel: label,
                peakBitRate: 0
            )
        }

        if let fallback = validProgressive.sorted(by: { $0.height < $1.height }).first {
            return StreamSelection(
                url: fallback.url,
                isHLS: false,
                isAudioOnly: false,
                qualityLabel: fallback.qualityLabel.isEmpty ? "MP4" : fallback.qualityLabel,
                peakBitRate: 0
            )
        }

        return nil
    }
}
