import UIKit

final class SearchViewController: UIViewController {
    private enum Mode {
        case history
        case suggestions
        case results
    }

    private let searchBar = UISearchBar()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let stateView = StateView()

    private var mode: Mode = .history
    private var recentSearches: [String] = []
    private var suggestions: [String] = []
    private var results: [VideoItem] = []
    private var suggestWorkItem: DispatchWorkItem?
    private var activeQuery = ""

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSearchBar()
        setupTableView()
        applyTheme()
        recentSearches = LocalStore.shared.getRecentSearches()

        NotificationCenter.default.addObserver(self, selector: #selector(handleThemeChange), name: .themeDidChange, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if results.isEmpty {
            searchBar.becomeFirstResponder()
        }
    }

    private func setupSearchBar() {
        searchBar.placeholder = "Tìm video trên YouTube..."
        searchBar.delegate = self
        searchBar.returnKeyType = .search
        searchBar.autocapitalizationType = .none
        navigationItem.titleView = searchBar
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.keyboardDismissMode = .onDrag
        tableView.separatorStyle = .singleLine
        tableView.register(VideoCardCell.self, forCellReuseIdentifier: VideoCardCell.reuseIdentifier)
        view.addSubview(tableView)

        stateView.isHidden = true
        stateView.onRetry = { [weak self] in
            guard let self = self, !self.activeQuery.isEmpty else { return }
            self.performSearch(query: self.activeQuery)
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

    private func applyTheme() {
        let p = ThemeManager.shared.palette
        view.backgroundColor = p.background
        tableView.backgroundColor = p.background
        tableView.separatorColor = p.separator
        searchBar.barStyle = p.barStyle
        searchBar.tintColor = p.accent
        stateView.applyTheme()
    }

    private func performSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        activeQuery = trimmed
        searchBar.text = trimmed
        searchBar.resignFirstResponder()
        LocalStore.shared.addSearchQuery(trimmed)
        recentSearches = LocalStore.shared.getRecentSearches()

        mode = .results
        tableView.separatorStyle = .none
        stateView.showLoading("Đang tìm \"\(trimmed)\"...")

        ProviderManager.shared.search(query: trimmed) { [weak self] result in
            guard let self = self, self.activeQuery == trimmed else { return }
            switch result {
            case .success(let items):
                self.results = items
                if items.isEmpty {
                    self.stateView.showEmpty(title: "Không tìm thấy kết quả", message: "Hãy thử từ khóa khác.")
                } else {
                    self.stateView.hide()
                }
                self.tableView.reloadData()
            case .failure(let err):
                self.stateView.showError(message: err.localizedDescription)
            }
        }
    }

    private func fetchSuggestions(for text: String) {
        suggestWorkItem?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            mode = .history
            tableView.separatorStyle = .singleLine
            stateView.hide()
            tableView.reloadData()
            return
        }

        let item = DispatchWorkItem { [weak self] in
            ProviderManager.shared.fetchSearchSuggestions(query: trimmed) { result in
                guard let self = self else { return }
                if case .success(let list) = result, self.mode != .results {
                    self.suggestions = list
                    self.mode = .suggestions
                    self.tableView.separatorStyle = .singleLine
                    self.stateView.hide()
                    self.tableView.reloadData()
                }
            }
        }
        suggestWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}

extension SearchViewController: UISearchBarDelegate {
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
        if mode == .results && !searchText.isEmpty {
            mode = .suggestions
        }
        fetchSuggestions(for: searchText)
    }

    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        performSearch(query: searchBar.text ?? "")
    }
}

extension SearchViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch mode {
        case .history: return recentSearches.count
        case .suggestions: return suggestions.count
        case .results: return results.count
        }
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch mode {
        case .history, .suggestions:
            return 44
        case .results:
            return VideoCardCell.height(forWidth: tableView.bounds.width)
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if mode == .results {
            let cell = tableView.dequeueReusableCell(withIdentifier: VideoCardCell.reuseIdentifier, for: indexPath) as! VideoCardCell
            cell.configure(with: results[indexPath.row])
            return cell
        }

        let cell = tableView.dequeueReusableCell(withIdentifier: "SuggestCell")
            ?? UITableViewCell(style: .default, reuseIdentifier: "SuggestCell")
        let p = ThemeManager.shared.palette
        cell.backgroundColor = p.background
        cell.textLabel?.textColor = p.primaryText
        cell.textLabel?.font = UIFont.systemFont(ofSize: 14.5)
        if mode == .history {
            cell.textLabel?.text = "↺  " + recentSearches[indexPath.row]
        } else {
            cell.textLabel?.text = "⌕  " + suggestions[indexPath.row]
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch mode {
        case .history:
            performSearch(query: recentSearches[indexPath.row])
        case .suggestions:
            performSearch(query: suggestions[indexPath.row])
        case .results:
            RootContainerViewController.shared?.openVideo(results[indexPath.row])
        }
    }
}
