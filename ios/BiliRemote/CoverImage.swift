import SwiftUI

enum CoverURL {
    static func normalized(_ source: String?) -> URL? {
        guard let source, !source.isEmpty else { return nil }
        let value = source.hasPrefix("//") ? "https:" + source : source
        guard var parts = URLComponents(string: value), let host = parts.host else { return nil }
        if host.hasSuffix(".hdslb.com") {
            if parts.scheme == "http" { parts.scheme = "https" }
            parts.percentEncodedPath = parts.percentEncodedPath.components(separatedBy: "@").first ?? ""
        }
        guard parts.scheme == "https" else { return nil }
        return parts.url
    }
}

struct RemoteCoverImage: View {
    let source: String?
    @State private var image: UIImage?
    @State private var loadedURL: URL?
    @State private var failed = false
    @State private var retry = 0
    @Environment(\.scenePhase) private var scenePhase
    private var url: URL? { CoverURL.normalized(source) }
    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        Group {
            if let image, loadedURL == url { Image(uiImage: image).resizable().scaledToFill() }
            else { Image(systemName: "play.rectangle.fill").font(.title2).foregroundStyle(Color.biliPink.opacity(0.5)) }
        }
        .task(id: "\(url?.absoluteString ?? "")-\(retry)") { await load() }
        .onChange(of: scenePhase) { _, phase in if phase == .active && failed { retry += 1 } }
    }

    @MainActor private func load() async {
        image = nil; loadedURL = nil; failed = false
        guard let url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; loadedURL = url; return }
        for attempt in 0..<3 {
            do {
                if attempt > 0 { try await Task.sleep(for: .seconds(attempt)) }
                try Task.checkCancellation()
                var request = URLRequest(url: url, cachePolicy: attempt == 0 ? .returnCacheDataElseLoad : .reloadIgnoringLocalCacheData, timeoutInterval: 12)
                request.setValue("https://www.bilibili.com/", forHTTPHeaderField: "Referer")
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard (response as? HTTPURLResponse)?.statusCode == 200, let decoded = UIImage(data: data) else { continue }
                // Downsample before retaining covers; a scrolling list must not cache full-resolution posters.
                let thumbnail = await decoded.byPreparingThumbnail(ofSize: CGSize(width: 960, height: 540)) ?? decoded
                try Task.checkCancellation()
                Self.cache.totalCostLimit = 32 * 1024 * 1024
                Self.cache.setObject(thumbnail, forKey: url as NSURL, cost: Int(thumbnail.size.width * thumbnail.size.height * thumbnail.scale * thumbnail.scale * 4))
                image = thumbnail; loadedURL = url; return
            } catch { if Task.isCancelled { return } }
        }
        failed = true
    }
}
