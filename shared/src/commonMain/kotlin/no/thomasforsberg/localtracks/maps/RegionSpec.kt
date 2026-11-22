package no.thomasforsberg.localtracks.maps

// Downloaded areas are rounded out to whole tiles at this zoom (about 10 × 10 km in southern Norway),
// so the tiles requested reveal only a coarse grid cell, not the exact trip being planned.
const val REGION_GRID_ZOOM = 11

// Region downloads start here; the Norway overview covers the zoom levels below.
const val REGION_MIN_ZOOM = 9

const val DEFAULT_REGION_MAX_ZOOM = 15
const val DETAILED_REGION_MAX_ZOOM = 16

// Kartverket topo tiles in Norwegian terrain average about 50 KB (measured at zoom 13–16).
const val ESTIMATED_BYTES_PER_TILE = 50_000L

// Measured: low-zoom tiles are mostly sea and plain land, about 9 KB each.
const val NORWAY_OVERVIEW_BYTES = 6_500_000L

// About 1 GB: larger areas are better split up, and protect Kartverket from huge bulk downloads.
const val MAX_REGION_TILES = 20_000L

// Mainland Norway with Svalbard left out.
val NORWAY = BoundingBox(west = 4.0, south = 57.8, east = 31.5, north = 71.3)

// Which tiles to download: an area, at every zoom from minZoom to maxZoom.
data class RegionSpec(val area: TileArea, val minZoom: Int, val maxZoom: Int) {
    init {
        require(minZoom <= maxZoom) { "minZoom must not exceed maxZoom" }
    }

    val bounds: BoundingBox get() = area.bounds

    val tileCount: Long get() = (minZoom..maxZoom).sumOf { area.at(it).tileCount }

    val estimatedBytes: Long get() = tileCount * ESTIMATED_BYTES_PER_TILE

    val isTooLarge: Boolean get() = tileCount > MAX_REGION_TILES

    fun tiles(): Sequence<TileId> = (minZoom..maxZoom).asSequence().flatMap { area.at(it).tiles() }

    companion object {
        // A user-chosen area, rounded out to the region grid.
        fun forSelection(selection: BoundingBox, maxZoom: Int): RegionSpec =
            RegionSpec(TileArea.covering(selection, REGION_GRID_ZOOM), REGION_MIN_ZOOM, maxZoom)

        // Small-scale map of all of Norway, for finding your way around and choosing areas to download.
        // Every user downloads exactly the same tiles, so it reveals nothing about where they go.
        val NORWAY_OVERVIEW = RegionSpec(TileArea.covering(NORWAY, REGION_MIN_ZOOM - 1), minZoom = 0, maxZoom = REGION_MIN_ZOOM - 1)
    }
}
