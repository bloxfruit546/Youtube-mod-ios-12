import UIKit
import AVFoundation

/// Lightweight Comment cell with manual frame layout (NO Auto Layout inside UITableViewCell).
final class CommentCell: UITableViewCell {
    static let reuseIdentifier = "CommentCell"

    private let avatarView = UIImageView()
    private let authorLabel = UILabel()
    private let bodyLabel = UILabel()
    private let metaLabel = UILabel()
    private let separatorLine = UIView()

    private var avatarToken: UUID?
    private var currentCommentId: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        isOpaque = true
        contentView.isOpaque = true

        avatarView.contentMode = .scaleAspectFit
        avatarView.isOpaque = false
        contentView.addSubview(avatarView)

        authorLabel.font = UIFont.boldSystemFont(ofSize: 12)
        authorLabel.isOpaque = true
        contentView.addSubview(authorLabel)

        bodyLabel.font = UIFont.systemFont(ofSize: 13.5)
        bodyLabel.numberOfLines = 0
        bodyLabel.isOpaque = true
        contentView.addSubview(bodyLabel)

        metaLabel.font = UIFont.systemFont(ofSize: 11.5)
        metaLabel.isOpaque = true
        contentView.addSubview(metaLabel)

        separatorLine.isOpaque = true
        contentView.addSubview(separatorLine)
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func applyTheme() {
        let p = ThemeManager.shared.palette
        backgroundColor = p.background
        contentView.backgroundColor = p.background
        authorLabel.backgroundColor = p.background
        authorLabel.textColor = p.secondaryText
        bodyLabel.backgroundColor = p.background
        bodyLabel.textColor = p.primaryText
        metaLabel.backgroundColor = p.background
        metaLabel.textColor = p.secondaryText
        separatorLine.backgroundColor = p.separator
    }

    static func height(for comment: CommentItem, width: CGFloat) -> CGFloat {
        let textW = max(80, width - 58 - 12)
        let bodyRect = (comment.text as NSString).boundingRect(
            with: CGSize(width: textW, height: 600),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 13.5)],
            context: nil
        )
        return 10 + 16 + 4 + ceil(bodyRect.height) + 6 + 16 + 10
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height
        avatarView.frame = CGRect(x: 12, y: 12, width: 32, height: 32)
        let textX: CGFloat = 54
        let textW = max(80, w - textX - 12)
        authorLabel.frame = CGRect(x: textX, y: 10, width: textW, height: 16)
        let bodyH = max(18, h - 10 - 16 - 4 - 6 - 16 - 10)
        bodyLabel.frame = CGRect(x: textX, y: 30, width: textW, height: bodyH)
        metaLabel.frame = CGRect(x: textX, y: bodyLabel.frame.maxY + 6, width: textW, height: 16)
        separatorLine.frame = CGRect(x: 0, y: h - 0.5, width: w, height: 0.5)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancel(avatarToken)
        avatarToken = nil
        currentCommentId = nil
        avatarView.image = nil
        authorLabel.text = nil
        bodyLabel.text = nil
        metaLabel.text = nil
    }

    func configure(with comment: CommentItem) {
        applyTheme()
        currentCommentId = comment.id
        let pinPrefix = comment.isPinned ? "[Ghim] " : ""
        authorLabel.text = "\(pinPrefix)\(comment.authorName) • \(comment.publishedText)"
        bodyLabel.text = comment.text
        var metaParts: [String] = []
        if comment.likeCount > 0 { metaParts.append("Thích: \(comment.likeCount)") }
        if comment.replyCount > 0 { metaParts.append("\(comment.replyCount) phản hồi") }
        if comment.isHearted { metaParts.append("♥ Tác giả thích") }
        metaLabel.text = metaParts.joined(separator: " • ")

        ImageLoader.shared.cancel(avatarToken)
        let expectedId = comment.id
        avatarToken = ImageLoader.shared.loadImage(from: comment.authorAvatarURL, targetSize: CGSize(width: 32, height: 32), circular: true) { [weak self] img in
            guard let self = self, self.currentCommentId == expectedId else { return }
            self.avatarView.image = img
        }
        setNeedsLayout()
    }
}

final class WatchViewController: UIViewController {
    // Exposed so RootContainerViewController can attach UIPanGestureRecognizer cleanly
    let playerContainerView = UIView()

