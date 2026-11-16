import UIKit

/// Ultra-lightweight UITableViewCell for Apple A7 (iPhone 5s).
/// RULES ENFORCED:
/// - ZERO NSLayoutConstraint (100% manual frame math in `layoutSubviews()`)
/// - ZERO Offscreen Rendering (isOpaque = true, solid backgrounds, no shadows, no cornerRadius+masksToBounds)
/// - Background-decoded images + immediate cancellation on `prepareForReuse()`
final class VideoCardCell: UITableViewCell {
    static let reuseIdentifier = "VideoCardCell"

    private let thumbnailView = UIImageView()
    private let durationLabel = UILabel()
    private let avatarView = UIImageView()
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let separatorLine = UIView()

    private var thumbToken: UUID?
    private var avatarToken: UUID?
    private var currentVideoId: String?

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        selectionStyle = .none
        isOpaque = true
        contentView.isOpaque = true

        thumbnailView.contentMode = .scaleAspectFill
        thumbnailView.clipsToBounds = true
        thumbnailView.isOpaque = true
        contentView.addSubview(thumbnailView)

        durationLabel.font = UIFont.boldSystemFont(ofSize: 11)
        durationLabel.textAlignment = .center
        durationLabel.isOpaque = true
        contentView.addSubview(durationLabel)

        avatarView.contentMode = .scaleAspectFit
        avatarView.isOpaque = false // Circular CoreGraphics clipped image
        contentView.addSubview(avatarView)

        titleLabel.font = UIFont.systemFont(ofSize: 14.5, weight: .semibold)
        titleLabel.numberOfLines = 2
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.isOpaque = true
        contentView.addSubview(titleLabel)

        subtitleLabel.font = UIFont.systemFont(ofSize: 12)
        subtitleLabel.numberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.isOpaque = true
        contentView.addSubview(subtitleLabel)

        separatorLine.isOpaque = true
        contentView.addSubview(separatorLine)
    }

    func applyTheme() {
        let p = ThemeManager.shared.palette
        backgroundColor = p.background
        contentView.backgroundColor = p.background
        thumbnailView.backgroundColor = p.secondaryBackground
        durationLabel.backgroundColor = p.badgeBackground
        durationLabel.textColor = p.badgeText
        titleLabel.backgroundColor = p.background
        titleLabel.textColor = p.primaryText
        subtitleLabel.backgroundColor = p.background
        subtitleLabel.textColor = p.secondaryText
        separatorLine.backgroundColor = p.separator
    }

    static func height(forWidth width: CGFloat) -> CGFloat {
        let thumbHeight = floor(width * 9.0 / 16.0)
        // 10pt top padding below thumb + 38pt title + 4pt gap + 18pt subtitle + 12pt bottom padding
        return thumbHeight + 82.0
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let h = contentView.bounds.height

        let thumbH = floor(w * 9.0 / 16.0)
        thumbnailView.frame = CGRect(x: 0, y: 0, width: w, height: thumbH)

        if let durText = durationLabel.text, !durText.isEmpty {
            let durSize = durationLabel.sizeThatFits(CGSize(width: 120, height: 20))
            let badgeW = durSize.width + 10
            let badgeH: CGFloat = 18
            durationLabel.frame = CGRect(
                x: w - badgeW - 8,
                y: thumbH - badgeH - 8,
                width: badgeW,
                height: badgeH
            )
            durationLabel.isHidden = false
        } else {
            durationLabel.isHidden = true
        }

        let topY = thumbH + 10
        let leftPad: CGFloat = 12
        let rightPad: CGFloat = 12
        let avatarSize: CGFloat = 36

        let hasAvatar = (avatarView.image != nil)
        let textX: CGFloat
        if hasAvatar {
            avatarView.isHidden = false
            avatarView.frame = CGRect(x: leftPad, y: topY, width: avatarSize, height: avatarSize)
            textX = leftPad + avatarSize + 10
        } else {
            avatarView.isHidden = true
            textX = leftPad
        }

        let textW = max(60, w - textX - rightPad)
        let titleFit = titleLabel.sizeThatFits(CGSize(width: textW, height: 40))
        let titleH = min(38, ceil(titleFit.height))
        titleLabel.frame = CGRect(x: textX, y: topY, width: textW, height: titleH)

        let subY = topY + titleH + 4
        let subFit = subtitleLabel.sizeThatFits(CGSize(width: textW, height: 34))
        let subH = min(32, ceil(subFit.height))
        subtitleLabel.frame = CGRect(x: textX, y: subY, width: textW, height: subH)

        separatorLine.frame = CGRect(x: 0, y: h - 0.5, width: w, height: 0.5)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        ImageLoader.shared.cancel(thumbToken)
        ImageLoader.shared.cancel(avatarToken)
        thumbToken = nil
        avatarToken = nil
        currentVideoId = nil
        thumbnailView.image = nil
        avatarView.image = nil
        titleLabel.text = nil
        subtitleLabel.text = nil
        durationLabel.text = nil
    }

    func configure(with video: VideoItem) {
        applyTheme()
        currentVideoId = video.id
        titleLabel.text = video.title
        subtitleLabel.text = video.metadataLine
        durationLabel.text = video.formattedDuration

        ImageLoader.shared.cancel(thumbToken)
        ImageLoader.shared.cancel(avatarToken)

        let expectedId = video.id
        let thumbTarget = CGSize(width: 320, height: 180)
        thumbToken = ImageLoader.shared.loadImage(from: video.thumbnailURL, targetSize: thumbTarget, circular: false) { [weak self] image in
            guard let self = self, self.currentVideoId == expectedId else { return }
            self.thumbnailView.image = image
        }

        if let avatarURL = video.channelAvatarURL {
            avatarToken = ImageLoader.shared.loadImage(from: avatarURL, targetSize: CGSize(width: 36, height: 36), circular: true) { [weak self] image in
                guard let self = self, self.currentVideoId == expectedId else { return }
                self.avatarView.image = image
                self.setNeedsLayout()
            }
        } else {
            avatarView.image = nil
        }

        setNeedsLayout()
    }
}
