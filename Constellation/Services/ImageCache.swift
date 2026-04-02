import UIKit

/// Thread-safe image cache for processed constellation illustrations
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let processingQueue = DispatchQueue(label: "com.constellation.imageprocessing", qos: .userInitiated, attributes: .concurrent)
    private var inFlightRequests: [String: [(UIImage?) -> Void]] = [:]
    private let lock = NSLock()

    private init() {
        // Configure cache limits
        cache.countLimit = 100
        cache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    /// Get a processed image from cache or load and process it
    func getProcessedImage(for filename: String, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = filename as NSString

        // Check cache first (fast path)
        if let cached = cache.object(forKey: cacheKey) {
            DispatchQueue.main.async {
                completion(cached)
            }
            return
        }

        // Check if already loading this image
        lock.lock()
        if var requests = inFlightRequests[filename] {
            requests.append(completion)
            inFlightRequests[filename] = requests
            lock.unlock()
            return
        }
        inFlightRequests[filename] = [completion]
        lock.unlock()

        // Load and process on background thread
        processingQueue.async { [weak self] in
            guard let self = self else { return }

            let processedImage = self.loadAndProcessImage(filename: filename)

            // Cache the result
            if let image = processedImage {
                self.cache.setObject(image, forKey: cacheKey, cost: self.imageCost(image))
            }

            // Notify all waiting requests
            self.lock.lock()
            let requests = self.inFlightRequests.removeValue(forKey: filename) ?? []
            self.lock.unlock()

            DispatchQueue.main.async {
                for request in requests {
                    request(processedImage)
                }
            }
        }
    }

    private func loadAndProcessImage(filename: String) -> UIImage? {
        let cleanFilename = filename.replacingOccurrences(of: ".png", with: "")

        var loadedImage: UIImage?

        // Try multiple loading paths
        if let url = Bundle.main.url(forResource: cleanFilename, withExtension: "png", subdirectory: "illustrations"),
           let image = UIImage(contentsOfFile: url.path) {
            loadedImage = image
        } else if let path = Bundle.main.path(forResource: cleanFilename, ofType: "png", inDirectory: "illustrations"),
                  let image = UIImage(contentsOfFile: path) {
            loadedImage = image
        } else if let path = Bundle.main.path(forResource: cleanFilename, ofType: "png"),
                  let image = UIImage(contentsOfFile: path) {
            loadedImage = image
        }

        guard let original = loadedImage else { return nil }

        // Process image (convert black to transparent)
        return convertBlackToTransparent(original)
    }

    private func convertBlackToTransparent(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let pixelData = context.data else { return nil }
        let data = pixelData.bindMemory(to: UInt8.self, capacity: width * height * 4)

        // Process pixels - make dark areas transparent
        for i in stride(from: 0, to: width * height * 4, by: 4) {
            let r = Double(data[i])
            let g = Double(data[i + 1])
            let b = Double(data[i + 2])

            let luminance = 0.299 * r + 0.587 * g + 0.114 * b
            data[i + 3] = UInt8(min(255, luminance * 2))
        }

        guard let newCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: newCGImage)
    }

    private func imageCost(_ image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// Clear all cached images
    func clearCache() {
        cache.removeAllObjects()
    }
}