    private let audioOnlyOverlayView = UIView()
    private let audioOnlyOverlayLabel = UILabel()
    private let controlsOverlay = UIView()
    private let minimizeButton = UIButton(type: .system)
    private let audioOnlyTopButton = UIButton(type: .system)
    private let qualityBadgeButton = UIButton(type: .system)
    private let centerPlayPauseButton = UIButton(type: .system)
    private let rewindButton = UIButton(type: .system)
    private let forwardButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)
    private let errorOverlayLabel = UILabel()
    private let retryPlayerButton = UIButton(type: .system)

    private let elapsedLabel = UILabel()
    private let durationLabel = UILabel()
    private let seekSlider = UISlider()
    private let fullscreenButton = UIButton(type: .system)

    private let tableView = UITableView(frame: .zero, style: .plain)

    // TableHeaderView containing Video Info, Actions, Channel bar, and Segment switcher
    private let infoHeaderView = UIView()
    private let videoTitleLabel = UILabel()
    private let videoMetaLabel = UILabel()
    private let providerLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let toggleDescButton = UIButton(type: .system)

    private let actionBarStack = UIView()
    private let audioOnlyActionButton = UIButton(type: .system)
    private let watchLaterButton = UIButton(type: .system)
    private let qualityActionButton = UIButton(type: .system)
    private let copyLinkButton = UIButton(type: .system)

    private let channelBarView = UIView()
    private let channelAvatarView = UIImageView()
    private let channelNameLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let segmentControl = UISegmentedControl(items: ["Video liên quan", "Bình luận"])

    private var isDescriptionExpanded = false
    private var isControlsVisible = true
    private var isUserScrubbing = false
    private var hideControlsWorkItem: DispatchWorkItem?
    private var channelAvatarToken: UUID?

    private var relatedVideos: [VideoItem] = []
    private var comments: [CommentItem] = []
    private var isLoadingComments = false
    private var commentsLoadedForVideoId: String?

    var isFullscreen = false {
        didSet {
            onFullscreenChanged?(isFullscreen)
            view.setNeedsLayout()
        }
    }

    var onMinimizeRequested: (() -> Void)?
    var onFullscreenChanged: ((Bool) -> Void)?
    var onOpenChannel: ((String, String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPlayerContainer()
        setupTableView()
        setupInfoHeader()
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(handlePlayerState), name: .playerStateDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handlePlayerProgress), name: .playerProgressDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleStreamInfoUpdated), name: .playerStreamInfoDidUpdate, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshChannelSubscribeState), name: .subscriptionsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshWatchLaterState), name: .playlistsDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupPlayerContainer() {
        playerContainerView.backgroundColor = .black
        playerContainerView.clipsToBounds = true
        view.addSubview(playerContainerView)

        let layer = PlayerManager.shared.playerLayer
        layer.backgroundColor = UIColor.black.cgColor
        playerContainerView.layer.addSublayer(layer)

        // Audio-Only overlay
        audioOnlyOverlayView.backgroundColor = UIColor(white: 0.08, alpha: 1.0)
        audioOnlyOverlayView.isHidden = true
        playerContainerView.addSubview(audioOnlyOverlayView)

        audioOnlyOverlayLabel.textColor = .white
        audioOnlyOverlayLabel.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        audioOnlyOverlayLabel.textAlignment = .center
        audioOnlyOverlayLabel.numberOfLines = 2
        audioOnlyOverlayLabel.text = "Chế độ Chỉ nghe (Audio-Only)\nTiết kiệm pin & RAM cho iPhone 5s"
        audioOnlyOverlayView.addSubview(audioOnlyOverlayLabel)

        // Controls overlay
        controlsOverlay.backgroundColor = UIColor(white: 0, alpha: 0.45)
        playerContainerView.addSubview(controlsOverlay)

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleControlsOverlay))
        tap.cancelsTouchesInView = false
        tap.delegate = self
        playerContainerView.addGestureRecognizer(tap)

        minimizeButton.setImage(VectorIcons.chevronDown(size: 20), for: .normal)
        minimizeButton.tintColor = .white
        minimizeButton.addTarget(self, action: #selector(handleMinimizeTap), for: .touchUpInside)
        controlsOverlay.addSubview(minimizeButton)

        audioOnlyTopButton.setImage(VectorIcons.headphones(size: 18), for: .normal)
        audioOnlyTopButton.tintColor = .white
        audioOnlyTopButton.addTarget(self, action: #selector(handleAudioOnlyToggle), for: .touchUpInside)
        controlsOverlay.addSubview(audioOnlyTopButton)

        qualityBadgeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 11)
        qualityBadgeButton.setTitleColor(.white, for: .normal)
        qualityBadgeButton.backgroundColor = UIColor(white: 0.15, alpha: 0.85)
        qualityBadgeButton.contentEdgeInsets = UIEdgeInsets(top: 3, left: 6, bottom: 3, right: 6)
        qualityBadgeButton.addTarget(self, action: #selector(handleQualityTap), for: .touchUpInside)
        controlsOverlay.addSubview(qualityBadgeButton)

        centerPlayPauseButton.setImage(VectorIcons.pause(size: 36), for: .normal)
        centerPlayPauseButton.tintColor = .white
        centerPlayPauseButton.addTarget(self, action: #selector(handlePlayPauseTap), for: .touchUpInside)
        controlsOverlay.addSubview(centerPlayPauseButton)

        rewindButton.setTitle("-15s", for: .normal)
        rewindButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        rewindButton.setTitleColor(.white, for: .normal)
        rewindButton.addTarget(self, action: #selector(handleRewind15), for: .touchUpInside)
        controlsOverlay.addSubview(rewindButton)

        forwardButton.setTitle("+15s", for: .normal)
        forwardButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        forwardButton.setTitleColor(.white, for: .normal)
        forwardButton.addTarget(self, action: #selector(handleForward15), for: .touchUpInside)
        controlsOverlay.addSubview(forwardButton)

        spinner.hidesWhenStopped = true
        playerContainerView.addSubview(spinner)

        errorOverlayLabel.textColor = .white
        errorOverlayLabel.font = UIFont.systemFont(ofSize: 10.5)
        errorOverlayLabel.textAlignment = .center
        errorOverlayLabel.numberOfLines = 0
        errorOverlayLabel.adjustsFontSizeToFitWidth = true
        errorOverlayLabel.minimumScaleFactor = 0.75
        errorOverlayLabel.isHidden = true
        playerContainerView.addSubview(errorOverlayLabel)

        retryPlayerButton.setTitle("Thử lại", for: .normal)
        retryPlayerButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        retryPlayerButton.setTitleColor(.white, for: .normal)
        retryPlayerButton.backgroundColor = UIColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1.0)
        retryPlayerButton.isHidden = true
        retryPlayerButton.addTarget(self, action: #selector(handleRetryPlayer), for: .touchUpInside)
        playerContainerView.addSubview(retryPlayerButton)

        elapsedLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        elapsedLabel.textColor = .white
        elapsedLabel.text = "0:00"
        controlsOverlay.addSubview(elapsedLabel)

        durationLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        durationLabel.textColor = .white
        durationLabel.textAlignment = .right
        durationLabel.text = "0:00"
        controlsOverlay.addSubview(durationLabel)

        seekSlider.minimumTrackTintColor = UIColor.red
        seekSlider.maximumTrackTintColor = UIColor(white: 1.0, alpha: 0.35)
        seekSlider.thumbTintColor = .red
        seekSlider.addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        seekSlider.addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        seekSlider.addTarget(self, action: #selector(sliderTouchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        controlsOverlay.addSubview(seekSlider)

        fullscreenButton.setImage(VectorIcons.fullscreen(size: 18), for: .normal)
        fullscreenButton.tintColor = .white
        fullscreenButton.addTarget(self, action: #selector(handleFullscreenTap), for: .touchUpInside)
        controlsOverlay.addSubview(fullscreenButton)
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(VideoCardCell.self, forCellReuseIdentifier: VideoCardCell.reuseIdentifier)
        tableView.register(CommentCell.self, forCellReuseIdentifier: CommentCell.reuseIdentifier)
        view.addSubview(tableView)
    }

    private func setupInfoHeader() {
        infoHeaderView.isOpaque = true

        videoTitleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        videoTitleLabel.numberOfLines = 3
        videoTitleLabel.isOpaque = true
        infoHeaderView.addSubview(videoTitleLabel)

        videoMetaLabel.font = UIFont.systemFont(ofSize: 12.5)
        videoMetaLabel.numberOfLines = 1
        videoMetaLabel.isOpaque = true
        infoHeaderView.addSubview(videoMetaLabel)

        providerLabel.font = UIFont.systemFont(ofSize: 11.5)
        providerLabel.numberOfLines = 0
        providerLabel.isOpaque = true
        infoHeaderView.addSubview(providerLabel)

        toggleDescButton.setTitle("Xem mô tả", for: .normal)
        toggleDescButton.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        toggleDescButton.contentHorizontalAlignment = .left
        toggleDescButton.addTarget(self, action: #selector(handleToggleDescription), for: .touchUpInside)
        infoHeaderView.addSubview(toggleDescButton)

        descriptionLabel.font = UIFont.systemFont(ofSize: 12.5)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.isHidden = true
        descriptionLabel.isOpaque = true
        infoHeaderView.addSubview(descriptionLabel)

        // Action bar
        actionBarStack.isOpaque = true
        infoHeaderView.addSubview(actionBarStack)

        for btn in [audioOnlyActionButton, watchLaterButton, qualityActionButton, copyLinkButton] {
            btn.titleLabel?.font = UIFont.systemFont(ofSize: 12, weight: .medium)
            btn.titleLabel?.numberOfLines = 1
            actionBarStack.addSubview(btn)
        }
        audioOnlyActionButton.setTitle("Chỉ nghe", for: .normal)
        audioOnlyActionButton.addTarget(self, action: #selector(handleAudioOnlyToggle), for: .touchUpInside)

        watchLaterButton.setTitle("Xem sau", for: .normal)
        watchLaterButton.addTarget(self, action: #selector(handleWatchLaterTap), for: .touchUpInside)

        qualityActionButton.setTitle("Chất lượng", for: .normal)
        qualityActionButton.addTarget(self, action: #selector(handleQualityTap), for: .touchUpInside)

        copyLinkButton.setTitle("Chép link", for: .normal)
        copyLinkButton.addTarget(self, action: #selector(handleCopyLinkTap), for: .touchUpInside)

        // Channel bar
        channelBarView.isOpaque = true
        infoHeaderView.addSubview(channelBarView)

        channelAvatarView.contentMode = .scaleAspectFit
        channelAvatarView.isOpaque = false
        channelBarView.addSubview(channelAvatarView)

        channelNameLabel.font = UIFont.boldSystemFont(ofSize: 14)
        channelNameLabel.isOpaque = true
        channelBarView.addSubview(channelNameLabel)

        let chTap = UITapGestureRecognizer(target: self, action: #selector(handleChannelTap))
        channelBarView.addGestureRecognizer(chTap)

        subscribeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        subscribeButton.addTarget(self, action: #selector(handleSubscribeTap), for: .touchUpInside)
        channelBarView.addSubview(subscribeButton)

        segmentControl.selectedSegmentIndex = 0
        segmentControl.addTarget(self, action: #selector(handleSegmentChanged), for: .valueChanged)
        infoHeaderView.addSubview(segmentControl)
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background

        infoHeaderView.backgroundColor = p.background
        videoTitleLabel.backgroundColor = p.background
        videoTitleLabel.textColor = p.primaryText
        videoMetaLabel.backgroundColor = p.background
        videoMetaLabel.textColor = p.secondaryText
        providerLabel.backgroundColor = p.background
        providerLabel.textColor = p.secondaryText
        toggleDescButton.setTitleColor(p.accent, for: .normal)
        descriptionLabel.backgroundColor = p.secondaryBackground
        descriptionLabel.textColor = p.primaryText

        actionBarStack.backgroundColor = p.background
        for btn in [audioOnlyActionButton, watchLaterButton, qualityActionButton, copyLinkButton] {
            btn.backgroundColor = p.secondaryBackground
            btn.setTitleColor(p.primaryText, for: .normal)
        }

        channelBarView.backgroundColor = p.background
        channelNameLabel.backgroundColor = p.background
        channelNameLabel.textColor = p.primaryText
        segmentControl.tintColor = p.accent

        refreshAudioOnlyVisuals()
        refreshChannelSubscribeState()
        refreshWatchLaterState()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        let h = view.bounds.height
        let topInset: CGFloat
        if #available(iOS 11.0, *) {
            topInset = isFullscreen ? 0 : view.safeAreaInsets.top
        } else {
            topInset = isFullscreen ? 0 : 20
        }

        if isFullscreen {
            playerContainerView.frame = view.bounds
            tableView.isHidden = true
        } else {
            let playerH = floor(w * 9.0 / 16.0)
            playerContainerView.frame = CGRect(x: 0, y: topInset, width: w, height: playerH)
            tableView.isHidden = false
            tableView.frame = CGRect(x: 0, y: playerContainerView.frame.maxY, width: w, height: max(0, h - playerContainerView.frame.maxY))
        }

        layoutPlayerSublayersAndControls()
        layoutInfoHeader(forWidth: w)
    }

    private func layoutPlayerSublayersAndControls() {
        let bounds = playerContainerView.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        PlayerManager.shared.playerLayer.frame = bounds
        CATransaction.commit()

        audioOnlyOverlayView.frame = bounds
        audioOnlyOverlayLabel.frame = bounds.insetBy(dx: 24, dy: 20)

        controlsOverlay.frame = bounds
        let cw = bounds.width
        let ch = bounds.height

        minimizeButton.frame = CGRect(x: 8, y: 8, width: 34, height: 34)
        audioOnlyTopButton.frame = CGRect(x: cw - 42, y: 8, width: 34, height: 34)
        qualityBadgeButton.sizeToFit()
        let qbW = max(54, qualityBadgeButton.bounds.width + 8)
        qualityBadgeButton.frame = CGRect(x: audioOnlyTopButton.frame.minX - qbW - 8, y: 13, width: qbW, height: 24)

        centerPlayPauseButton.frame = CGRect(x: (cw - 52) * 0.5, y: (ch - 52) * 0.5, width: 52, height: 52)
        rewindButton.frame = CGRect(x: centerPlayPauseButton.frame.minX - 66, y: (ch - 40) * 0.5, width: 50, height: 40)
        forwardButton.frame = CGRect(x: centerPlayPauseButton.frame.maxX + 16, y: (ch - 40) * 0.5, width: 50, height: 40)

        spinner.center = CGPoint(x: cw * 0.5, y: ch * 0.5)
        errorOverlayLabel.frame = CGRect(x: 10, y: 12, width: max(60, cw - 20), height: max(40, ch - 56))
        retryPlayerButton.frame = CGRect(x: (cw - 100) * 0.5, y: ch - 40, width: 100, height: 30)

        let bottomY = ch - 34
        elapsedLabel.frame = CGRect(x: 8, y: bottomY, width: 46, height: 26)
        fullscreenButton.frame = CGRect(x: cw - 38, y: bottomY - 2, width: 32, height: 30)
        durationLabel.frame = CGRect(x: fullscreenButton.frame.minX - 50, y: bottomY, width: 46, height: 26)
        seekSlider.frame = CGRect(
            x: elapsedLabel.frame.maxX + 6,
            y: bottomY - 2,
            width: max(40, durationLabel.frame.minX - elapsedLabel.frame.maxX - 12),
            height: 30
        )
    }

    private func layoutInfoHeader(forWidth w: CGFloat) {
        let pad: CGFloat = 12
        let contentW = max(120, w - pad * 2)
        var y: CGFloat = 12

        let titleSize = videoTitleLabel.sizeThatFits(CGSize(width: contentW, height: 100))
        videoTitleLabel.frame = CGRect(x: pad, y: y, width: contentW, height: ceil(titleSize.height))
        y = videoTitleLabel.frame.maxY + 6

        videoMetaLabel.frame = CGRect(x: pad, y: y, width: contentW, height: 16)
        y = videoMetaLabel.frame.maxY + 4

        providerLabel.frame = CGRect(x: pad, y: y, width: contentW, height: max(15, ceil(providerLabel.sizeThatFits(CGSize(width: contentW, height: 160)).height)))
        y = providerLabel.frame.maxY + 6

        toggleDescButton.frame = CGRect(x: pad, y: y, width: 140, height: 24)
        y = toggleDescButton.frame.maxY + 4

        if isDescriptionExpanded, let desc = descriptionLabel.text, !desc.isEmpty {
            descriptionLabel.isHidden = false
            let dSize = descriptionLabel.sizeThatFits(CGSize(width: contentW - 16, height: 1200))
            descriptionLabel.frame = CGRect(x: pad, y: y, width: contentW, height: ceil(dSize.height) + 12)
            y = descriptionLabel.frame.maxY + 10
        } else {
            descriptionLabel.isHidden = true
        }

        // Action bar (4 equal buttons)
        actionBarStack.frame = CGRect(x: pad, y: y, width: contentW, height: 32)
        let gap: CGFloat = 6
        let btnW = floor((contentW - gap * 3) / 4.0)
        let buttons = [audioOnlyActionButton, watchLaterButton, qualityActionButton, copyLinkButton]
        for (idx, btn) in buttons.enumerated() {
            btn.frame = CGRect(x: CGFloat(idx) * (btnW + gap), y: 0, width: btnW, height: 32)
        }
        y = actionBarStack.frame.maxY + 12

        // Channel bar
        channelBarView.frame = CGRect(x: 0, y: y, width: w, height: 48)
        channelAvatarView.frame = CGRect(x: pad, y: 6, width: 36, height: 36)
        subscribeButton.sizeToFit()
        let subW = max(96, subscribeButton.bounds.width + 8)
        subscribeButton.frame = CGRect(x: w - pad - subW, y: 9, width: subW, height: 30)
        let nameX = pad + 36 + 10
        channelNameLabel.frame = CGRect(x: nameX, y: 12, width: max(40, subscribeButton.frame.minX - nameX - 8), height: 24)
        y = channelBarView.frame.maxY + 8

        segmentControl.frame = CGRect(x: pad, y: y, width: contentW, height: 30)
        y = segmentControl.frame.maxY + 10

        if abs(infoHeaderView.frame.height - y) > 0.5 || abs(infoHeaderView.frame.width - w) > 0.5 {
            infoHeaderView.frame = CGRect(x: 0, y: 0, width: w, height: y)
            tableView.tableHeaderView = infoHeaderView
        }
    }

    // MARK: - Refresh from PlayerManager

    func refreshAllUI() {
        handleStreamInfoUpdated()
        handlePlayerState()
        handlePlayerProgress()
        scheduleHideControls()
    }

    @objc private func handleStreamInfoUpdated() {
        let pm = PlayerManager.shared
        guard let video = pm.currentVideo else { return }

        if commentsLoadedForVideoId != video.id {
            comments = []
            commentsLoadedForVideoId = nil
        }

        videoTitleLabel.text = video.title
        videoMetaLabel.text = video.metadataLine
        if let info = pm.currentStreamInfo {
            let qLabel = pm.currentSelection?.qualityLabel ?? ""
            providerLabel.text = "Nguồn: \(info.providerName) • \(qLabel)"
            qualityBadgeButton.setTitle(qLabel.isEmpty ? LocalStore.shared.settings.maxQuality.shortLabel : qLabel, for: .normal)
            descriptionLabel.text = info.video.descriptionText ?? video.descriptionText ?? "(Không có mô tả)"
            relatedVideos = info.relatedVideos
        } else {
            providerLabel.text = "Đang phân giải luồng phát..."
            qualityBadgeButton.setTitle(LocalStore.shared.settings.maxQuality.shortLabel, for: .normal)
            descriptionLabel.text = video.descriptionText ?? ""
            relatedVideos = []
        }

        channelNameLabel.text = video.channelName.isEmpty ? "Kênh YouTube" : video.channelName
        ImageLoader.shared.cancel(channelAvatarToken)
        channelAvatarView.image = nil
        if let avatarURL = video.channelAvatarURL {
            let vid = video.id
            channelAvatarToken = ImageLoader.shared.loadImage(from: avatarURL, targetSize: CGSize(width: 36, height: 36), circular: true) { [weak self] img in
                guard let self = self, PlayerManager.shared.currentVideo?.id == vid else { return }
                self.channelAvatarView.image = img
            }
        }

        refreshAudioOnlyVisuals()
        refreshChannelSubscribeState()
        refreshWatchLaterState()
        layoutInfoHeader(forWidth: view.bounds.width)
        tableView.reloadData()

        if segmentControl.selectedSegmentIndex == 1 {
            loadCommentsIfNeeded()
        }
    }

    @objc private func handlePlayerState() {
        let pm = PlayerManager.shared
        switch pm.state {
        case .idle:
            spinner.stopAnimating()
            errorOverlayLabel.isHidden = true
            retryPlayerButton.isHidden = true
        case .loading:
            spinner.startAnimating()
            errorOverlayLabel.isHidden = true
            retryPlayerButton.isHidden = true
            centerPlayPauseButton.isHidden = true
        case .playing:
            spinner.stopAnimating()
            errorOverlayLabel.isHidden = true
            retryPlayerButton.isHidden = true
            centerPlayPauseButton.isHidden = false
            centerPlayPauseButton.setImage(VectorIcons.pause(size: 36), for: .normal)
        case .paused:
            spinner.stopAnimating()
            errorOverlayLabel.isHidden = true
            retryPlayerButton.isHidden = true
            centerPlayPauseButton.isHidden = false
            centerPlayPauseButton.setImage(VectorIcons.play(size: 36), for: .normal)
        case .failed(let msg):
            spinner.stopAnimating()
            centerPlayPauseButton.isHidden = true
            errorOverlayLabel.isHidden = false
            errorOverlayLabel.text = "Không phát được video\n\(msg)"
            providerLabel.text = "Lỗi chi tiết: \(msg)"
            layoutInfoHeader(forWidth: view.bounds.width)
            retryPlayerButton.isHidden = false
        }
        refreshAudioOnlyVisuals()
    }

    @objc private func handlePlayerProgress() {
        guard !isUserScrubbing else { return }
        let pm = PlayerManager.shared
        elapsedLabel.text = formatTime(pm.currentTime)
        durationLabel.text = formatTime(pm.duration)
        if pm.duration > 0 {
            seekSlider.value = Float(min(1.0, max(0.0, pm.currentTime / pm.duration)))
        } else {
            seekSlider.value = 0
        }
    }

    private func refreshAudioOnlyVisuals() {
        let p = ThemeManager.shared.palette
        let isAudio = PlayerManager.shared.isAudioOnly
        audioOnlyOverlayView.isHidden = !isAudio
        audioOnlyTopButton.tintColor = isAudio ? p.accent : .white
        audioOnlyActionButton.backgroundColor = isAudio ? p.accent : p.secondaryBackground
        audioOnlyActionButton.setTitleColor(isAudio ? .white : p.primaryText, for: .normal)
        audioOnlyActionButton.setTitle(isAudio ? "Đang Chỉ nghe" : "Chỉ nghe", for: .normal)
    }

    @objc private func refreshChannelSubscribeState() {
        let p = ThemeManager.shared.palette
        guard let chId = PlayerManager.shared.currentVideo?.channelId, !chId.isEmpty else {
            subscribeButton.isHidden = true
            return
        }
        subscribeButton.isHidden = false
        let sub = LocalStore.shared.isSubscribed(channelId: chId)
        subscribeButton.setTitle(sub ? "Đã đăng ký" : "Đăng ký", for: .normal)
        subscribeButton.backgroundColor = sub ? p.secondaryBackground : p.accent
        subscribeButton.setTitleColor(sub ? p.primaryText : .white, for: .normal)
    }

    @objc private func refreshWatchLaterState() {
        let p = ThemeManager.shared.palette
        guard let vid = PlayerManager.shared.currentVideo?.id else { return }
        let saved = LocalStore.shared.isInWatchLater(videoId: vid)
        watchLaterButton.setTitle(saved ? "Đã lưu" : "Xem sau", for: .normal)
        watchLaterButton.backgroundColor = saved ? p.accent : p.secondaryBackground
        watchLaterButton.setTitleColor(saved ? .white : p.primaryText, for: .normal)
    }

    private func loadCommentsIfNeeded() {
        guard let vid = PlayerManager.shared.currentVideo?.id else { return }
        if commentsLoadedForVideoId == vid || isLoadingComments { return }
        isLoadingComments = true
        ProviderManager.shared.fetchComments(videoId: vid) { [weak self] result in
            guard let self = self else { return }
            self.isLoadingComments = false
            guard PlayerManager.shared.currentVideo?.id == vid else { return }
            self.commentsLoadedForVideoId = vid
            switch result {
            case .success(let items):
                self.comments = items
            case .failure(let err):
                AppLogger.shared.warn("Comments load failed: \(err.localizedDescription)")
                self.comments = []
            }
            if self.segmentControl.selectedSegmentIndex == 1 {
                self.tableView.reloadData()
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleControlsOverlay() {
        isControlsVisible.toggle()
        controlsOverlay.isHidden = !isControlsVisible
        if isControlsVisible {
            scheduleHideControls()
        }
    }

    private func scheduleHideControls() {
        hideControlsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self = self, PlayerManager.shared.isPlaying else { return }
            self.isControlsVisible = false
            self.controlsOverlay.isHidden = true
        }
        hideControlsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0, execute: item)
    }

    @objc private func handleMinimizeTap() {
        if isFullscreen {
            isFullscreen = false
            return
        }
        onMinimizeRequested?()
    }

    @objc private func handleFullscreenTap() {
        isFullscreen.toggle()
        scheduleHideControls()
    }

    @objc private func handlePlayPauseTap() {
        PlayerManager.shared.togglePlayPause()
        scheduleHideControls()
    }

    @objc private func handleRewind15() {
        PlayerManager.shared.seek(to: PlayerManager.shared.currentTime - 15)
        scheduleHideControls()
    }

    @objc private func handleForward15() {
        PlayerManager.shared.seek(to: PlayerManager.shared.currentTime + 15)
        scheduleHideControls()
    }

    @objc private func handleRetryPlayer() {
        PlayerManager.shared.retryCurrentVideo()
    }

    @objc private func sliderTouchDown() {
        isUserScrubbing = true
        hideControlsWorkItem?.cancel()
    }

    @objc private func sliderValueChanged() {
        let target = Double(seekSlider.value) * PlayerManager.shared.duration
        elapsedLabel.text = formatTime(target)
    }

    @objc private func sliderTouchUp() {
        let target = Double(seekSlider.value) * PlayerManager.shared.duration
        isUserScrubbing = false
        PlayerManager.shared.seek(to: target)
        scheduleHideControls()
    }

    @objc private func handleAudioOnlyToggle() {
        PlayerManager.shared.setAudioOnly(!PlayerManager.shared.isAudioOnly)
        refreshAudioOnlyVisuals()
    }

    @objc private func handleQualityTap() {
        let alert = UIAlertController(title: "Chất lượng tối đa (H.264)", message: "iPhone 5s A7 khuyến nghị 480p", preferredStyle: .actionSheet)
        let current = LocalStore.shared.settings.maxQuality
        for q in MaxVideoQuality.allCases {
            let prefix = (q == current) ? "✓ " : ""
            alert.addAction(UIAlertAction(title: prefix + q.displayName, style: .default) { _ in
                LocalStore.shared.updateSettings { $0.maxQuality = q }
                PlayerManager.shared.applyQualityChange()
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        if let pop = alert.popoverPresentationController {
            pop.sourceView = qualityActionButton
            pop.sourceRect = qualityActionButton.bounds
        }
        present(alert, animated: true)
    }

    @objc private func handleWatchLaterTap() {
        guard let video = PlayerManager.shared.currentVideo else { return }
        _ = LocalStore.shared.toggleWatchLater(video: video)
        refreshWatchLaterState()
    }

    @objc private func handleCopyLinkTap() {
        guard let vid = PlayerManager.shared.currentVideo?.id else { return }
        UIPasteboard.general.string = "https://www.youtube.com/watch?v=\(vid)"
        let alert = UIAlertController(title: nil, message: "Đã sao chép link video", preferredStyle: .alert)
        present(alert, animated: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            alert.dismiss(animated: true)
        }
    }

    @objc private func handleToggleDescription() {
        isDescriptionExpanded.toggle()
        toggleDescButton.setTitle(isDescriptionExpanded ? "Ẩn mô tả" : "Xem mô tả", for: .normal)
        layoutInfoHeader(forWidth: view.bounds.width)
    }

    @objc private func handleChannelTap() {
        guard let video = PlayerManager.shared.currentVideo, !video.channelId.isEmpty else { return }
        onMinimizeRequested?()
        onOpenChannel?(video.channelId, video.channelName)
    }

    @objc private func handleSubscribeTap() {
        guard let video = PlayerManager.shared.currentVideo, !video.channelId.isEmpty else { return }
        _ = LocalStore.shared.toggleSubscription(
            channelId: video.channelId,
            name: video.channelName,
            avatarURL: video.channelAvatarURL
        )
        refreshChannelSubscribeState()
    }

    @objc private func handleSegmentChanged() {
        if segmentControl.selectedSegmentIndex == 1 {
            loadCommentsIfNeeded()
        }
        tableView.reloadData()
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

extension WatchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if segmentControl.selectedSegmentIndex == 0 {
            return relatedVideos.count
        }
        return comments.isEmpty ? 1 : comments.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if segmentControl.selectedSegmentIndex == 0 {
            return VideoCardCell.height(forWidth: tableView.bounds.width)
        }
        if comments.isEmpty {
            return 60
        }
        return CommentCell.height(for: comments[indexPath.row], width: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if segmentControl.selectedSegmentIndex == 0 {
            let cell = tableView.dequeueReusableCell(withIdentifier: VideoCardCell.reuseIdentifier, for: indexPath) as! VideoCardCell
            cell.configure(with: relatedVideos[indexPath.row])
            return cell
        }

        if comments.isEmpty {
            let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
            let p = ThemeManager.shared.palette
            cell.backgroundColor = p.background
            cell.textLabel?.textColor = p.secondaryText
            cell.textLabel?.font = UIFont.systemFont(ofSize: 13)
            cell.textLabel?.textAlignment = .center
            cell.selectionStyle = .none
            cell.textLabel?.text = isLoadingComments ? "Đang tải bình luận..." : "Không có bình luận."
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: CommentCell.reuseIdentifier, for: indexPath) as! CommentCell
        cell.configure(with: comments[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard segmentControl.selectedSegmentIndex == 0 else { return }
        let video = relatedVideos[indexPath.row]
        PlayerManager.shared.load(video: video)
        tableView.setContentOffset(.zero, animated: true)
    }
}

extension WatchViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.view is UIControl {
            return false
        }
        return true
    }
}
