import SwiftUI
import AppKit

// MARK: - Win11-style folder icon

enum FolderVariant {
    case plain, home, desktop, downloads, documents, music, pictures, videos

    var emblem: String? {
        switch self {
        case .plain: return nil
        case .home: return "person.fill"
        case .desktop: return "desktopcomputer"
        case .downloads: return "arrow.down"
        case .documents: return "doc.text"
        case .music: return "music.note"
        case .pictures: return "photo"
        case .videos: return "film"
        }
    }

    /// Win11 special folders sit under the user's home.
    static func forFolderURL(_ url: URL) -> FolderVariant {
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let path = url.standardizedFileURL.path
        if path == home.path { return .home }
        let map: [String: FolderVariant] = [
            "Desktop": .desktop, "Downloads": .downloads, "Documents": .documents,
            "Music": .music, "Pictures": .pictures, "Videos": .videos,
        ]
        let parent = (path as NSString).deletingLastPathComponent
        if parent == home.path, let v = map[url.lastPathComponent] { return v }
        return .plain
    }
}

/// Two-tone yellow Windows 11 folder, vector-drawn at any size.
struct FolderIconView: View {
    var variant: FolderVariant = .plain
    var size: CGFloat

    var body: some View {
        let w = size
        let h = size * 0.80
        ZStack(alignment: .topLeading) {
            // Back silhouette: tab + body
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: size * 0.045, style: .continuous)
                    .frame(width: w * 0.42, height: h * 0.30)
                RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                    .frame(width: w, height: h * 0.82)
                    .padding(.top, h * 0.18)
            }
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(red: 0.937, green: 0.647, blue: 0.243), location: 0),   // #EFA53E
                        .init(color: Color(red: 0.851, green: 0.549, blue: 0.161), location: 1),   // #D98C29
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )

            // Front face
            RoundedRectangle(cornerRadius: size * 0.052, style: .continuous)
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: Color(red: 1.0, green: 0.878, blue: 0.525), location: 0),  // #FFE086
                            .init(color: Color(red: 1.0, green: 0.757, blue: 0.302), location: 1),  // #FFC14D
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(Color.white.opacity(0.55))
                        .frame(height: max(0.6, size * 0.012))
                        .padding(.horizontal, size * 0.02)
                }
                .frame(width: w, height: h * 0.70)
                .padding(.top, h * 0.24)
                .shadow(color: .black.opacity(0.13), radius: size * 0.025, y: size * 0.012)

            if let emblem = variant.emblem {
                Image(systemName: emblem)
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.96))
                    .shadow(color: .black.opacity(0.25), radius: size * 0.015, y: size * 0.008)
                    .frame(maxWidth: .infinity)
                    .padding(.top, h * 0.32)
            }
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .accessibilityLabel(Text("Folder"))
    }
}

// MARK: - Generic file icon (page with type emblem)

private struct PageShape: Shape {
    var fold: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let f = min(fold, rect.width * 0.4)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - f, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

enum FileIconColors {
    static func tint(_ category: FileCategory, scheme: ColorScheme) -> Color {
        switch category {
        case .folder: return Color(red: 0.85, green: 0.62, blue: 0.2)
        case .image: return Color(red: 0.06, green: 0.55, blue: 0.55)
        case .video: return Color(red: 0.48, green: 0.31, blue: 0.83)
        case .audio: return Color(red: 0.71, green: 0.16, blue: 0.61)
        case .document: return Color(red: 0.12, green: 0.37, blue: 0.80)
        case .archive: return Color(red: 0.78, green: 0.47, blue: 0.0)
        case .application: return Color(red: 0.15, green: 0.39, blue: 0.81)
        case .other: return Color(white: scheme == .dark ? 0.72 : 0.45)
        }
    }

    static func symbol(_ category: FileCategory) -> String {
        switch category {
        case .folder: return "folder.fill"
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "music.note"
        case .document: return "doc.text"
        case .archive: return "doc.zip"
        case .application: return "app.glyph"
        case .other: return "doc"
        }
    }
}

struct FileIconView: View {
    let item: FSItem
    var size: CGFloat
    @Environment(\.colorScheme) private var scheme

    private var isTextish: Bool {
        ["txt", "md", "log", "rtf"].contains(item.url.pathExtension.lowercased())
    }

    var body: some View {
        if item.isDirectory {
            FolderIconView(variant: FolderVariant.forFolderURL(item.url), size: size)
        } else if item.url.pathExtension.lowercased() == "app" {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            pageView
        }
    }

