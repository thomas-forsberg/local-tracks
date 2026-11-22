package no.thomasforsberg.localtracks.maps

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class TilesTest {
    @Test
    fun tileCoordinatesAtWellKnownPoints() {
        assertEquals(1.0, WebMercator.tileX(0.0, 1), absoluteTolerance = 1e-9)
        assertEquals(1.0, WebMercator.tileY(0.0, 1), absoluteTolerance = 1e-9)
        assertEquals(0.0, WebMercator.tileX(-180.0, 5), absoluteTolerance = 1e-9)
        assertEquals(0.0, WebMercator.tileY(WebMercator.MAX_LATITUDE, 5), absoluteTolerance = 1e-6)
    }

    @Test
    fun tileEdgesConvertBackToTheSameTile() {
        val zoom = 15
        assertEquals(17359.0, WebMercator.tileX(WebMercator.longitude(17359, zoom), zoom), absoluteTolerance = 1e-6)
        assertEquals(9516.0, WebMercator.tileY(WebMercator.latitude(9516, zoom), zoom), absoluteTolerance = 1e-6)
    }

    @Test
    fun coveringFindsTheTilesKartverketServesForAPlace() {
        // Nordmarka, north of Oslo; Kartverket serves this as topo/default/webmercator/15/9516/17359.png.
        val area = TileArea.covering(BoundingBox(west = 10.713, south = 59.995, east = 10.72, north = 59.998), zoom = 15)

        assertEquals(TileArea(15, 17359, 9516, 17359, 9516), area)
    }

    @Test
    fun zoomingInGivesTheChildrenAndZoomingOutTheParents() {
        val area = TileArea(zoom = 11, minX = 1084, minY = 594, maxX = 1085, maxY = 595)

        assertEquals(TileArea(13, 4336, 2376, 4343, 2383), area.at(13))
        assertEquals(64, area.at(13).tileCount)
        assertEquals(TileArea(10, 542, 297, 542, 297), area.at(10))
        assertEquals(area, area.at(11))
    }

    @Test
    fun tilesListsEveryTileOnce() {
        val area = TileArea(zoom = 3, minX = 1, minY = 2, maxX = 3, maxY = 3)
        val tiles = area.tiles().toList()

        assertEquals(6, tiles.size)
        assertEquals(6, tiles.toSet().size)
        assertEquals(area.tileCount, tiles.size.toLong())
    }

    @Test
    fun boundsCoverTheArea() {
        val box = BoundingBox(west = 10.6, south = 59.95, east = 10.8, north = 60.05)
        val bounds = TileArea.covering(box, 11).bounds

        assertTrue(bounds.west <= box.west && bounds.east >= box.east)
        assertTrue(bounds.south <= box.south && bounds.north >= box.north)
    }
}
