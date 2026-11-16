import UIKit
import MediaPlayer

final class NowPlayingController {
    static let shared = NowPlayingController()

    private var currentVideoId: String?
    private var cachedArtwork: MPMediaItemArtwork?
    private var imageToken: UUID?
    private var commandsConfigured = false

    private init() {}

    func configureRemoteCommandsIfNeeded(
        onPlay: @escaping () -> Void,
        onPause: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSeekRelative: @escaping (TimeInterval) -> Void,
        onSeekAbsolute: @escaping (TimeInterval) -> Void
    ) {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = true
        cc.playCommand.addTarget { _ in
            onPlay()
            return .success
        }

        cc.pauseCommand.isEnabled = true
        cc.pauseCommand.addTarget { _ in
            onPause()
            return .success
        }

        cc.togglePlayPauseCommand.isEnabled = true
        cc.togglePlayPauseCommand.addTarget { _ in
            onToggle()
            return .success
        }

        cc.skipForwardCommand.isEnabled = true
        cc.skipForwardCommand.preferredIntervals = [15]
        cc.skipForwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            onSeekRelative(interval)
            return .success
        }

        cc.skipBackwardCommand.isEnabled = true
        cc.skipBackwardCommand.preferredIntervals = [15]
        cc.skipBackwardCommand.addTarget { event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 15
            onSeekRelative(-interval)
            return .success
        }

        cc.changePlaybackPositionCommand.isEnabled = true
        cc.changePlaybackPositionCommand.addTarget { event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            onSeekAbsolute(posEvent.positionTime)
            return .success
        }
    }

    func update(
        video: VideoItem?,
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        guard let video = video else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            currentVideoId = nil
            cachedArtwork = nil
            return
        }

        if currentVideoId != video.id {
            currentVideoId = video.id
            cachedArtwork = nil
            ImageLoader.shared.cancel(imageToken)
            imageToken = ImageLoader.shared.loadImage(from: video.thumbnailURL, targetSize: CGSize(width: 320, height: 180), circular: false) { [weak self] image in
                guard let self = self, self.currentVideoId == video.id, let img = image else { return }
                self.cachedArtwork = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
                self.applyNowPlayingDict(video: video, elapsed: elapsed, duration: duration, isPlaying: isPlaying)
            }
        }

        applyNowPlayingDict(video: video, elapsed: elapsed, duration: duration, isPlaying: isPlaying)
    }

    private func applyNowPlayingDict(
        video: VideoItem,
        elapsed: TimeInterval,
        duration: TimeInterval,
        isPlaying: Bool
    ) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: video.title,
            MPMediaItemPropertyArtist: video.channelName,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: max(0, elapsed),
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
        if duration > 0 && duration.isFinite {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        if let artwork = cachedArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
