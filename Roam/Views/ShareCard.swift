import SwiftUI
import MapKit
import UniformTypeIdentifiers

enum ShareStyle: String, CaseIterable, Identifiable {
    case route = "Route"
    case map = "Map"
    case sticker = "Sticker"
    var id: String { rawValue }
}

/// A 9:16 Strava-style card, rendered at 1080×1920 for Instagram stories.
struct ShareCardView: View {
    let record: RunRecord
    let style: ShareStyle
    var mapImage: UIImage?

    static let size = CGSize(width: 360, height: 640)

    private var isSticker: Bool { style == .sticker }

    var body: some View {
        ZStack {
            background
            VStack(alignment: .leading, spacing: 0) {
                if !isSticker { topBar }
                Spacer(minLength: 0)
                if style != .map {
                    RouteShape(points: record.path)
                        .stroke(Theme.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(isSticker ? 0.5 : 0.3), radius: 4)
                        .frame(height: isSticker ? 230 : 260)
                        .padding(.horizontal, 12)
                    Spacer(minLength: 0)
                }
                stats
            }
            .padding(28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .sticker:
            Color.clear
        case .map:
            if let mapImage {
                Image(uiImage: mapImage).resizable().scaledToFill()
                    .frame(width: Self.size.width, height: Self.size.height).clipped()
                    .overlay(LinearGradient(colors: [.black.opacity(0.55), .clear, .clear, .black.opacity(0.85)],
                                            startPoint: .top, endPoint: .bottom))
            } else {
                LinearGradient(colors: [Theme.dusk, Theme.night], startPoint: .top, endPoint: .bottom)
            }
        case .route:
            ZStack {
                LinearGradient(colors: [Theme.dusk, Theme.night], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Theme.orange.opacity(0.35), .clear], center: .init(x: 0.5, y: 0.35),
                               startRadius: 10, endRadius: 260)
            }
        }
    }

    private var topBar: some View {
        HStack {
            Wordmark()
            Spacer()
            Text(record.startDate.formatted(.dateTime.month(.abbreviated).day().year()))
                .font(.system(size: 13, weight: .semibold))
                .opacity(0.8)
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.isGroup ? "GROUP STUDY RUN" : "STUDY RUN")
                    .font(.system(size: 12, weight: .bold)).tracking(2)
                    .foregroundStyle(Theme.orange)
                Text(record.routeLabel)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .lineLimit(1).minimumScaleFactor(0.6)
                if let place = record.endPlace {
                    Text("Now near \(place)").font(.system(size: 13, weight: .medium)).opacity(0.8)
                }
            }
            HStack(alignment: .top, spacing: 18) {
                stat("Distance", Fmt.km(record.distanceKm), "km")
                stat("Focus time", Fmt.duration(record.duration), nil)
                stat("Pace", Fmt.pace(record.paceSecPerKm), "/km")
            }
            if isSticker {
                Wordmark(size: 15)
            } else if let host = record.groupHost {
                Text("Ran together with \(host)'s crew").font(.system(size: 12, weight: .medium)).opacity(0.75)
            }
        }
        .shadow(color: .black.opacity(isSticker ? 0.6 : 0), radius: 3)
    }

    private func stat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).opacity(0.7)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 28, weight: .heavy, design: .rounded)).minimumScaleFactor(0.5)
                if let unit { Text(unit).font(.system(size: 13, weight: .semibold)).opacity(0.8) }
            }
        }
        .lineLimit(1)
    }
}

struct Wordmark: View {
    var size: CGFloat = 20
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "figure.run").font(.system(size: size * 0.9, weight: .heavy))
                .foregroundStyle(Theme.orange)
            Text("ROAM").font(.system(size: size, weight: .black, design: .rounded)).tracking(1.5)
        }
    }
}

/// Draws a lat/lon polyline fitted (aspect-preserving) into its frame – the "trail shape".
struct RouteShape: Shape {
    let points: [Coordinate]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard points.count >= 2 else { return path }
        let mp = points.map(\.mapPoint)
        let minX = mp.map(\.x).min()!, maxX = mp.map(\.x).max()!
        let minY = mp.map(\.y).min()!, maxY = mp.map(\.y).max()!
        let w = max(maxX - minX, 1e-9), h = max(maxY - minY, 1e-9)
        let scale = min(rect.width / w, rect.height / h)
        let ox = rect.midX - (minX + w / 2 - minX) * scale
        let oy = rect.midY - (minY + h / 2 - minY) * scale
        let cg = mp.map { CGPoint(x: ox + ($0.x - minX) * scale, y: oy + ($0.y - minY) * scale) }
        path.addLines(cg)
        return path
    }
}

/// PNG export (keeps transparency for the sticker style).
struct ShareableImage: Transferable {
    let image: UIImage

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { $0.image.pngData() ?? Data() }
            .suggestedFileName("roam-run.png")
    }
}

@MainActor
enum ShareCardRenderer {
    static func render(_ record: RunRecord, style: ShareStyle, mapImage: UIImage?) -> UIImage? {
        let renderer = ImageRenderer(content: ShareCardView(record: record, style: style, mapImage: mapImage))
        renderer.scale = 3 // 1080 × 1920
        renderer.isOpaque = style != .sticker
        return renderer.uiImage
    }
}
