package no.thomasforsberg.localtracks.maps

import io.ktor.client.HttpClient
import io.ktor.client.engine.HttpClientEngine
import io.ktor.client.plugins.HttpRequestRetry
import io.ktor.client.plugins.HttpTimeout
import io.ktor.client.plugins.defaultRequest
import io.ktor.client.request.get
import io.ktor.client.request.header
import io.ktor.client.statement.bodyAsBytes
import io.ktor.http.HttpHeaders
import io.ktor.http.isSuccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.channels.produce
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlin.coroutines.CoroutineContext
import kotlin.random.Random
import kotlin.time.Clock

// Where tiles come from. Only Kartverket for now; other sources (e.g. OpenStreetMap) can be added later.
interface TileSource {
    val attribution: String

    fun url(tile: TileId): String
}

// Kartverket's topographic map of Norway, CC BY 4.0. The WMTS path is TileMatrix/TileRow/TileCol, i.e. z/y/x.
object KartverketTopo : TileSource {
    override val attribution = "© Kartverket"

    override fun url(tile: TileId) =
        "https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/${tile.zoom}/${tile.y}/${tile.x}.png"
}

class TileDownloadException(message: String) : Exception(message)

// The HTTP client for tile downloads: identifies the app (not the user), times out stalled requests and
// retries failures with exponential backoff.
fun tileHttpClient(engine: HttpClientEngine, retryBaseDelayMillis: Long = 1_000): HttpClient = HttpClient(engine) {
    expectSuccess = false
    install(HttpTimeout) {
        requestTimeoutMillis = 30_000
    }
    install(HttpRequestRetry) {
        retryOnServerErrors(maxRetries = 3)
        retryOnException(maxRetries = 3, retryOnTimeout = true)
        exponentialDelay(baseDelayMs = retryBaseDelayMillis)
    }
    defaultRequest {
        header(HttpHeaders.UserAgent, "LocalTracks/1")
    }
}

// Downloads a region's tiles into its MBTiles file. Tiles already in the file are skipped, so an interrupted
// download continues where it stopped. Tiles are requested in random order, so the requests don't trace
// a path across the map. Each tile takes ~200 ms to arrive, so speed depends on how many are in flight
// (measured: 4 → 22 tiles/s, 16 → 74, 60 → 175).
class RegionDownloader(
    private val client: HttpClient,
    private val repository: MapRegionRepository,
    private val openStore: (MapRegion) -> MBTilesStore,
    private val clock: Clock = Clock.System,
    private val source: TileSource = KartverketTopo,
    private val parallelRequests: Int = 32,
    private val random: Random = Random.Default,
    // Off the main thread: SQLite writes block.
    private val workContext: CoroutineContext = Dispatchers.Default,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(client: HttpClient, repository: MapRegionRepository, openStore: (MapRegion) -> MBTilesStore) :
        this(client, repository, openStore, Clock.System)

    // Returns when every tile is stored. Throws on a failed tile (after retries) or when cancelled;
    // everything stored until then is kept. @Throws makes failures Swift errors instead of crashes.
    @Throws(Exception::class)
    suspend fun download(regionId: Long): Unit = withContext(workContext) {
        val region = checkNotNull(repository.region(regionId)) { "No map region $regionId" }
        openStore(region).use { store ->
            store.writeMetadata(region.name, region.spec, source.attribution)
            val stored = store.storedTiles()
            val remaining = region.spec.tiles().filterNot { it in stored }.toList().shuffled(random)
            val progress = Progress(tiles = stored.size.toLong(), bytes = store.totalBytes())

            downloadAll(remaining) { batch ->
                store.putAll(batch)
                progress.add(batch)
                repository.updateProgress(regionId, progress.tiles, progress.bytes)
            }
            repository.complete(regionId, clock.now(), progress.tiles, progress.bytes)
        }
    }

    private suspend fun downloadAll(tiles: List<TileId>, save: (Map<TileId, ByteArray>) -> Unit) {
        val batch = mutableMapOf<TileId, ByteArray>()
        // Workers take turns saving, so the store is never written by two at once.
        val saving = Mutex()
        try {
            coroutineScope {
                val queue = produce { tiles.forEach { send(it) } }
                repeat(parallelRequests) {
                    launch {
                        for (tile in queue) {
                            val data = fetch(tile)
                            saving.withLock {
                                batch[tile] = data
                                if (batch.size >= BATCH_SIZE) {
                                    save(batch.toMap())
                                    batch.clear()
                                }
                            }
                        }
                    }
                }
            }
        } finally {
            // Keep what has arrived even when a tile failed or the download was cancelled.
            if (batch.isNotEmpty()) withContext(NonCancellable) { save(batch.toMap()) }
        }
    }

    private suspend fun fetch(tile: TileId): ByteArray {
        val response = client.get(source.url(tile))
        if (!response.status.isSuccess()) throw TileDownloadException("Tile $tile: HTTP ${response.status.value}")
        return response.bodyAsBytes().also { if (it.isEmpty()) throw TileDownloadException("Tile $tile: empty") }
    }

    private class Progress(var tiles: Long, var bytes: Long) {
        fun add(batch: Map<TileId, ByteArray>) {
            tiles += batch.size
            bytes += batch.values.sumOf { it.size.toLong() }
        }
    }

    private companion object {
        const val BATCH_SIZE = 50
    }
}
