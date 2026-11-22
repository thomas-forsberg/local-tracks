package no.thomasforsberg.localtracks.maps

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
    fun norwayOverviewIsSmallEnoughToDownloadOnce() {
        val overview = RegionSpec.NORWAY_OVERVIEW

        assertEquals(0, overview.minZoom)
        assertEquals(REGION_MIN_ZOOM - 1, overview.maxZoom)
        assertTrue(overview.tileCount < 1_000, "${overview.tileCount}")
    }
}
