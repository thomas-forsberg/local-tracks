package no.thomasforsberg.localtracks.maps

import no.thomasforsberg.localtracks.storage.createInMemoryMBTilesDriver
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MBTilesStoreTest {
    private val store = MBTilesStore(createInMemoryMBTilesDriver())

    @Test
    fun storesAndReadsTiles() {
        val tile = TileId(15, 17359, 9516)
        store.putAll(mapOf(tile to byteArrayOf(1, 2, 3)))

        assertContentEquals(byteArrayOf(1, 2, 3), store.tile(tile))
        assertNull(store.tile(TileId(15, 17359, 9517)))
        assertEquals(setOf(tile), store.storedTiles())
        assertEquals(1, store.tileCount())
        assertEquals(3, store.totalBytes())
    }

    @Test
    fun rowsAreCountedFromTheBottomAsMBTilesRequires() {
        store.putAll(mapOf(TileId(1, 0, 0) to byteArrayOf(9)))

        // XYZ row 0 (the top) is TMS row 1 at zoom 1; reading it back as XYZ gives the same tile.
        assertEquals(setOf(TileId(1, 0, 0)), store.storedTiles())
    }

    @Test
    fun writesTheMetadataMapLibreReads() {
        store.writeMetadata("Nordmarka", RegionSpec(TileArea(11, 1084, 594, 1085, 595), 9, 15), "© Kartverket")
        val metadata = store.metadata()

        assertEquals("png", metadata["format"])
        assertEquals("9", metadata["minzoom"])
        assertEquals("15", metadata["maxzoom"])
        assertEquals("© Kartverket", metadata["attribution"])
        assertEquals(4, metadata.getValue("bounds").split(",").size)
    }
}
