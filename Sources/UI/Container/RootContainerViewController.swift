import UIKit

enum PlayerPresentationState {
    case hidden
    case expanded
    case mini
}

final class RootContainerViewController: UIViewController {
    static weak var shared: RootContainerViewController?

    let mainTabBarController = UITabBarController()
    private let watchVC = WatchViewController()
    private let miniPlayerView = MiniPlayerView()

    private(set) var presentationState: PlayerPresentationState = .hidden
    private let miniHeight: CGFloat = 58.0

    override var preferredStatusBarStyle: UIStatusBarStyle {
        return ThemeManager.shared.palette.statusBarStyle
    }

    override var shouldAutorotate: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if presentationState == .expanded && watchVC.isFullscreen {
            return [.landscapeLeft, .landscapeRight, .portrait]
        }
        return .portrait
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        RootContainerViewController.shared = self

        setupTabs()
        setupWatchAndMiniPlayer()
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupTabs() {
        let homeVC = HomeViewController()
        let homeNav = UINavigationController(rootViewController: homeVC)
        homeNav.tabBarItem = UITabBarItem(title: "Trang chủ", image: VectorIcons.home(), tag: 0)

        let subsVC = SubscriptionsViewController()
        let subsNav = UINavigationController(rootViewController: subsVC)
        subsNav.tabBarItem = UITabBarItem(title: "Đăng ký", image: VectorIcons.subscriptions(), tag: 1)

        let libVC = LibraryViewController()
        let libNav = UINavigationController(rootViewController: libVC)
        libNav.tabBarItem = UITabBarItem(title: "Thư viện", image: VectorIcons.library(), tag: 2)

        mainTabBarController.viewControllers = [homeNav, subsNav, libNav]
        addChild(mainTabBarController)
        mainTabBarController.view.frame = view.bounds
        view.addSubview(mainTabBarController.view)
        mainTabBarController.didMove(toParent: self)
    }

