import UIKit

final class SubscriptionsViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()

    private var channels: [SubscribedChannel] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Kênh đăng ký"
        setupNavigationBar()
        setupTableView()
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(reloadData), name: .subscriptionsDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)

        reloadData()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupNavigationBar() {
        let importBtn = UIBarButtonItem(title: "Nhập Takeout", style: .plain, target: self, action: #selector(handleImportTap))
        let searchBtn = UIBarButtonItem(image: VectorIcons.search(size: 20), style: .plain, target: self, action: #selector(handleSearchTap))
        navigationItem.rightBarButtonItems = [searchBtn, importBtn]
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .singleLine
        view.addSubview(tableView)
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

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background
        tableView.separatorColor = p.separator
        stateView.applyTheme()
    }

    @objc private func reloadData() {
        channels = LocalStore.shared.getSubscriptions()
        if channels.isEmpty {
            stateView.showEmpty(
                title: "Chưa có kênh đăng ký",
                message: "Nhấn \"Đăng ký\" khi xem video hoặc bấm \"Nhập Takeout\" để nhập file JSON/CSV từ Google Takeout."
            )
        } else {
            stateView.hide()
        }
        tableView.reloadData()
    }

    @objc private func handleSearchTap() {
        RootContainerViewController.shared?.openSearch()
    }

    @objc private func handleImportTap() {
        let types = ["public.json", "public.comma-separated-values-text", "public.text", "public.plain-text"]
        let picker = UIDocumentPickerViewController(documentTypes: types, in: .import)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
}

extension SubscriptionsViewController: UIDocumentPickerDelegate {
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let result = LocalStore.shared.importSubscriptions(from: url)
        let alertTitle: String
        let alertMsg: String
        switch result {
        case .success(let count):
            alertTitle = "Nhập thành công"
            alertMsg = "Đã thêm \(count) kênh đăng ký mới."
        case .failure(let err):
            alertTitle = "Lỗi nhập file"
            alertMsg = err.localizedDescription
        }
        let alert = UIAlertController(title: alertTitle, message: alertMsg, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

extension SubscriptionsViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return channels.count
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 56
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SubCell")
            ?? UITableViewCell(style: .subtitle, reuseIdentifier: "SubCell")
        let ch = channels[indexPath.row]
        let p = ThemeManager.shared.palette
        cell.backgroundColor = p.background
        cell.textLabel?.textColor = p.primaryText
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        cell.detailTextLabel?.textColor = p.secondaryText
        cell.textLabel?.text = ch.name
        cell.detailTextLabel?.text = ch.id
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let ch = channels[indexPath.row]
        let vc = ChannelViewController(channelId: ch.id, channelName: ch.name)
        navigationController?.pushViewController(vc, animated: true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let ch = channels[indexPath.row]
            LocalStore.shared.unsubscribe(channelId: ch.id)
        }
    }
}
