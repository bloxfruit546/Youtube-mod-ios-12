import UIKit

final class ImageLoader {
    static let shared = ImageLoader()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 15 * 1024 * 1024 // Hard cap 15 MB for iPhone 5s 1GB RAM
        c.countLimit = 60
        return c
    }()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0
        config.urlCache = nil // Managed manually via bounded NSCache
        config.httpMaximumConnectionsPerHost = 4
        return URLSession(configuration: config)
    }()

    private let decodeQueue = DispatchQueue(label: "com.litetube5s.imagedecode", qos: .userInitiated, attributes: .concurrent)
    private let lock = NSLock()
    private var runningTasks: [UUID: URLSessionDataTask] = [:]

    private init() {}

    @discardableResult
    func loadImage(
        from url: URL?,
        targetSize: CGSize? = nil,
        circular: Bool = false,
        completion: @escaping (UIImage?) -> Void
    ) -> UUID? {
        guard let url = url else {
            completion(nil)
            return nil
        }

        let key = cacheKey(for: url, circular: circular)
        if let cached = cache.object(forKey: key) {
            completion(cached)
            return nil
        }

        let token = UUID()
        let task = session.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            self.removeTask(for: token)

            guard error == nil, let data = data, !data.isEmpty else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            self.decodeQueue.async {
                guard let rawImage = UIImage(data: data) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }

                let processed = self.processImage(rawImage, targetSize: targetSize, circular: circular)
                let cost = self.estimatedMemoryCost(for: processed)
                self.cache.setObject(processed, forKey: key, cost: cost)

                DispatchQueue.main.async {
                    completion(processed)
                }
            }
        }

        lock.lock()
        runningTasks[token] = task
        lock.unlock()

        task.resume()
        return token
    }

    func cancel(_ token: UUID?) {
        guard let token = token else { return }
        lock.lock()
        let task = runningTasks.removeValue(forKey: token)
        lock.unlock()
        task?.cancel()
    }

    func clearMemoryCache() {
        cache.removeAllObjects()
    }

    private func removeTask(for token: UUID) {
        lock.lock()
        runningTasks.removeValue(forKey: token)
        lock.unlock()
    }

    private func cacheKey(for url: URL, circular: Bool) -> NSString {
        return "\(url.absoluteString)|c:\(circular ? 1 : 0)" as NSString
    }

    private func estimatedMemoryCost(for image: UIImage) -> Int {
        guard let cg = image.cgImage else {
            return Int(image.size.width * image.size.height * 4)
        }
        return cg.bytesPerRow * cg.height
    }

    /// Pre-decodes image on background thread and optionally clips circularly via CoreGraphics
    /// to avoid expensive GPU offscreen rendering (masksToBounds + cornerRadius) on Apple A7.
    private func processImage(_ image: UIImage, targetSize: CGSize?, circular: Bool) -> UIImage {
        let drawSize: CGSize
        if let target = targetSize, target.width > 0, target.height > 0 {
            drawSize = target
        } else {
            // Cap maximum dimension to 640px for 4-inch Retina display
            let maxDim: CGFloat = 320.0
            let scale = min(1.0, maxDim / max(image.size.width, image.size.height))
            drawSize = CGSize(width: max(1, floor(image.size.width * scale)),
                              height: max(1, floor(image.size.height * scale)))
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = !circular

        let renderer = UIGraphicsImageRenderer(size: drawSize, format: format)
        return renderer.image { _ in
            let rect = CGRect(origin: .zero, size: drawSize)
            if circular {
                UIBezierPath(ovalIn: rect).addClip()
            }
            let imgSize = image.size
            if imgSize.width > 0 && imgSize.height > 0 {
                let widthRatio = drawSize.width / imgSize.width
                let heightRatio = drawSize.height / imgSize.height
                let fillScale = max(widthRatio, heightRatio)
                let scaledW = imgSize.width * fillScale
                let scaledH = imgSize.height * fillScale
                let drawRect = CGRect(
                    x: (drawSize.width - scaledW) * 0.5,
                    y: (drawSize.height - scaledH) * 0.5,
                    width: scaledW,
                    height: scaledH
                )
                image.draw(in: drawRect)
            } else {
                image.draw(in: rect)
            }
        }
    }
}
