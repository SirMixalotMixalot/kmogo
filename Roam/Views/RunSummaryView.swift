import SwiftUI

struct RunSummaryView: View {
    let record: RunRecord
    var arrivedCity: City?
    var isNew: Bool
    var onDone: () -> Void

    @State private var style: ShareStyle = .route
    @State private var mapImage: UIImage?
    @State private var rendered: UIImage?
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header
                    if let city = arrivedCity { arrival(city) }
                    preview
                    Picker("Style", selection: $style) {
                        ForEach(ShareStyle.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    shareButtons
                    details
                }
                .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: onDone) }
            }
            .task(id: "\(style.rawValue)-\(record.endPlace ?? "")") { await render() }
            .sensoryFeedback(.success, trigger: isNew && record.completed)
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(record.completed ? "🏁" : "🛑").font(.system(size: 52))
            Text(record.completed ? "Run complete!" : "Run ended early")
                .font(.largeTitle.bold())
            Text("\(Fmt.km(record.distanceKm)) km · \(Fmt.duration(record.duration)) of focus")
                .font(.headline).foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    private func arrival(_ city: City) -> some View {
        HStack(spacing: 14) {
            Text(city.emoji).font(.system(size: 40))
            VStack(alignment: .leading) {
                Text("You made it to \(city.name)!").font(.headline)
                Text("New city added to your passport.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Theme.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
    }

    private var preview: some View {
        ZStack {
            if style == .sticker {
                // Show the transparent sticker over a photo-ish backdrop.
                LinearGradient(colors: [.teal, .indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            if let rendered {
                Image(uiImage: rendered).resizable().scaledToFit()
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(9 / 16, contentMode: .fit)
        .frame(maxHeight: 460)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
    }

    private var shareButtons: some View {
        HStack(spacing: 12) {
            if let rendered {
                ShareLink(item: ShareableImage(image: rendered),
                          preview: SharePreview("My Roam run", image: Image(uiImage: rendered))) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    UIPasteboard.general.setData(rendered.pngData() ?? Data(), forPasteboardType: "public.png")
                    copied = true
                } label: {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    private var details: some View {
        VStack(spacing: 12) {
            row("Coins earned", "+\(record.coins)", "circle.hexagongrid.fill")
            row("Route", record.routeLabel, "map")
            if let place = record.endPlace { row("Finished near", place, "mappin") }
            row("Left the app", record.distractions == 0 ? "Never 💪" : "\(record.distractions)×", "eye.slash")
            if let host = record.groupHost { row("Group run", "Hosted by \(host)", "person.3") }
        }
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func row(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold().multilineTextAlignment(.trailing)
        }
    }

    private func render() async {
        copied = false
        if style == .map, mapImage == nil {
            mapImage = await MapSnapshot.make(path: record.path, size: ShareCardView.size, accent: Theme.uiOrange)
        }
        rendered = ShareCardRenderer.render(record, style: style, mapImage: mapImage)
    }
}
