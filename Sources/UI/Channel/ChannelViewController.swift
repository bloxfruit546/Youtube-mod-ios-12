import UIKit

final class ChannelViewController: UIViewController {
    private let channelId: String
    private var channelName: String

    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()

    private let headerView = UIView()
    private let avatarView = UIImageView()
    private let nameLabel = UILabel()
    private let subsLabel = UILabel()
    private let subscribeButton = UIButton(type: .system)
    private let headerBorder = UIView()

    private var channel: ChannelItem?
    private var avatarToken: UUID?

    init(channelId: String, channelName: String) {
        self.channelId = channelId
        self.channelName = channelName
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        ImageLoader.shared.cancel(avatarToken)
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = channelName
        setupHeader()
        setupTableView()
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(updateSubscribeButton), name: .subscriptionsDidChange, object: nil)

        loadChannel()
    }

    private func setupHeader() {
        headerView.isOpaque = true

        avatarView.contentMode = .scaleAspectFit
        avatarView.isOpaque = false
        headerView.addSubview(avatarView)

        nameLabel.font = UIFont.boldSystemFont(ofSize: 16)
        nameLabel.text = channelName
        nameLabel.isOpaque = true
        headerView.addSubview(nameLabel)

        subsLabel.font = UIFont.systemFont(ofSize: 12.5)
        subsLabel.isOpaque = true
        headerView.addSubview(subsLabel)

        subscribeButton.titleLabel?.font = UIFont.boldSystemFont(ofSize: 13)
        subscribeButton.addTarget(self, action: #selector(handleSubscribeTap), for: .touchUpInside)
        headerView.addSubview(subscribeButton)

        headerBorder.isOpaque = true
        headerView.addSubview(headerBorder)
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(VideoCardCell.self, forCellReuseIdentifier: VideoCardCell.reuseIdentifier)
        view.addSubview(tableView)

        stateView.onRetry = { [weak self] in
            self?.loadChannel()
        }
        view.addSubview(stateView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let w = view.bounds.width
        tableView.frame = view.bounds
        stateView.frame = view.bounds

        headerView.frame = CGRect(x: 0, y: 0, width: w, height: 76)
        avatarView.frame = CGRect(x: 12, y: 14, width: 48, height: 48)
        subscribeButton.frame = CGRect(x: w - 110 - 12, y: 22, width: 110, height: 32)
        let textX: CGFloat = 72
        let textW = max(60, subscribeButton.frame.minX - textX - 8)
        nameLabel.frame = CGRect(x: textX, y: 16, width: textW, height: 22)
        subsLabel.frame = CGRect(x: textX, y: 40, width: textW, height: 18)
        headerBorder.frame = CGRect(x: 0, y: 75.5, width: w, height: 0.5)
        tableView.tableHeaderView = headerView
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background
        headerView.backgroundColor = p.background
        nameLabel.backgroundColor = p.background
        nameLabel.textColor = p.primaryText
        subsLabel.backgroundColor = p.background
        subsLabel.textColor = p.secondaryText
        headerBorder.backgroundColor = p.separator
        stateView.applyTheme()
        updateSubscribeButton()
    }

    @objc private func updateSubscribeButton() {
        let p = ThemeManager.shared.palette
        let sub = LocalStore.shared.isSubscribed(channelId: channelId)
        subscribeButton.setTitle(sub ? "Đã đăng ký" : "Đăng ký", for: .normal)
        subscribeButton.backgroundColor = sub ? p.secondaryBackground : p.accent
        subscribeButton.setTitleColor(sub ? p.primaryText : .white, for: .normal)
    }

    @objc private func handleSubscribeTap() {
        _ = LocalStore.shared.toggleSubscription(
            channelId: channelId,
            name: channel?.name ?? channelName,
            avatarURL: channel?.avatarURL
        )
        updateSubscribeButton()
    }

    private func loadChannel() {
        stateView.showLoading("Đang tải kênh...")
        ProviderManager.shared.fetchChannel(channelId: channelId) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let ch):
                self.channel = ch
                self.channelName = ch.name
                self.title = ch.name
                self.nameLabel.text = ch.name
                self.subsLabel.text = ch.subscriberCountText
                self.stateView.hide()
                self.tableView.reloadData()

                if let avatarURL = ch.avatarURL {
                    self.avatarToken = ImageLoader.shared.loadImage(from: avatarURL, targetSize: CGSize(width: 48, height: 48), circular: true) { [weak self] img in
                        self?.avatarView.image = img
                    }
                }
            case .failure(let err):
                self.stateView.showError(message: err.localizedDescription)
            }
        }
    }
}

extension ChannelViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return channel?.videos.count ?? 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return VideoCardCell.height(forWidth: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCardCell.reuseIdentifier, for: indexPath) as! VideoCardCell
        if let video = channel?.videos[indexPath.row] {
            cell.configure(with: video)
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if let video = channel?.videos[indexPath.row] {
            RootContainerViewController.shared?.openVideo(video)
        }
    }
}
