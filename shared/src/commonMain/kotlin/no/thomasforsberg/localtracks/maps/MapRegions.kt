package no.thomasforsberg.localtracks.maps

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Map_region
import kotlin.coroutines.CoroutineContext
import kotlin.time.Instant

enum class MapRegionKind { OVERVIEW, AREA }

data class MapRegion(
    val id: Long,
    val kind: MapRegionKind,
    val name: String,
    val spec: RegionSpec,
    val createdAt: Instant,
    val completedAt: Instant?,
    val downloadedTiles: Long,
    val downloadedBytes: Long,
) {
    val isComplete: Boolean get() = completedAt != null

    // Name of the region's MBTiles file, in the maps directory.
    val fileName: String get() = "region-$id.mbtiles"

    val progress: Double get() = if (spec.tileCount == 0L) 1.0 else downloadedTiles.toDouble() / spec.tileCount
}

class MapRegionRepository(
    private val database: LocalTracksDatabase,
    private val queryContext: CoroutineContext = Dispatchers.Default,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(database: LocalTracksDatabase) : this(database, Dispatchers.Default)

    private val queries get() = database.mapRegionQueries

    fun create(kind: MapRegionKind, name: String, spec: RegionSpec, createdAt: Instant): MapRegion = database.transactionWithResult {
        val area = spec.area
        queries.insert(
            kind, name, area.zoom.toLong(), area.minX.toLong(), area.minY.toLong(), area.maxX.toLong(), area.maxY.toLong(),
            spec.minZoom.toLong(), spec.maxZoom.toLong(), createdAt,
        )
        val id = queries.lastInsertedId().executeAsOne()
        checkNotNull(queries.byId(id).executeAsOneOrNull()).toMapRegion()
    }

    fun region(id: Long): MapRegion? = queries.byId(id).executeAsOneOrNull()?.toMapRegion()

    fun allRegions(): List<MapRegion> = queries.all().executeAsList().map { it.toMapRegion() }

    // Overview first, then areas oldest first; emits again whenever a region changes.
    fun regions(): Flow<List<MapRegion>> =
        queries.all().asFlow().mapToList(queryContext).map { rows -> rows.map { it.toMapRegion() } }

    fun updateProgress(id: Long, tiles: Long, bytes: Long) = queries.updateProgress(tiles, bytes, id)

    fun complete(id: Long, completedAt: Instant, tiles: Long, bytes: Long) = queries.complete(completedAt, tiles, bytes, id)

    fun rename(id: Long, name: String) = queries.rename(name, id)

    // The caller deletes the region's file too.
    fun delete(id: Long) = queries.delete(id)
}

private fun Map_region.toMapRegion() = MapRegion(
    id = id,
    kind = kind,
    name = name,
    spec = RegionSpec(
        area = TileArea(area_zoom.toInt(), min_x.toInt(), min_y.toInt(), max_x.toInt(), max_y.toInt()),
        minZoom = min_zoom.toInt(),
        maxZoom = max_zoom.toInt(),
    ),
    createdAt = created_at,
    completedAt = completed_at,
    downloadedTiles = downloaded_tiles,
    downloadedBytes = downloaded_bytes,
)
