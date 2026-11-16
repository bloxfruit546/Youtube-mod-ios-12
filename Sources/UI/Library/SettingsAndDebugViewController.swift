import UIKit

final class SettingsAndDebugViewController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .grouped)
    private var ramTimer: Timer?
    private var diagnosticResults: [SSLProbeResult] = []
    private var isProbing = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Cài đặt & Debug"
        tableView.delegate = self
        tableView.dataSource = self
        view.addSubview(tableView)
        applyTheme()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reloadTable), name: .settingsDidChange, object: nil)
    }

    deinit {
        ramTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ramTimer?.invalidate()
        ramTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            self?.refreshRamCell()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ramTimer?.invalidate()
        ramTimer = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        tableView.frame = view.bounds
    }

    @objc private func handleThemeChange() {
        applyTheme()
        tableView.reloadData()
    }

    @objc private func reloadTable() {
        tableView.reloadData()
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.secondaryBackground
        tableView.separatorColor = p.separator
    }

    private func refreshRamCell() {
        let ip = IndexPath(row: 0, section: 2)
        if let cell = tableView.cellForRow(at: ip) {
            cell.detailTextLabel?.text = MemoryMonitor.formattedUsage()
        }
    }

    // MARK: - Actions

    private func chooseQuality() {
        let alert = UIAlertController(title: "Chất lượng tối đa", message: "Khuyên dùng 480p cho Apple A7", preferredStyle: .actionSheet)
        let cur = LocalStore.shared.settings.maxQuality
        for q in MaxVideoQuality.allCases {
            let mark = (q == cur) ? "✓ " : ""
            alert.addAction(UIAlertAction(title: mark + q.displayName, style: .default) { _ in
                LocalStore.shared.updateSettings { $0.maxQuality = q }
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func chooseProviderOrder() {
        let alert = UIAlertController(title: "Thứ tự nguồn dữ liệu", message: nil, preferredStyle: .actionSheet)
        let cur = LocalStore.shared.settings.preferredProvider
        for p in PreferredProvider.allCases {
            let mark = (p == cur) ? "✓ " : ""
            alert.addAction(UIAlertAction(title: mark + p.displayName, style: .default) { _ in
                LocalStore.shared.updateSettings { $0.preferredProvider = p }
            })
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        present(alert, animated: true)
    }

    private func editRegionCode() {
        let alert = UIAlertController(title: "Mã vùng Trending", message: "Ví dụ: VN, US, JP, KR", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = LocalStore.shared.settings.regionCode
            tf.autocapitalizationType = .allCharacters
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in
            let code = (alert.textFields?.first?.text ?? "VN").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            if !code.isEmpty {
                LocalStore.shared.updateSettings { $0.regionCode = code }
            }
        })
        present(alert, animated: true)
    }

    private func editInstances(isPiped: Bool) {
        let title = isPiped ? "Danh sách Piped Instances" : "Danh sách Invidious Instances"
        let currentList = isPiped ? LocalStore.shared.settings.pipedInstances : LocalStore.shared.settings.invidiousInstances
        let alert = UIAlertController(title: title, message: "Ngăn cách bằng dấu phẩy (,)", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = currentList.joined(separator: ",")
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Khôi phục mặc định", style: .destructive) { _ in
            LocalStore.shared.updateSettings { s in
                if isPiped {
                    s.pipedInstances = AppSettings.defaultPipedInstances
                } else {
                    s.invidiousInstances = AppSettings.defaultInvidiousInstances
                }
            }
        })
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Lưu", style: .default) { _ in
            let raw = alert.textFields?.first?.text ?? ""
            let parsed = raw
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !parsed.isEmpty {
                LocalStore.shared.updateSettings { s in
                    if isPiped { s.pipedInstances = parsed } else { s.invidiousInstances = parsed }
                }
            }
        })
        present(alert, animated: true)
    }

    private func promptRemoteConfig() {
        let alert = UIAlertController(title: "Tải remote_config.json", message: "Nhập URL tới file JSON chứa pipedInstances & invidiousInstances", preferredStyle: .alert)
        alert.addTextField { tf in
            tf.text = LocalStore.shared.settings.remoteConfigURL
            tf.placeholder = "https://raw.githubusercontent.com/.../remote_config.json"
            tf.keyboardType = .URL
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Hủy", style: .cancel))
        alert.addAction(UIAlertAction(title: "Tải ngay", style: .default) { [weak self] _ in
            let url = alert.textFields?.first?.text ?? ""
            ProviderManager.shared.refreshRemoteConfig(from: url) { res in
                let msg: String
                switch res {
                case .success(let summary): msg = summary
                case .failure(let err): msg = err.localizedDescription
                }
                let done = UIAlertController(title: "Remote Config", message: msg, preferredStyle: .alert)
                done.addAction(UIAlertAction(title: "OK", style: .default))
                self?.present(done, animated: true)
            }
        })
        present(alert, animated: true)
    }

    private func runSSLDiagnostics() {
        guard !isProbing else { return }
        isProbing = true
        diagnosticResults = []
        tableView.reloadData()

        ProviderManager.shared.runDiagnostics { [weak self] results in
            guard let self = self else { return }
            self.isProbing = false
            self.diagnosticResults = results
            self.tableView.reloadData()
        }
    }

    private func openLogViewer() {
        let vc = LogViewerViewController()
        navigationController?.pushViewController(vc, animated: true)
    }
}

extension SettingsAndDebugViewController: UITableViewDataSource, UITableViewDelegate {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 4
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "Phát & Giao diện"
        case 1: return "Nguồn dữ liệu (Failover)"
        case 2: return "Chẩn đoán (RAM, SSL/TLS, Logs)"
        case 3: return diagnosticResults.isEmpty ? nil : "Kết quả kiểm tra HTTPS/SSL"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch section {
        case 0: return 4
        case 1: return 4
        case 2: return 5
        case 3: return diagnosticResults.count
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "SetCell")
            ?? UITableViewCell(style: .value1, reuseIdentifier: "SetCell")
        let p = ThemeManager.shared.palette
        let s = LocalStore.shared.settings
        cell.backgroundColor = p.background
        cell.textLabel?.textColor = p.primaryText
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14.5)
        cell.detailTextLabel?.textColor = p.secondaryText
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 13)
        cell.accessoryType = .none

        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            cell.textLabel?.text = "Giao diện"
            cell.detailTextLabel?.text = ThemeManager.shared.mode.displayName
        case (0, 1):
            cell.textLabel?.text = "Chất lượng video tối đa"
            cell.detailTextLabel?.text = s.maxQuality.shortLabel
        case (0, 2):
            cell.textLabel?.text = "Mặc định Chỉ nghe (Audio-Only)"
            cell.detailTextLabel?.text = s.audioOnlyDefault ? "Bật" : "Tắt"
        case (0, 3):
            cell.textLabel?.text = "Mã vùng Trending"
            cell.detailTextLabel?.text = s.regionCode

        case (1, 0):
            cell.textLabel?.text = "Thứ tự nguồn phát"
            cell.detailTextLabel?.text = s.preferredProvider.rawValue.uppercased()
        case (1, 1):
            cell.textLabel?.text = "Piped instances"
            cell.detailTextLabel?.text = "\(s.pipedInstances.count) server"
            cell.accessoryType = .disclosureIndicator
        case (1, 2):
            cell.textLabel?.text = "Invidious instances"
            cell.detailTextLabel?.text = "\(s.invidiousInstances.count) server"
            cell.accessoryType = .disclosureIndicator
        case (1, 3):
            cell.textLabel?.text = "Cập nhật từ remote_config.json"
            cell.detailTextLabel?.text = s.remoteConfigURL.isEmpty ? "Chưa đặt" : "Đã đặt"
            cell.accessoryType = .disclosureIndicator

        case (2, 0):
            cell.textLabel?.text = "RAM thực tế (phys_footprint)"
            cell.detailTextLabel?.text = MemoryMonitor.formattedUsage()
        case (2, 1):
            cell.textLabel?.text = isProbing ? "Đang kiểm tra HTTPS/SSL..." : "Kiểm tra kết nối HTTPS/SSL & API"
            cell.textLabel?.textColor = p.accent
            cell.detailTextLabel?.text = nil
        case (2, 2):
            cell.textLabel?.text = "Xem logs.txt trực tiếp"
            cell.detailTextLabel?.text = nil
            cell.accessoryType = .disclosureIndicator
        case (2, 3):
            cell.textLabel?.text = "Sao chép toàn bộ Log"
            cell.detailTextLabel?.text = nil
        case (2, 4):
            cell.textLabel?.text = "Xóa logs.txt"
            cell.textLabel?.textColor = p.accent
            cell.detailTextLabel?.text = nil

        case (3, _):
            let res = diagnosticResults[indexPath.row]
            let host = URL(string: res.urlString)?.host ?? res.urlString
            cell.textLabel?.text = host
            if let err = res.errorDescription {
                cell.detailTextLabel?.text = "LỖI: \(err)"
                cell.detailTextLabel?.textColor = .red
            } else {
                cell.detailTextLabel?.text = "HTTP \(res.statusCode ?? 0) • \(res.latencyMs)ms"
                cell.detailTextLabel?.textColor = res.isSuccess ? UIColor(red: 0.1, green: 0.7, blue: 0.25, alpha: 1.0) : .orange
            }
        default:
            break
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch (indexPath.section, indexPath.row) {
        case (0, 0):
            ThemeManager.shared.toggle()
        case (0, 1):
            chooseQuality()
        case (0, 2):
            LocalStore.shared.updateSettings { $0.audioOnlyDefault.toggle() }
        case (0, 3):
            editRegionCode()
        case (1, 0):
            chooseProviderOrder()
        case (1, 1):
            editInstances(isPiped: true)
        case (1, 2):
            editInstances(isPiped: false)
        case (1, 3):
            promptRemoteConfig()
        case (2, 1):
            runSSLDiagnostics()
        case (2, 2):
            openLogViewer()
        case (2, 3):
            UIPasteboard.general.string = AppLogger.shared.readLogs()
            let alert = UIAlertController(title: "Đã sao chép", message: "Nội dung logs.txt đã được chép vào Clipboard.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        case (2, 4):
            AppLogger.shared.clearLogs()
            let alert = UIAlertController(title: "Đã xóa", message: "Đã làm sạch file logs.txt.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        default:
            break
        }
    }
}

