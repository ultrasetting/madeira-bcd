import SwiftUI
import UIKit

/// Loads and downsamples Steam artwork for Couch mode. Decoded images are kept
/// in a bounded cache, so the shelves stay smooth without holding full-size
/// heroes (3840×1240) in memory a game may need later.
@MainActor final class CouchImageCache {
    static let shared = CouchImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var loads: [NSString: Task<UIImage?, Never>] = [:]
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 200 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    init() { cache.totalCostLimit = 96 << 20 }

    func cached(_ url: URL, maxPixel: CGFloat) -> UIImage? {
        cache.object(forKey: key(url, maxPixel))
    }

    func image(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = key(url, maxPixel)
        if let hit = cache.object(forKey: key) { return hit }
        if let running = loads[key] { return await running.value }
        let session = session
        let task = Task<UIImage?, Never> {
            // A file URL (a cover chosen in Madeira) has no HTTP status.
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
                  let image = UIImage(data: data) else { return nil }
            let scale = min(1, maxPixel / max(image.size.width, image.size.height, 1))
            let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
            return await image.byPreparingThumbnail(ofSize: size) ?? image
        }
        loads[key] = task
        let image = await task.value
        loads[key] = nil
        if let image {
            let pixels = image.size.width * image.size.height * image.scale * image.scale
            cache.setObject(image, forKey: key, cost: Int(pixels * 4))
        }
        return image
    }

    /// Starts loading images the focus is likely to reach next.
    func prefetch(_ urls: [URL], maxPixel: CGFloat) {
        for url in urls where cached(url, maxPixel: maxPixel) == nil {
            Task { _ = await image(url, maxPixel: maxPixel) }
        }
    }

    private func key(_ url: URL, _ maxPixel: CGFloat) -> NSString {
        "\(Int(maxPixel))|\(url.absoluteString)" as NSString
    }
}

/// An image from CouchImageCache. `fill` crops to the frame it is given;
/// otherwise the image fits. The placeholder is told whether loading failed.
struct CouchImage<Placeholder: View>: View {
    let url: URL?
    var maxPixel: CGFloat
    var fill: Bool
    let placeholder: (_ failed: Bool) -> Placeholder
    @State private var image: UIImage?
    @State private var failed = false

    init(_ url: URL?, maxPixel: CGFloat = 800, fill: Bool = true,
         @ViewBuilder placeholder: @escaping (_ failed: Bool) -> Placeholder) {
        self.url = url
        self.maxPixel = maxPixel
        self.fill = fill
        self.placeholder = placeholder
        _image = State(initialValue: url.flatMap { CouchImageCache.shared.cached($0, maxPixel: maxPixel) })
        _failed = State(initialValue: url == nil)
    }

    var body: some View {
        Group {
            if let image {
                if fill {
                    Color.clear
                        .overlay { Image(uiImage: image).resizable().scaledToFill() }
                        .clipped()
                } else {
                    Image(uiImage: image).resizable().scaledToFit()
                }
            } else {
                placeholder(failed)
            }
        }
        .task(id: url) {
            guard let url else { image = nil; failed = true; return }
            if let hit = CouchImageCache.shared.cached(url, maxPixel: maxPixel) { image = hit; failed = false; return }
            image = nil
            failed = false
            let loaded = await CouchImageCache.shared.image(url, maxPixel: maxPixel)
            image = loaded
            failed = loaded == nil
        }
    }
}
