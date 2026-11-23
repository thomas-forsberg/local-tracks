package no.thomasforsberg.localtracks.maps

import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class RegionSpecTest {
    @Test
    fun selectionsInsideTheSameGridCellsDownloadTheSameTiles() {
        // Two different trips in the same part of Nordmarka.
        val one = RegionSpec.forSelection(BoundingBox(10.66, 59.99, 10.70, 60.01), DEFAULT_REGION_MAX_ZOOM)
        val other = RegionSpec.forSelection(BoundingBox(10.64, 59.98, 10.69, 60.00), DEFAULT_REGION_MAX_ZOOM)

        assertEquals(one, other)
        assertEquals(REGION_GRID_ZOOM, one.area.zoom)
    }

    @Test
    fun regionsCoverEveryZoomFromTheRegionMinimumToTheChosenMaximum() {
        val spec = RegionSpec.forSelection(BoundingBox(10.66, 59.99, 10.70, 60.01), DEFAULT_REGION_MAX_ZOOM)
        val zooms = spec.tiles().map { it.zoom }.toSet()

        assertEquals((REGION_MIN_ZOOM..DEFAULT_REGION_MAX_ZOOM).toSet(), zooms)
        assertEquals(spec.tileCount, spec.tiles().count().toLong())
    }

    @Test
    fun twoByTwoGridCellsAreAboutSeventyMegabytesToZoomFifteen() {
        // About 20 × 20 km in Nordmarka.
        val area = TileArea(REGION_GRID_ZOOM, 1084, 594, 1085, 595)
        val standard = RegionSpec(area, REGION_MIN_ZOOM, DEFAULT_REGION_MAX_ZOOM)
        val detailed = RegionSpec(area, REGION_MIN_ZOOM, DETAILED_REGION_MAX_ZOOM)

        assertEquals(1_366, standard.tileCount)
        assertEquals(68_300_000, standard.estimatedBytes)
        assertEquals(standard.tileCount + 4_096, detailed.tileCount)
    }

    @Test
    fun batchesListEveryTileOnceStartingWithTheCoarseZooms() {
        val spec = RegionSpec(TileArea(11, 1084, 594, 1086, 595), REGION_MIN_ZOOM, 13)
        val batches = spec.batches(Random(1)).toList()

        assertEquals(listOf(9, 10), batches.first().map { it.zoom })
        assertEquals(1 + 6, batches.size, "the coarse zooms, then one batch per grid square")
        val tiles = batches.flatten().flatMap { it.tiles().toList() }
        assertEquals(spec.tiles().toSet(), tiles.toSet())
        assertEquals(tiles.size, tiles.toSet().size)
    }

    @Test
    fun theOverviewIsBatchedByItsOwnTiles() {
        val tiles = RegionSpec.NORWAY_OVERVIEW.batches(Random(1)).flatten().flatMap { it.tiles().toList() }.toList()

        assertEquals(RegionSpec.NORWAY_OVERVIEW.tileCount, tiles.size.toLong())
    }

    @Test
    fun aCountySizedAreaIsEstimatedInGigabytes() {
        val innlandet = RegionSpec.forSelection(BoundingBox(8.0, 60.2, 12.8, 62.7), DEFAULT_REGION_MAX_ZOOM)

        assertTrue(innlandet.estimatedBytes > 5_000_000_000L, "${innlandet.estimatedBytes}")
    }

    @Test
    fun norwayOverviewIsSmallEnoughToDownloadOnce() {
        val overview = RegionSpec.NORWAY_OVERVIEW

        assertEquals(0, overview.minZoom)
        assertEquals(REGION_MIN_ZOOM - 1, overview.maxZoom)
        assertTrue(overview.tileCount < 1_000, "${overview.tileCount}")
    }
}
