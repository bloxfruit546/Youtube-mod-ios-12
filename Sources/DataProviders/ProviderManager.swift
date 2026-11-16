import Foundation

final class ProviderManager: YouTubeDataSourceProtocol {
    static let shared = ProviderManager()

    let providerName = "FailoverChain"

    private let piped = PipedProvider()
    private let invidious = InvidiousProvider()
    private let innertube = InnertubeProvider()

    private init() {}

    private var orderedProviders: [YouTubeDataSourceProtocol] {
        switch LocalStore.shared.settings.preferredProvider {
        case .autoPipedFirst:
            return [piped, invidious, innertube]
        case .invidiousFirst:
            return [invidious, piped, innertube]
        case .innertubeFirst:
            return [innertube, piped, invidious]
        }
    }

    // MARK: - Failover Execution

    private func executeWithFailover<T>(
        index: Int = 0,
        providers: [YouTubeDataSourceProtocol],
        errors: [String] = [],
        operation: @escaping (YouTubeDataSourceProtocol, @escaping (Result<T, Error>) -> Void) -> Void,
        completion: @escaping (Result<T, Error>) -> Void
    ) {
        guard index < providers.count else {
            DispatchQueue.main.async {
                completion(.failure(DataProviderError.allProvidersFailed(errors)))
            }
            return
        }

        let current = providers[index]
        operation(current) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let value):
                DispatchQueue.main.async {
                    completion(.success(value))
                }
            case .failure(let err):
                let msg = "[\(current.providerName)] \(err.localizedDescription)"
                AppLogger.shared.warn("Provider failover -> \(msg)")
                self.executeWithFailover(
                    index: index + 1,
                    providers: providers,
                    errors: errors + [msg],
                    operation: operation,
                    completion: completion
                )
            }
        }
    }

    // MARK: - YouTubeDataSourceProtocol

    func fetchTrending(region: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        executeWithFailover(providers: orderedProviders, operation: { provider, cb in
            provider.fetchTrending(region: region, completion: cb)
        }, completion: completion)
    }

    func search(query: String, completion: @escaping (Result<[VideoItem], Error>) -> Void) {
        executeWithFailover(providers: orderedProviders, operation: { provider, cb in
            provider.search(query: query, completion: cb)
        }, completion: completion)
    }

    func fetchSearchSuggestions(query: String, completion: @escaping (Result<[String], Error>) -> Void) {
        // Use Innertube Google Suggest first for fast low-latency autocomplete, fallback to Piped/Invidious
        let suggestOrder: [YouTubeDataSourceProtocol] = [innertube, piped, invidious]
        executeWithFailover(providers: suggestOrder, operation: { provider, cb in
            provider.fetchSearchSuggestions(query: query, completion: cb)
        }, completion: completion)
    }

    func fetchVideoDetailsAndStreams(videoId: String, completion: @escaping (Result<StreamInfo, Error>) -> Void) {
        executeWithFailover(providers: orderedProviders, operation: { provider, cb in
            provider.fetchVideoDetailsAndStreams(videoId: videoId, completion: cb)
        }, completion: completion)
    }

    func fetchComments(videoId: String, completion: @escaping (Result<[CommentItem], Error>) -> Void) {
        let commentOrder: [YouTubeDataSourceProtocol] = [piped, invidious]
        executeWithFailover(providers: commentOrder, operation: { provider, cb in
            provider.fetchComments(videoId: videoId, completion: cb)
        }, completion: completion)
    }

    func fetchChannel(channelId: String, completion: @escaping (Result<ChannelItem, Error>) -> Void) {
        executeWithFailover(providers: orderedProviders, operation: { provider, cb in
            provider.fetchChannel(channelId: channelId, completion: cb)
        }, completion: completion)
    }

    // MARK: - Remote Config Update

    func refreshRemoteConfig(from urlString: String? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let target = (urlString ?? LocalStore.shared.settings.remoteConfigURL).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: target), !target.isEmpty else {
            completion(.failure(DataProviderError.invalidURL))
            return
        }

        HTTPClient.shared.requestJSONObject(url: url, timeout: 6.0) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let obj):
                    guard let dict = obj as? [String: Any] else {
                        completion(.failure(DataProviderError.decodingError("remote_config.json phải là JSON object")))
                        return
                    }
                    let pipedList = (dict["pipedInstances"] as? [String])?.filter { !$0.isEmpty }
                    let invidiousList = (dict["invidiousInstances"] as? [String])?.filter { !$0.isEmpty }
                    LocalStore.shared.updateSettings { s in
                        s.remoteConfigURL = target
                        if let p = pipedList, !p.isEmpty { s.pipedInstances = p }
                        if let i = invidiousList, !i.isEmpty { s.invidiousInstances = i }
                    }
                    let summary = "Cập nhật thành công: \(pipedList?.count ?? 0) Piped, \(invidiousList?.count ?? 0) Invidious."
                    AppLogger.shared.info("RemoteConfig: \(summary)")
                    completion(.success(summary))
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - Diagnostics (SSL/TLS & Latency Probe)

    func runDiagnostics(completion: @escaping ([SSLProbeResult]) -> Void) {
        let settings = LocalStore.shared.settings
        var targets: [String] = []
        targets.append(contentsOf: settings.pipedInstances.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/trending?region=\(settings.regionCode)" })
        targets.append(contentsOf: settings.invidiousInstances.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/ ")) + "/api/v1/stats" })
        targets.append("https://www.youtube.com/generate_204")

        let group = DispatchGroup()
        let lock = NSLock()
        var results: [SSLProbeResult] = []

        for urlStr in targets {
            group.enter()
            HTTPClient.shared.probeSSL(urlString: urlStr) { res in
                lock.lock()
                results.append(res)
                lock.unlock()
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(results)
        }
    }
}
