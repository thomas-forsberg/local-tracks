package no.thomasforsberg.localtracks.maps

import app.cash.sqldelight.db.SqlDriver
import no.thomasforsberg.localtracks.maps.db.MBTilesDatabase

// One region's tiles in an MBTiles file, which MapLibre can display as a raster source.
class MBTilesStore(private val driver: SqlDriver) : AutoCloseable {
    private val queries = MBTilesDatabase(driver).mBTilesQueries

    fun writeMetadata(name: String, spec: RegionSpec, attribution: String) {
        val bounds = spec.bounds
        mapOf(
            "name" to name,
            "format" to "png",
            "type" to "baselayer",
            "version" to "1",
            "minzoom" to spec.minZoom.toString(),
            "maxzoom" to spec.maxZoom.toString(),
            "bounds" to listOf(bounds.west, bounds.south, bounds.east, bounds.north).joinToString(","),
            "attribution" to attribution,
        ).forEach { (key, value) -> queries.setMetadata(key, value) }
    }

    fun metadata(): Map<String, String> = queries.metadata().executeAsList().associate { it.name to it.value_ }

    // In one transaction: a commit per tile would make large downloads slow.
    fun putAll(tiles: Map<TileId, ByteArray>) {
        queries.transaction {
            tiles.forEach { (tile, data) -> queries.putTile(tile.zoom.toLong(), tile.x.toLong(), tmsRow(tile).toLong(), data) }
        }
    }

    fun tile(tile: TileId): ByteArray? =
        queries.tile(tile.zoom.toLong(), tile.x.toLong(), tmsRow(tile).toLong()).executeAsOneOrNull()

    // What's already downloaded, so an interrupted download can continue where it stopped.
    fun storedTiles(): Set<TileId> = queries.storedTiles { zoom, column, row ->
        val z = zoom.toInt()
        TileId(z, column.toInt(), flip(row.toInt(), z))
    }.executeAsList().toSet()

    fun tileCount(): Long = queries.totals().executeAsOne().tileCount

    fun totalBytes(): Long = queries.totals().executeAsOne().bytes ?: 0

    override fun close() = driver.close()

    private fun tmsRow(tile: TileId) = flip(tile.y, tile.zoom)

    // XYZ counts rows from the top, TMS (MBTiles) from the bottom.
    private fun flip(row: Int, zoom: Int) = WebMercator.tilesPerSide(zoom) - 1 - row
}
