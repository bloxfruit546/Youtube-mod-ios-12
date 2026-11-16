import UIKit

final class HomeViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let refreshControl = UIRefreshControl()
    private let stateView = StateView()

    private var videos: [VideoItem] = []
    private var isLoading = false

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupTableView()
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionsOrSettingsChange), name: .subscriptionsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleSubscriptionsOrSettingsChange), name: .settingsDidChange, object: nil)

        loadFeed()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNavigationBar() {
        let titleLbl = UILabel()
        titleLbl.text = "LiteTube5s"
        titleLbl.font = UIFont.boldSystemFont(ofSize: 18)
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: titleLbl)

        let searchItem = UIBarButtonItem(
            image: VectorIcons.search(size: 20),
            style: .plain,
            target: self,
            action: #selector(handleSearchTap)
        )
        let themeItem = UIBarButtonItem(
            image: VectorIcons.themeToggle(size: 20),
            style: .plain,
            target: self,
            action: #selector(handleThemeToggle)
        )
        navigationItem.rightBarButtonItems = [searchItem, themeItem]
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(VideoCardCell.self, forCellReuseIdentifier: VideoCardCell.reuseIdentifier)
        refreshControl.addTarget(self, action: #selector(handleRefresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)

        stateView.onRetry = { [weak self] in
            self?.loadFeed()
        }
        view.addSubview(stateView)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
        stateView.frame = view.bounds
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    @objc private func handleSubscriptionsOrSettingsChange() {
        loadFeed()
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background
        refreshControl.tintColor = p.primaryText
        stateView.applyTheme()
        if let lbl = navigationItem.leftBarButtonItem?.customView as? UILabel {
            lbl.textColor = p.primaryText
        }
    }

    @objc private func handleSearchTap() {
        RootContainerViewController.shared?.openSearch()
    }

    @objc private func handleThemeToggle() {
        ThemeManager.shared.toggle()
    }

    @objc private func handleRefresh() {
        loadFeed()
    }

    private func loadFeed() {
        guard !isLoading else { return }
        isLoading = true

        if videos.isEmpty {
            stateView.showLoading("Đang tải video...")
        }

        let subs = LocalStore.shared.getSubscriptions()
        if subs.isEmpty {
            let region = LocalStore.shared.settings.regionCode
            ProviderManager.shared.fetchTrending(region: region) { [weak self] result in
                guard let self = self else { return }
                self.isLoading = false
                self.refreshControl.endRefreshing()
                switch result {
                case .success(let items):
                    self.videos = items
                    if items.isEmpty {
                        self.stateView.showEmpty(title: "Không có video", message: "Danh sách Thịnh hành trống.")
                    } else {
                        self.stateView.hide()
                    }
                    self.tableView.reloadData()
                case .failure(let error):
                    if self.videos.isEmpty {
                        self.stateView.showError(message: error.localizedDescription)
                    }
                }
            }
            return
        }

        // Load latest videos from up to 6 subscribed channels in small batches to stay gentle on A7 RAM
        let targetSubs = Array(subs.prefix(6))
        let group = DispatchGroup()
        let lock = NSLock()
        var merged: [VideoItem] = []

        for sub in targetSubs {
            group.enter()
            ProviderManager.shared.fetchChannel(channelId: sub.id) { result in
                if case .success(let ch) = result {
                    lock.lock()
                    merged.append(contentsOf: ch.videos.prefix(6))
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoading = false
            self.refreshControl.endRefreshing()

            // Deduplicate preserving interleaved order
            var seen = Set<String>()
            let unique = merged.filter { seen.insert($0.id).inserted }
            if !unique.isEmpty {
                self.videos = unique
                self.stateView.hide()
                self.tableView.reloadData()
            } else {
                // Fallback to Trending if subscriptions failed
                let region = LocalStore.shared.settings.regionCode
                ProviderManager.shared.fetchTrending(region: region) { result in
                    switch result {
                    case .success(let items):
                        self.videos = items
                        if items.isEmpty {
                            self.stateView.showEmpty(title: "Không có video", message: "Kéo xuống để thử lại.")
                        } else {
                            self.stateView.hide()
                        }
                        self.tableView.reloadData()
                    case .failure(let err):
                        if self.videos.isEmpty {
                            self.stateView.showError(message: err.localizedDescription)
                        }
                    }
                }
            }
        }
    }
}

extension HomeViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return videos.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return VideoCardCell.height(forWidth: tableView.bounds.width)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: VideoCardCell.reuseIdentifier, for: indexPath) as! VideoCardCell
        cell.configure(with: videos[indexPath.row])
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        RootContainerViewController.shared?.openVideo(videos[indexPath.row])
    }
}
