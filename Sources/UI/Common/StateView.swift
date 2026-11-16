import UIKit

final class StateView: UIView {
    private let indicator = UIActivityIndicatorView(style: .gray)
    private let titleLabel = UILabel()
    private let messageLabel = UILabel()
    private let actionButton = UIButton(type: .system)

    var onRetry: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true

        indicator.hidesWhenStopped = true
        addSubview(indicator)

        titleLabel.font = UIFont.boldSystemFont(ofSize: 16)
        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        titleLabel.isOpaque = true
        addSubview(titleLabel)

        messageLabel.font = UIFont.systemFont(ofSize: 13)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 4
        messageLabel.isOpaque = true
        addSubview(messageLabel)

        actionButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 14)
        actionButton.setTitle("Thử lại", for: .normal)
        actionButton.addTarget(self, action: #selector(handleRetry), for: .touchUpInside)
        addSubview(actionButton)

        applyTheme()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        let h = bounds.height
        let pad: CGFloat = 24
        let contentW = max(100, w - pad * 2)

        indicator.center = CGPoint(x: w * 0.5, y: h * 0.42)

        let titleSize = titleLabel.sizeThatFits(CGSize(width: contentW, height: 80))
        let msgSize = messageLabel.sizeThatFits(CGSize(width: contentW, height: 120))

        var y = indicator.isAnimating ? indicator.frame.maxY + 14 : (h * 0.36)
        titleLabel.frame = CGRect(x: pad, y: y, width: contentW, height: titleSize.height)
        y = titleLabel.frame.maxY + 8
        messageLabel.frame = CGRect(x: pad, y: y, width: contentW, height: msgSize.height)
        y = messageLabel.frame.maxY + 14
        actionButton.frame = CGRect(x: (w - 130) * 0.5, y: y, width: 130, height: 36)
    }

    func applyTheme() {
        let p = ThemeManager.shared.palette
        backgroundColor = p.background
        titleLabel.backgroundColor = p.background
        titleLabel.textColor = p.primaryText
        messageLabel.backgroundColor = p.background
        messageLabel.textColor = p.secondaryText
        indicator.color = p.primaryText
        actionButton.backgroundColor = p.secondaryBackground
        actionButton.setTitleColor(p.primaryText, for: .normal)
    }

    func showLoading(_ text: String = "Đang tải...") {
        isHidden = false
        indicator.startAnimating()
        titleLabel.text = text
        messageLabel.text = ""
        actionButton.isHidden = true
        setNeedsLayout()
    }

    func showError(title: String = "Không tải được dữ liệu", message: String) {
        isHidden = false
        indicator.stopAnimating()
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = (onRetry == nil)
        setNeedsLayout()
    }

    func showEmpty(title: String, message: String) {
        isHidden = false
        indicator.stopAnimating()
        titleLabel.text = title
        messageLabel.text = message
        actionButton.isHidden = (onRetry == nil)
        setNeedsLayout()
    }

    func hide() {
        indicator.stopAnimating()
        isHidden = true
    }

    @objc private func handleRetry() {
        onRetry?()
    }
}
