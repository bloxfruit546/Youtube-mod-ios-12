import Foundation

struct SSLProbeResult {
    let urlString: String
    let statusCode: Int?
    let latencyMs: Int
    let errorDescription: String?

    var isSuccess: Bool {
        if let code = statusCode {
            return (200...399).contains(code)
        }
        return false
    }
}

final class HTTPClient {
    static let shared = HTTPClient()

    private let session: URLSession
    private let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 12_5_8 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/12.1.2 Mobile/15E148 Safari/604.1"

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.timeoutIntervalForResource = 12.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.httpMaximumConnectionsPerHost = 4
        config.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept-Language": "vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7"
        ]
        self.session = URLSession(configuration: config)
    }

    @discardableResult
    func requestData(
        url: URL,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        timeout: TimeInterval = 6.0,
        completion: @escaping (Result<Data, Error>) -> Void
    ) -> URLSessionDataTask {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if let headers = headers {
            for (k, v) in headers {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        let start = Date()
        let task = session.dataTask(with: request) { data, response, error in
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)

            if let error = error {
                let nsErr = error as NSError
                if nsErr.code != NSURLErrorCancelled {
                    AppLogger.shared.network("FAIL \(method) \(url.absoluteString) (\(elapsedMs)ms): \(error.localizedDescription)")
                }
                completion(.failure(error))
                return
            }

            guard let httpResp = response as? HTTPURLResponse else {
                let err = DataProviderError.networkError("Phản hồi không hợp lệ")
                completion(.failure(err))
                return
            }

            if httpResp.statusCode == 429 {
                AppLogger.shared.network("HTTP 429 Rate Limit \(url.host ?? "") (\(elapsedMs)ms)")
                completion(.failure(DataProviderError.rateLimited))
                return
            }

            guard (200...299).contains(httpResp.statusCode) else {
                AppLogger.shared.network("HTTP \(httpResp.statusCode) \(url.absoluteString) (\(elapsedMs)ms)")
                completion(.failure(DataProviderError.httpStatus(httpResp.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(DataProviderError.networkError("Dữ liệu rỗng")))
                return
            }

            completion(.success(data))
        }
        task.resume()
        return task
    }

    @discardableResult
    func requestJSONObject(
        url: URL,
        method: String = "GET",
        headers: [String: String]? = nil,
        body: Data? = nil,
        timeout: TimeInterval = 6.0,
        completion: @escaping (Result<Any, Error>) -> Void
    ) -> URLSessionDataTask {
        return requestData(url: url, method: method, headers: headers, body: body, timeout: timeout) { result in
            switch result {
            case .success(let data):
                do {
                    let obj = try JSONSerialization.jsonObject(with: data, options: [])
                    completion(.success(obj))
                } catch {
                    AppLogger.shared.error("JSON parse error at \(url.absoluteString): \(error.localizedDescription)")
                    completion(.failure(DataProviderError.decodingError(error.localizedDescription)))
                }
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }

    func probeSSL(urlString: String, completion: @escaping (SSLProbeResult) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(SSLProbeResult(urlString: urlString, statusCode: nil, latencyMs: 0, errorDescription: "URL không hợp lệ"))
            return
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6.0)
        request.httpMethod = "GET"
        let start = Date()
        let task = session.dataTask(with: request) { _, response, error in
            let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
            if let error = error {
                completion(SSLProbeResult(urlString: urlString, statusCode: nil, latencyMs: elapsedMs, errorDescription: error.localizedDescription))
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode
            completion(SSLProbeResult(urlString: urlString, statusCode: code, latencyMs: elapsedMs, errorDescription: nil))
        }
        task.resume()
    }
}