    private func setupWatchAndMiniPlayer() {
        addChild(watchVC)
        watchVC.view.frame = CGRect(x: 0, y: view.bounds.height, width: view.bounds.width, height: view.bounds.height)
        watchVC.view.isHidden = true
        view.addSubview(watchVC.view)
        watchVC.didMove(toParent: self)

        watchVC.onMinimizeRequested = { [weak self] in
            self?.setPresentationState(.mini, animated: true)
        }
        watchVC.onFullscreenChanged = { [weak self] isFull in
            self?.mainTabBarController.tabBar.isHidden = isFull
            self?.setNeedsStatusBarAppearanceUpdate()
        }
        watchVC.onOpenChannel = { [weak self] channelId, name in
            self?.openChannel(channelId: channelId, name: name)
        }

        let panDown = UIPanGestureRecognizer(target: self, action: #selector(handleWatchPan(_:)))
        watchVC.playerContainerView.addGestureRecognizer(panDown)

        miniPlayerView.isHidden = true
        miniPlayerView.onExpandTap = { [weak self] in
            self?.setPresentationState(.expanded, animated: true)
        }
        miniPlayerView.onPlayPauseTap = {
            PlayerManager.shared.togglePlayPause()
        }
        miniPlayerView.onCloseTap = { [weak self] in
            PlayerManager.shared.stopAndClear()
            self?.setPresentationState(.hidden, animated: true)
        }
        let panUp = UIPanGestureRecognizer(target: self, action: #selector(handleMiniPan(_:)))
        miniPlayerView.addGestureRecognizer(panUp)
        view.addSubview(miniPlayerView)
    }

    @objc private func handleThemeChange() {
        applyTheme()
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background

        mainTabBarController.tabBar.barTintColor = p.elevatedBackground
        mainTabBarController.tabBar.tintColor = p.accent
        mainTabBarController.tabBar.unselectedItemTintColor = p.secondaryText
        mainTabBarController.tabBar.isTranslucent = false

        if let navs = mainTabBarController.viewControllers as? [UINavigationController] {
            for nav in navs {
                nav.navigationBar.barTintColor = p.background
                nav.navigationBar.tintColor = p.primaryText
                nav.navigationBar.barStyle = p.barStyle
                nav.navigationBar.isTranslucent = false
                nav.navigationBar.titleTextAttributes = [.foregroundColor: p.primaryText]
            }
        }

        setNeedsStatusBarAppearanceUpdate()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mainTabBarController.view.frame = view.bounds
        layoutPlayerContainers(animated: false)
    }

    private var miniPlayerFrame: CGRect {
        let tabTop = mainTabBarController.tabBar.frame.minY
        let y = (tabTop > 0 ? tabTop : view.bounds.height - 49) - miniHeight
        return CGRect(x: 0, y: y, width: view.bounds.width, height: miniHeight)
    }

    private func layoutPlayerContainers(animated: Bool) {
        let apply = {
            switch self.presentationState {
            case .hidden:
                self.watchVC.view.frame = CGRect(x: 0, y: self.view.bounds.height, width: self.view.bounds.width, height: self.view.bounds.height)
                self.watchVC.view.isHidden = true
                self.miniPlayerView.isHidden = true
                self.mainTabBarController.tabBar.isHidden = false
                self.updateTabBottomInsets(0)
            case .expanded:
                self.watchVC.view.isHidden = false
                self.watchVC.view.alpha = 1.0
                self.watchVC.view.frame = self.view.bounds
                self.miniPlayerView.isHidden = true
                self.mainTabBarController.tabBar.isHidden = self.watchVC.isFullscreen
                self.updateTabBottomInsets(0)
            case .mini:
                self.watchVC.view.isHidden = true
                self.miniPlayerView.isHidden = false
                self.miniPlayerView.frame = self.miniPlayerFrame
                self.miniPlayerView.refreshFromPlayer()
                self.mainTabBarController.tabBar.isHidden = false
                self.updateTabBottomInsets(self.miniHeight)
            }
        }

        if animated {
            UIView.animate(withDuration: 0.24, delay: 0, options: [.curveEaseOut], animations: apply)
        } else {
            apply()
        }
    }

    private func updateTabBottomInsets(_ extraBottom: CGFloat) {
        guard let navs = mainTabBarController.viewControllers as? [UINavigationController] else { return }
        for nav in navs {
            nav.additionalSafeAreaInsets.bottom = extraBottom
        }
    }

    func setPresentationState(_ newState: PlayerPresentationState, animated: Bool) {
        if newState != .expanded && watchVC.isFullscreen {
            watchVC.isFullscreen = false
        }
        presentationState = newState
        if newState == .expanded {
            watchVC.view.isHidden = false
        }
        layoutPlayerContainers(animated: animated)
        setNeedsStatusBarAppearanceUpdate()
    }

    // MARK: - Pan Gestures

    @objc private func handleWatchPan(_ gesture: UIPanGestureRecognizer) {
        guard presentationState == .expanded, !watchVC.isFullscreen else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let h = view.bounds.height

        switch gesture.state {
        case .changed:
            let y = max(0, translation.y)
            watchVC.view.frame.origin.y = y
            let progress = min(1.0, y / (h * 0.5))
            watchVC.view.alpha = max(0.35, 1.0 - progress * 0.65)
        case .ended, .cancelled:
            if translation.y > h * 0.22 || velocity.y > 650 {
                setPresentationState(.mini, animated: true)
            } else {
                setPresentationState(.expanded, animated: true)
            }
        default:
            break
        }
    }

    @objc private func handleMiniPan(_ gesture: UIPanGestureRecognizer) {
        guard presentationState == .mini else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)

        if gesture.state == .ended {
            if translation.y < -40 || velocity.y < -400 {
                setPresentationState(.expanded, animated: true)
            } else if translation.y > 40 || velocity.y > 400 {
                PlayerManager.shared.stopAndClear()
                setPresentationState(.hidden, animated: true)
            }
        }
    }

    // MARK: - Public Navigation API

    func openVideo(_ video: VideoItem, startAt: Double? = nil) {
        let resume = startAt ?? LocalStore.shared.savedPosition(for: video.id)
        let effectiveResume = (resume > 5 && video.durationSeconds > 0 && resume < Double(video.durationSeconds - 10)) ? resume : nil

        PlayerManager.shared.load(video: video, startAt: effectiveResume)
        watchVC.refreshAllUI()
        setPresentationState(.expanded, animated: true)
    }

    func openChannel(channelId: String, name: String) {
        guard !channelId.isEmpty else { return }
        guard let nav = mainTabBarController.selectedViewController as? UINavigationController else { return }
        let vc = ChannelViewController(channelId: channelId, channelName: name)
        nav.pushViewController(vc, animated: true)
    }

    func openSearch() {
        guard let nav = mainTabBarController.selectedViewController as? UINavigationController else { return }
        let vc = SearchViewController()
        nav.pushViewController(vc, animated: true)
    }
}
