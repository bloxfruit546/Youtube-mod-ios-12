import UIKit
import AVFoundation

extension Notification.Name {
    static let playerStateDidChange = Notification.Name("com.litetube5s.playerStateDidChange")
    static let playerProgressDidUpdate = Notification.Name("com.litetube5s.playerProgressDidUpdate")
    static let playerStreamInfoDidUpdate = Notification.Name("com.litetube5s.playerStreamInfoDidUpdate")
}

enum PlayerState: Equatable {
    case idle
    case loading
    case playing
    case paused
    case failed(String)
}

final class PlayerManager: NSObject {
    static let shared = PlayerManager()

    let player: AVPlayer = {
        let p = AVPlayer()
        p.automaticallyWaitsToMinimizeStalling = true
        return p
    }()

    let playerLayer: AVPlayerLayer

    private(set) var state: PlayerState = .idle {
        didSet {
            if state != oldValue {
                NotificationCenter.default.post(name: .playerStateDidChange, object: self)
            }
        }
    }

    private(set) var currentVideo: VideoItem?
    private(set) var currentStreamInfo: StreamInfo?
    private(set) var currentSelection: StreamSelection?
    private(set) var isAudioOnly: Bool = LocalStore.shared.settings.audioOnlyDefault
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0

    private var isInBackground = false
    private var timeObserverToken: Any?
    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var likelyKeepUpObservation: NSKeyValueObservation?
    private var expiredRetryCount = 0
    private var lastHistorySaveTime: Date = .distantPast
    private var activeLoadId: UUID?

    private override init() {
        self.playerLayer = AVPlayerLayer(player: player)
        self.playerLayer.videoGravity = .resizeAspect
        super.init()

        setupObservers()
        setupRemoteCommands()
    }

    deinit {
        if let token = timeObserverToken {
            player.removeTimeObserver(token)
        }
        NotificationCenter.default.removeObserver(self)
    }

