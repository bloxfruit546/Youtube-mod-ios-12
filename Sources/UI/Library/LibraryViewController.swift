import UIKit

final class LibraryViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .grouped)

    private var playlists: [PlaylistItem] = []
    private var historyCount: Int = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Thư viện"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: VectorIcons.settings(size: 20),
            style: .plain,
            target: self,
            action: #selector(openSettingsAndDebug)
        )

        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .playlistsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)

        reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.secondaryBackground
        tableView.separatorColor = p.separator
    }

    @objc private func reloadData() {
        playlists = LocalStore.shared.getPlaylists()
        historyCount = LocalStore.shared.getHistory().count
        tableView.reloadData()
    }

    @objc private func openSettingsAndDebug() {
        let vc = SettingsAndDebugViewController()
        navigationController?.pushViewController(vc, animated: true)
    }

    private func promptNewPlaylist() {
        let alert = UIAlertController(title: "Tạo danh sách phát", message: nil, preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Tên danh sách phát..."
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Tạo", style: .default) { _ in
            let title = alert.textFields?.first?.text ?? ""
            LocalStore.shared.createPlaylist(title: title)
        })
        present(alert, animated: true)
    }
}

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Hoạt động"
        case 1: return "Danh sách phát cục bộ"
        case 2: return "Hệ thống & Chẩn đoán"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 1
        case 1: return playlists.count + 1
        case 2: return 2
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LibCell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "LibCell")
        let p = ThemeManager.shared.palette
        cell.backgroundColor = p.background
        cell.textLabel?.textColor = p.primaryText
        cell.detailTextLabel?.textColor = p.secondaryText
        cell.accessoryType = .disclosureIndicator

        switch indexPath.section {
        case 0:
            cell.textLabel?.text = "Lịch sử xem"
            cell.detailTextLabel?.text = "\(historyCount) video"
        case 1:
            if indexPath.row < playlists.count {
                let pl = playlists[indexPath.row]
                cell.textLabel?.text = pl.title
                cell.detailTextLabel?.text = "\(pl.videos.count) video"
            } else {
                cell.textLabel?.text = "+ Tạo danh sách phát mới"
                cell.textLabel?.textColor = p.accent
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .none
            }
        case 2:
            if indexPath.row == 0 {
                cell.textLabel?.text = "Cài đặt & Debug (RAM / SSL / Logs)"
                cell.detailTextLabel?.text = String(format: "%.0f MB", MemoryMonitor.currentFootprintMB())
            } else {
                cell.textLabel?.text = "Xóa bộ nhớ đệm ảnh & mạng"
                cell.detailTextLabel?.text = nil
                cell.accessoryType = .none
            }
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch indexPath.section {
        case 0:
            let vc = LocalVideoListViewController(mode: .history)
            navigationController?.pushViewController(vc, animated: true)
        case 1:
            if indexPath.row < playlists.count {
                let pl = playlists[indexPath.row]
                let vc = LocalVideoListViewController(mode: .playlist(pl.id, pl.title))
                navigationController?.pushViewController(vc, animated: true)
            } else {
                promptNewPlaylist()
            }
        case 2:
            if indexPath.row == 0 {
                openSettingsAndDebug()
            } else {
                ImageLoader.shared.clearMemoryCache()
                URLCache.shared.removeAllCachedResponses()
                let alert = UIAlertController(title: "Đã dọn RAM", message: "Đã xóa toàn bộ bộ nhớ đệm ảnh và HTTP cache.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
                tableView.reloadData()
            }
        default:
            break
        }
    }
}

final class LocalVideoListViewController: UIViewController {
    enum Mode {
        case history
        case playlist(String, String)
    }

    private let mode: Mode
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()
    private var videos: [VideoItem] = []

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        switch mode {
        case .history:
            title = "Lịch sử xem"
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Xóa hết", style: .plain, target: self, action: #selector(clearAllHistory))
        case .playlist(_, let name):
            title = name
        }

        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .none
        tableView.register(VideoCardCell.self, forCellReuseIdentifier: VideoCardCell.reuseIdentifier)
        view.addSubview(tableView)
        view.addSubview(stateView)

        applyTheme()
        reloadData()

        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .playlistsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
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

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background
        stateView.applyTheme()
    }

    @objc private func reloadData() {
        switch mode {
        case .history:
            videos = LocalStore.shared.getHistory().map { $0.video }
        case .playlist(let id, _):
            videos = LocalStore.shared.getPlaylists().first(where: { $0.id == id })?.videos ?? []
        }
        if videos.isEmpty {
            stateView.showEmpty(title: "Danh sách trống", message: "Chưa có video nào ở đây.")
        } else {
            stateView.hide()
        }
        tableView.reloadData()
    }

    @objc private func clearAllHistory() {
        LocalStore.shared.clearHistory()
    }
}

extension LocalVideoListViewController: UITableViewDataSource, UITableViewDelegate {
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

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, case .playlist(let plId, _) = mode {
            LocalStore.shared.removeVideo(videoId: videos[indexPath.row].id, fromPlaylistId: plId)
        }
    }
}