final class LogViewerViewController: UIViewController {
    private let textView = UITextView()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "logs.txt"

        let copyBtn = UIBarButtonItem(title: "Copy", style: .plain, target: self, action: #selector(copyLogs))
        let clearBtn = UIBarButtonItem(title: "Xóa", style: .plain, target: self, action: #selector(clearLogs))
        navigationItem.rightBarButtonItems = [clearBtn, copyBtn]

        textView.isEditable = false
        textView.font = UIFont(name: "Menlo", size: 11) ?? UIFont.systemFont(ofSize: 11)
        view.addSubview(textView)

        applyTheme()
        loadText()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        textView.frame = view.bounds
    }

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        textView.backgroundColor = p.background
        textView.textColor = p.primaryText
    }

    private func loadText() {
        let pathInfo = "Đường dẫn: \(AppLogger.shared.logFileURL.path)\n"
        let ramInfo = "RAM: \(MemoryMonitor.formattedUsage())\n----------------------------------------\n"
        textView.text = pathInfo + ramInfo + AppLogger.shared.readLogs()
        if !textView.text.isEmpty {
            let bottom = NSRange(location: max(0, textView.text.count - 1), length: 1)
            textView.scrollRangeToVisible(bottom)
        }
    }

    @objc private func copyLogs() {
        UIPasteboard.general.string = textView.text
    }

    @objc private func clearLogs() {
        AppLogger.shared.clearLogs()
        loadText()
    }
}