    private func setupObservers() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 2)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let sec = CMTimeGetSeconds(time)
            if sec.isFinite && sec >= 0 {
                self.currentTime = sec
            }
            if let item = self.player.currentItem {
                let dur = CMTimeGetSeconds(item.duration)
                if dur.isFinite && dur > 0 {
                    self.duration = dur
                }
            }
            NowPlayingController.shared.update(
                video: self.currentVideo,
                elapsed: self.currentTime,
                duration: self.duration,
                isPlaying: self.isPlaying
            )
            NotificationCenter.default.post(name: .playerProgressDidUpdate, object: self)

            // Save playback position every 10 seconds
            if let video = self.currentVideo, Date().timeIntervalSince(self.lastHistorySaveTime) >= 10.0 {
                self.lastHistorySaveTime = Date()
                LocalStore.shared.recordHistory(video: video, positionSeconds: self.currentTime)
            }
        }

        rateObservation = player.observe(\.rate, options: [.new]) { [weak self] player, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if case .loading = self.state { return }
                if case .failed = self.state { return }
                if case .idle = self.state { return }
                self.state = player.rate > 0 ? .playing : .paused
                NowPlayingController.shared.update(
                    video: self.currentVideo,
                    elapsed: self.currentTime,
                    duration: self.duration,
                    isPlaying: player.rate > 0
                )
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePlaybackDidEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleItemFailedToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: nil
        )
    }

    private func setupRemoteCommands() {
        NowPlayingController.shared.configureRemoteCommandsIfNeeded(
            onPlay: { [weak self] in self?.play() },
            onPause: { [weak self] in self?.pause() },
            onToggle: { [weak self] in self?.togglePlayPause() },
            onSeekRelative: { [weak self] delta in
                guard let self = self else { return }
                self.seek(to: self.currentTime + delta)
            },
            onSeekAbsolute: { [weak self] pos in
                self?.seek(to: pos)
            }
        )
    }

    var isPlaying: Bool {
        return player.rate > 0 && player.error == nil
    }

    // MARK: - Load & Play

    func load(video: VideoItem, startAt: Double? = nil) {
        let loadId = UUID()
        activeLoadId = loadId
        expiredRetryCount = 0

        currentVideo = video
        currentStreamInfo = nil
        currentSelection = nil
        duration = Double(video.durationSeconds)
        currentTime = startAt ?? 0
        isAudioOnly = LocalStore.shared.settings.audioOnlyDefault
        state = .loading

        player.pause()
        clearItemObservations()
        player.replaceCurrentItem(with: nil)

        NotificationCenter.default.post(name: .playerStreamInfoDidUpdate, object: self)
        LocalStore.shared.recordHistory(video: video, positionSeconds: currentTime)
        NowPlayingController.shared.update(video: video, elapsed: currentTime, duration: duration, isPlaying: false)

        AppLogger.shared.info("Loading video \(video.id): \(video.title)")

        ProviderManager.shared.fetchVideoDetailsAndStreams(videoId: video.id) { [weak self] result in
            guard let self = self, self.activeLoadId == loadId else { return }
            switch result {
            case .success(let info):
                self.currentVideo = info.video
                self.currentStreamInfo = info
                if info.video.durationSeconds > 0 {
                    self.duration = Double(info.video.durationSeconds)
                }
                NotificationCenter.default.post(name: .playerStreamInfoDidUpdate, object: self)
                self.prepareAndPlay(from: info, seekTo: startAt)
            case .failure(let error):
                AppLogger.shared.error("Failed to fetch stream for \(video.id): \(error.localizedDescription)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    func retryCurrentVideo() {
        guard let video = currentVideo else { return }
        let resumeTime = currentTime > 2 ? currentTime : nil
        load(video: video, startAt: resumeTime)
    }

    func setAudioOnly(_ enabled: Bool) {
        guard isAudioOnly != enabled else { return }
        isAudioOnly = enabled
        guard let info = currentStreamInfo else { return }
        let resume = currentTime
        prepareAndPlay(from: info, seekTo: resume)
    }

    func applyQualityChange() {
        guard let info = currentStreamInfo else { return }
        let resume = currentTime
        prepareAndPlay(from: info, seekTo: resume)
    }

    private func prepareAndPlay(from info: StreamInfo, seekTo: Double?) {
        let maxQuality = LocalStore.shared.settings.maxQuality
        guard let selection = info.bestSelection(maxQuality: maxQuality, audioOnly: isAudioOnly) else {
            state = .failed(DataProviderError.noPlayableH264Stream.localizedDescription)
            return
        }

        currentSelection = selection
        state = .loading

        let headers: [String: String]
        if !info.httpHeaders.isEmpty {
            headers = info.httpHeaders
        } else {
            headers = [
                "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                "Origin": "https://www.youtube.com",
                "Referer": "https://www.youtube.com/"
            ]
        }
        let asset = AVURLAsset(url: selection.url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": headers
        ])
        let item = AVPlayerItem(asset: asset)
        // Strictly bound forward buffer on iPhone 5s 1GB RAM
        item.preferredForwardBufferDuration = 15.0
        if selection.peakBitRate > 0 {
            item.preferredPeakBitRate = selection.peakBitRate
        }

        clearItemObservations()

        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    let dur = CMTimeGetSeconds(item.duration)
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                    if selection.isAudioOnly && selection.isHLS {
                        self.setVideoTracksEnabled(false, on: item)
                    }
                    if let target = seekTo, target > 1.0 {
                        let cm = CMTime(seconds: target, preferredTimescale: 600)
                        item.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
                            self.player.play()
                            self.state = .playing
                        }
                    } else {
                        self.player.play()
                        self.state = .playing
                    }
                    AppLogger.shared.info("Playing [\(selection.qualityLabel)] via \(info.providerName)")
                case .failed:
                    let msg = item.error?.localizedDescription ?? "Lỗi AVPlayerItem"
                    AppLogger.shared.error("AVPlayerItem failed: \(msg)")
                    self.attemptStreamRefreshIfNeeded(reason: msg)
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.isPlaybackBufferEmpty {
                DispatchQueue.main.async {
                    if self.isPlaying {
                        self.state = .loading
                    }
                }
            }
        }

        likelyKeepUpObservation = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] item, _ in
            guard let self = self else { return }
            if item.isPlaybackLikelyToKeepUp {
                DispatchQueue.main.async {
                    if case .loading = self.state {
                        self.state = self.player.rate > 0 ? .playing : .paused
                    }
                }
            }
        }

        player.replaceCurrentItem(with: item)
        if !isInBackground {
            playerLayer.player = player
        }
        NotificationCenter.default.post(name: .playerStreamInfoDidUpdate, object: self)
    }

    private func setVideoTracksEnabled(_ enabled: Bool, on item: AVPlayerItem?) {
        guard let item = item else { return }
        for track in item.tracks {
            if track.assetTrack?.mediaType == .video {
                track.isEnabled = enabled
            }
        }
    }

    private func attemptStreamRefreshIfNeeded(reason: String) {
        guard let video = currentVideo, expiredRetryCount < 2 else {
            state = .failed(reason)
            return
        }
        expiredRetryCount += 1
        let resumeTime = currentTime
        AppLogger.shared.warn("Refreshing expired stream (attempt \(expiredRetryCount)) at \(Int(resumeTime))s")
        state = .loading
        let loadId = UUID()
        activeLoadId = loadId

        ProviderManager.shared.fetchVideoDetailsAndStreams(videoId: video.id) { [weak self] result in
            guard let self = self, self.activeLoadId == loadId else { return }
            switch result {
            case .success(let info):
                self.currentStreamInfo = info
                self.prepareAndPlay(from: info, seekTo: resumeTime)
            case .failure(let err):
                self.state = .failed(err.localizedDescription)
            }
        }
    }

    private func clearItemObservations() {
        statusObservation?.invalidate()
        statusObservation = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        likelyKeepUpObservation?.invalidate()
        likelyKeepUpObservation = nil
    }

    // MARK: - Playback Controls

    func play() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player.play()
        state = .playing
    }

    func pause() {
        player.pause()
        state = .paused
        if let video = currentVideo {
            LocalStore.shared.recordHistory(video: video, positionSeconds: currentTime)
        }
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to seconds: Double) {
        let clamped = max(0, duration > 0 ? min(seconds, duration) : seconds)
        currentTime = clamped
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        NowPlayingController.shared.update(
            video: currentVideo,
            elapsed: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }

    func stopAndClear() {
        activeLoadId = nil
        if let video = currentVideo {
            LocalStore.shared.recordHistory(video: video, positionSeconds: currentTime)
        }
        player.pause()
        clearItemObservations()
        player.replaceCurrentItem(with: nil)
        currentVideo = nil
        currentStreamInfo = nil
        currentSelection = nil
        currentTime = 0
        duration = 0
        state = .idle
        NowPlayingController.shared.update(video: nil, elapsed: 0, duration: 0, isPlaying: false)
    }

    // MARK: - Background Battery Optimization

    func handleEnterBackground() {
        isInBackground = true
        let wasPlaying = isPlaying
        // Detach player from AVPlayerLayer & disable video tracks so A7 stops decoding/rendering video frames
        playerLayer.player = nil
        setVideoTracksEnabled(false, on: player.currentItem)
        if let video = currentVideo {
            LocalStore.shared.recordHistory(video: video, positionSeconds: currentTime)
        }
        // Guard against iOS 12 pausing HLS playback when playerLayer is detached
        if wasPlaying {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                guard let self = self, self.isInBackground else { return }
                if self.player.rate == 0 {
                    self.player.play()
                }
            }
        }
    }

    func handleEnterForeground() {
        isInBackground = false
        playerLayer.player = player
        if !isAudioOnly {
            setVideoTracksEnabled(true, on: player.currentItem)
        }
    }

    // MARK: - Notifications

    @objc private func handlePlaybackDidEnd(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else { return }
        state = .paused
        seek(to: 0)
        pause()
    }

    @objc private func handleItemFailedToPlayToEnd(_ note: Notification) {
        guard (note.object as? AVPlayerItem) === player.currentItem else { return }
        let err = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        attemptStreamRefreshIfNeeded(reason: err?.localizedDescription ?? "Lỗi phát luồng (403/Timeout)")
    }
}
