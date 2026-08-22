import SwiftUI
import QuickLookThumbnailing

/// Async QuickLook thumbnails with an NSCache in front.
enum ThumbCache {
    static let cache = NSCache<NSString, NSImage>()

    static func key(_ item: FSItem, size: CGFloat) -> NSString {
        "\(item.id)|\(Int(size))" as NSString
    }

    static func cached(_ item: FSItem, size: CGFloat) -> NSImage? {
        cache.object(forKey: key(item, size: size))
    }

    static func store(_ image: NSImage, item: FSItem, size: CGFloat) {
        cache.setObject(image, forKey: key(item, size: size))
    }
}

struct ThumbnailView: View {
    let item: FSItem
    var size: CGFloat
    var cornerRadius: CGFloat = 4

    @State private var image: NSImage?

    private var isThumbable: Bool {
        switch item.category {
        case .image, .video: return true
        default: return item.url.pathExtension.lowercased() == "pdf"
        }
    }

    var body: some View {
        ZStack {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                FileIconView(item: item, size: size * 0.82)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
        .task(id: "\(item.id)-\(Int(size))") {
            await load()
        }
    }

    private func load() async {
        guard isThumbable, image == nil else { return }
        if let cached = ThumbCache.cached(item, size: size) {
            image = cached
            return
        }
        let url = item.url
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: size * scale, height: size * scale),
            scale: scale,
            representationTypes: [.thumbnail]
        )
        let result: NSImage? = await withCheckedContinuation { cont in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { thumbnail, _ in
                cont.resume(returning: thumbnail?.nsImage)
            }
        }
        guard let result else { return }
        ThumbCache.store(result, item: item, size: size)
        await MainActor.run { image = result }
    }
}