    private var pageView: some View {
        let w = size * 0.76
        let h = size
        let tint = FileIconColors.tint(item.category, scheme: scheme)
        return ZStack(alignment: .topTrailing) {
            PageShape(fold: size * 0.22)
                .fill(scheme == .dark ? Color(red: 0.84, green: 0.85, blue: 0.86) : Color.white)
                .overlay(
                    PageShape(fold: size * 0.22)
                        .stroke(Color.black.opacity(0.16), lineWidth: 0.8)
                )
                .frame(width: w, height: h)
                .shadow(color: .black.opacity(0.10), radius: size * 0.02, y: size * 0.015)

            // fold
            Path { p in
                let x = w - size * 0.22
                p.move(to: CGPoint(x: x, y: 0))
                p.addLine(to: CGPoint(x: w, y: size * 0.22))
                p.addLine(to: CGPoint(x: x, y: size * 0.22))
                p.closeSubpath()
            }
            .fill(Color(red: 0.90, green: 0.91, blue: 0.92))
            .frame(width: w, height: h)

            // type emblem
            Group {
                if isTextish {
                    VStack(alignment: .leading, spacing: size * 0.055) {
                        ForEach(0..<3, id: \.self) { i in
                            Capsule()
                                .fill(Color.gray.opacity(0.55))
                                .frame(width: w * (i == 2 ? 0.5 : 0.62), height: size * 0.035)
                        }
                    }
                } else {
                    Image(systemName: FileIconColors.symbol(item.category))
                        .font(.system(size: size * 0.30, weight: .medium))
                        .foregroundStyle(tint)
                }
            }
            .frame(width: w, height: h)
            .offset(y: size * 0.10)

            if item.isSymbolicLink {
                Circle()
                    .fill(Color.white)
                    .frame(width: size * 0.34, height: size * 0.34)
                    .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.6))
                    .overlay(
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: size * 0.15, weight: .semibold))
                            .foregroundStyle(Color(red: 0.2, green: 0.45, blue: 0.85))
                    )
                    .offset(x: -size * 0.13, y: size * 0.11)
            }
        }
        .frame(width: w + size * 0.02, height: h)
    }
}

// MARK: - Drive / PC / trash / misc icons

struct DriveIconView: View {
    var drive: DriveInfo
    var size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.906, green: 0.922, blue: 0.937), Color(red: 0.71, green: 0.75, blue: 0.80)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.10, style: .continuous)
                        .stroke(Color.black.opacity(0.22), lineWidth: 0.8)
                )
                .frame(width: size, height: size * 0.74)

            RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.97), Color(white: 0.88)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.86, height: size * 0.46)
                .offset(y: -size * 0.06)

            Circle()
                .fill(drive.isNetwork ? Color(red: 0.15, green: 0.45, blue: 0.85) : Color(red: 0.20, green: 0.72, blue: 0.35))
                .frame(width: size * 0.08, height: size * 0.08)
                .offset(x: size * 0.12, y: -size * 0.08)

            if drive.isNetwork {
                Image(systemName: "network")
                    .font(.system(size: size * 0.22, weight: .medium))
                    .foregroundStyle(Color(red: 0.2, green: 0.47, blue: 0.85))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, size * 0.10)
                    .offset(y: -size * 0.04)
            }
        }
        .frame(width: size, height: size * 0.74, alignment: .bottomLeading)
    }
}

struct PCIconView: View {
    var size: CGFloat
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.07, style: .continuous)
                    .fill(Color(red: 0.24, green: 0.27, blue: 0.31))
                    .frame(width: size, height: size * 0.64)
                RoundedRectangle(cornerRadius: size * 0.05, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.65, blue: 0.97), Color(red: 0.13, green: 0.41, blue: 0.83)], startPoint: .top, endPoint: .bottom))
                    .frame(width: size * 0.90, height: size * 0.54)
            }
            Capsule()
                .fill(Color(red: 0.56, green: 0.59, blue: 0.63))
                .frame(width: size * 0.10, height: size * 0.12)
            Capsule()
                .fill(Color(red: 0.42, green: 0.45, blue: 0.49))
                .frame(width: size * 0.52, height: size * 0.07)
        }
        .frame(width: size, height: size * 0.86)
    }
}

struct TrashIconView: View {
    var size: CGFloat
    var full: Bool = true
    var body: some View {
        let w = size, h = size
        ZStack(alignment: .top) {
            Path { p in
                p.move(to: CGPoint(x: w * 0.16, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.24))
                p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.98))
                p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.98))
                p.closeSubpath()
            }
            .fill(LinearGradient(colors: [
                Color(red: 0.66, green: 0.75, blue: 0.83).opacity(0.96),
                Color(red: 0.50, green: 0.62, blue: 0.73).opacity(0.96),
            ], startPoint: .top, endPoint: .bottom))
            .overlay(
                Path { p in
                    p.move(to: CGPoint(x: w * 0.16, y: h * 0.24))
                    p.addLine(to: CGPoint(x: w * 0.84, y: h * 0.24))
                    p.addLine(to: CGPoint(x: w * 0.76, y: h * 0.98))
                    p.addLine(to: CGPoint(x: w * 0.24, y: h * 0.98))
                    p.closeSubpath()
                }
                .stroke(Color(red: 0.36, green: 0.47, blue: 0.58).opacity(0.8), lineWidth: 0.8)
            )
            .frame(width: w, height: h)

            // ribs
            ForEach(0..<2, id: \.self) { i in
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: max(0.8, w * 0.035), height: h * 0.6)
                    .offset(x: (CGFloat(i) - 0.5) * w * 0.26, y: h * 0.30)
            }

            if full {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: w * 0.26, weight: .semibold))
                    .foregroundStyle(Color(red: 0.18, green: 0.42, blue: 0.65))
                    .offset(y: h * 0.46)
            }

            // lid + handle
            ZStack {
                RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                    .fill(Color(red: 0.48, green: 0.58, blue: 0.68))
                    .frame(width: w * 0.92, height: h * 0.09)
                    .offset(y: h * 0.12)
                RoundedRectangle(cornerRadius: w * 0.05, style: .continuous)
                    .fill(Color(red: 0.40, green: 0.50, blue: 0.60))
                    .frame(width: w * 0.34, height: h * 0.10)
                    .offset(y: h * 0.035)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Small nav icons

struct NavIcon: View {
    let symbol: String
    var color: Color = Color(red: 0.24, green: 0.47, blue: 0.78)
    var size: CGFloat = 17
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size - 2, weight: .medium))
            .foregroundStyle(color)
            .frame(width: size + 4, alignment: .center)
    }
}
