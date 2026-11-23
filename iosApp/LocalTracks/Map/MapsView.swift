import Shared
import SwiftUI

// The Maps tab: downloaded regions on a map, and choosing new areas to download.
struct MapsView: View {
    let library: MapLibrary
    @State private var isChoosingArea = false
    @State private var visibleSelection: BoundingBox?
    @State private var detailed = false
    @State private var areaName = ""
    @State private var renaming: MapRegion?
    @State private var newName = ""
    @State private var focus: RegionMapView.FocusRequest?

    // The rounded area that would be downloaded.
    private var chosenSpec: RegionSpec? {
        guard isChoosingArea, let visibleSelection else { return nil }
        let maxZoom = detailed ? RegionSpecKt.DETAILED_REGION_MAX_ZOOM : RegionSpecKt.DEFAULT_REGION_MAX_ZOOM
        return RegionSpec.companion.forSelection(selection: visibleSelection, maxZoom: maxZoom)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                map
                if isChoosingArea {
                    AreaChooser(
                        spec: chosenSpec,
                        availableBytes: library.availableBytes(),
                        name: $areaName,
                        detailed: $detailed,
                        onCancel: stopChoosing,
                        onDownload: download
                    )
                } else {
                    RegionList(
                        library: library,
                        onSelect: { focus = RegionMapView.FocusRequest(bounds: $0.spec.bounds) },
                        onRename: { region in
                            newName = region.name
                            renaming = region
                        }
                    )
                }
            }
            .background(Theme.background)
            .navigationTitle("Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add area", systemImage: "plus") {
                        areaName = library.nextAreaName()
                        isChoosingArea = true
                    }
                    .disabled(isChoosingArea || library.overview?.isComplete != true)
                }
            }
            .alert("Rename area", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Name", text: $newName)
                Button("Save") { renaming.map { library.rename($0, to: newName) } }
                Button("Cancel", role: .cancel) {}
            }
        }
        .task { await library.observe() }
    }

    private var map: some View {
        GeometryReader { geometry in
            let inset = Self.viewfinderInset(for: geometry.size)
            ZStack(alignment: .bottomLeading) {
                RegionMapView(
                    regions: library.displayableRegions,
                    fileURL: library.fileURL(for:),
                    selection: chosenSpec?.bounds,
                    selectionInset: isChoosingArea ? UIEdgeInsets(top: inset.height, left: inset.width, bottom: inset.height, right: inset.width) : nil,
                    onVisibleSelectionChange: { visibleSelection = $0 },
                    focus: focus
                )
                .accessibilityIdentifier("region-map")
                if isChoosingArea {
                    // The area being chosen; the blue outline shows it rounded out to whole grid squares.
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .foregroundStyle(.primary.opacity(0.6))
                        .padding(.horizontal, inset.width)
                        .padding(.vertical, inset.height)
                        .allowsHitTesting(false)
                }
                if !library.displayableRegions.isEmpty {
                    MapAttribution()
                }
                if library.overview?.isComplete != true {
                    OverviewPrompt(library: library)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    private static func viewfinderInset(for size: CGSize) -> CGSize {
        CGSize(width: 32, height: max(32, size.height * 0.12))
    }

    private func stopChoosing() {
        isChoosingArea = false
        visibleSelection = nil
    }

    private func download() {
        guard let spec = chosenSpec, AreaChooser.fits(spec, in: library.availableBytes()) else { return }
        let name = areaName.trimmingCharacters(in: .whitespacesAndNewlines)
        library.addArea(named: name.isEmpty ? library.nextAreaName() : name, spec: spec)
        stopChoosing()
    }
}

private struct OverviewPrompt: View {
    let library: MapLibrary

    var body: some View {
        let overview = library.overview
        let isDownloading = overview.map { library.downloading.contains($0.id) } ?? false
        VStack(spacing: 12) {
            Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
            Text("Maps stay on your phone").font(.headline)
            Text("Start with an overview of Norway (about \(Formatters.bytes(RegionSpecKt.NORWAY_OVERVIEW_BYTES))), then download detailed maps of the areas you go to. Maps are from Kartverket and work without a connection.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let overview, isDownloading {
                ProgressView(value: overview.progress).frame(maxWidth: 220)
            } else {
                if let overview, let failure = library.failures[overview.id] {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                }
                Button(overview == nil ? "Download overview" : "Continue download", action: library.downloadOverview)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

struct AreaChooser: View {
    let spec: RegionSpec?
    let availableBytes: Int64?
    @Binding var name: String
    @Binding var detailed: Bool
    let onCancel: () -> Void
    let onDownload: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Move the map to frame the area. It's rounded out to whole squares of about 10 km, so the download doesn't reveal your exact plans.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
            Toggle("Extra detail (about 4× larger)", isOn: $detailed)
            if let spec {
                StorageNeeded(spec: spec, availableBytes: availableBytes)
            }
            HStack {
                Button("Cancel", action: onCancel).buttonStyle(.bordered)
                Spacer()
                Button("Download", systemImage: "arrow.down.circle", action: onDownload)
                    .buttonStyle(.borderedProminent)
                    .disabled(spec.map { !Self.fits($0, in: availableBytes) } ?? true)
            }
        }
        .padding()
    }
}

extension AreaChooser {
    // Unknown free space doesn't block: the download stops by itself if the phone fills up.
    static func fits(_ spec: RegionSpec, in availableBytes: Int64?) -> Bool {
        availableBytes.map { spec.estimatedBytes <= $0 } ?? true
    }
}

// How much space the selected area needs, next to what's free, so a big download is never a surprise.
private struct StorageNeeded: View {
    let spec: RegionSpec
    let availableBytes: Int64?

    var body: some View {
        let fits = AreaChooser.fits(spec, in: availableBytes)
        VStack(alignment: .leading, spacing: 2) {
            Label("Needs about \(Formatters.bytes(spec.estimatedBytes))", systemImage: "internaldrive")
                .font(.headline)
                .foregroundStyle(fits ? Color.primary : Color.red)
            if let availableBytes {
                Text(fits
                    ? "\(Formatters.bytes(availableBytes)) free on this phone"
                    : "Only \(Formatters.bytes(availableBytes)) free on this phone. Zoom in to choose a smaller area.")
                    .font(.footnote)
                    .foregroundStyle(fits ? Color.secondary : Color.red)
            }
        }
        .monospacedDigit()
    }
}

private struct RegionList: View {
    let library: MapLibrary
    let onSelect: (MapRegion) -> Void
    let onRename: (MapRegion) -> Void

    var body: some View {
        List {
            ForEach(library.regions, id: \.id) { region in
                RegionRow(region: region, library: library)
                    .contentShape(.rect)
                    .onTapGesture { onSelect(region) }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await library.delete(region) } }
                    }
                    .contextMenu {
                        if region.kind == .area {
                            Button("Rename", systemImage: "pencil") { onRename(region) }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { Task { await library.delete(region) } }
                    }
            }
            if library.areas.isEmpty, library.overview?.isComplete == true {
                Text("No detailed maps yet. Tap + to download an area.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.plain)
        .themedList()
        .frame(maxHeight: 260)
    }
}

private struct RegionRow: View {
    let region: MapRegion
    let library: MapLibrary

    var body: some View {
        let isDownloading = library.downloading.contains(region.id)
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(region.kind == .overview ? "Norway overview" : region.name).font(.body.weight(.medium))
                if region.isComplete {
                    Text(Formatters.bytes(region.downloadedBytes)).font(.footnote).foregroundStyle(.secondary)
                } else if isDownloading {
                    ProgressView(value: region.progress)
                } else {
                    Text(library.failures[region.id] ?? "Paused at \(region.progress.formatted(.percent.precision(.fractionLength(0))))")
                        .font(.footnote)
                        .foregroundStyle(library.failures[region.id] == nil ? Color.secondary : Color.red)
                }
            }
            Spacer()
            if !region.isComplete {
                if isDownloading {
                    Button("Pause", systemImage: "pause.circle") { library.pause(region) }
                } else {
                    Button("Resume", systemImage: "arrow.down.circle") { library.start(region) }
                }
            }
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .font(.title3)
    }
}
