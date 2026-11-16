import UIKit

final class MiniPlayerView: UIView {
    private let progressTrack = UIView()
    private let progressFill = UIView()
    private let thumbnailView = UIImageView()
    private let titleLabel = UILabel()
    private let channelLabel = UILabel()
    private let playPauseButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let topBorder = UIView()

    private var currentVideoId: String?
    private var thumbToken: UUID?

    var onExpandTap: (() -> Void)?
    var onPlayPauseTap: (() -> Void)?
    var onCloseTap: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true

        topBorder.isOpaque = true
        addSubview(topBorder)

        progressTrack.isOpaque = true
        addSubview(progressTrack)

        progressFill.isOpaque = true
        addSubview(progressFill)

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.isOpaque = true
        addSubview(thumbnailView)

        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isOpaque = true
        addSubview(titleLabel)

        channelLabel.font = UIFont.systemFont(ofSize: 11.5)
        channelLabel.lineBreakMode = .byTruncatingTail
        channelLabel.isOpaque = true
        addSubview(channelLabel)

        playPauseButton.setImage(VectorIcons.pause(size: 20), for: .normal)
        playPauseButton.addTarget(self, action: #selector(handlePlayPause), for: .touchUpInside)
        addSubview(playPauseButton)

        closeButton.setImage(VectorIcons.close(size: 18), for: .normal)
        closeButton.addTarget(self, action: #selector(handleClose), for: .touchUpInside)
        addSubview(closeButton)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        addGestureRecognizer(tap)

        NotificationCenter.default.addObserver(self, selector: #selector(refreshFromPlayer), name: .playerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshFromPlayer), name: .playerStreamInfoDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateProgress), name: .playerProgressDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height

        topBorder.frame = CGRect(x: 0, y: 0, width: w, height: 0.5)
        progressTrack.frame = CGRect(x: 0, y: 0.5, width: w, height: 2)
        updateProgressFrame()

        let thumbH = h - 2.5
        let thumbW = floor(thumbH * 16.0 / 9.0)
        thumbnailView.frame = CGRect(x: 0, y: 2.5, width: thumbW, height: thumbH)

        let btnSize: CGFloat = 40
        closeButton.frame = CGRect(x: w - btnSize - 4, y: (h - btnSize) * 0.5, width: btnSize, height: btnSize)
        playPauseButton.frame = CGRect(x: closeButton.frame.minX - btnSize, y: (h - btnSize) * 0.5, width: btnSize, height: btnSize)

        let textX = thumbW + 10
        let textW = max(40, playPauseButton.frame.minX - textX - 6)
        titleLabel.frame = CGRect(x: textX, y: 10, width: textW, height: 18)
        channelLabel.frame = CGRect(x: textX, y: 30, width: textW, height: 15)
    }

    @objc private func handleThemeChange() {
        applyTheme()
    }

    func applyTheme() {
        let p = ThemeManager.shared.palette
        backgroundColor = p.elevatedBackground
        topBorder.backgroundColor = p.separator
        progressTrack.backgroundColor = p.separator
        progressFill.backgroundColor = p.accent
        thumbnailView.backgroundColor = p.secondaryBackground
        titleLabel.backgroundColor = p.elevatedBackground
        titleLabel.textColor = p.primaryText
        channelLabel.backgroundColor = p.elevatedBackground
        channelLabel.textColor = p.secondaryText
        playPauseButton.tintColor = p.primaryText
        closeButton.tintColor = p.secondaryText
    }

    @objc func refreshFromPlayer() {
        let pm = PlayerManager.shared
        guard let video = pm.currentVideo else {
            currentVideoId = nil
            thumbnailView.image = nil
            return
        }

        titleLabel.text = video.title
        channelLabel.text = pm.isAudioOnly ? "Chỉ nghe • \(video.channelName)" : video.channelName

        let icon = pm.isPlaying ? VectorIcons.pause(size: 20) : VectorIcons.play(size: 20)
        playPauseButton.setImage(icon, for: .normal)

        if currentVideoId != video.id {
            currentVideoId = video.id
            ImageLoader.shared.cancel(thumbToken)
            thumbToken = ImageLoader.shared.loadImage(from: video.thumbnailURL, targetSize: CGSize(width: 160, height: 90), circular: false) { [weak self] img in
                guard let self = self, self.currentVideoId == video.id else { return }
                self.thumbnailView.image = img
            }
        }
        updateProgressFrame()
    }

    @objc private func updateProgress() {
        updateProgressFrame()
    }

    private func updateProgressFrame() {
        let pm = PlayerManager.shared
        let ratio: CGFloat
        if pm.duration > 0 {
            ratio = min(1.0, max(0.0, CGFloat(pm.currentTime / pm.duration)))
        } else {
            ratio = 0
        }
        progressFill.frame = CGRect(x: 0, y: 0.5, width: bounds.width * ratio, height: 2)
    }

    @objc private func handleTap() {
        onExpandTap?()
    }

    @objc private func handlePlayPause() {
        onPlayPauseTap?()
    }

    @objc private func handleClose() {
        onCloseTap?()
    }
}
