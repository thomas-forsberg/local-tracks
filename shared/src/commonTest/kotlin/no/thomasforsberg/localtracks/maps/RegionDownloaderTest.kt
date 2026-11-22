package no.thomasforsberg.localtracks.maps

import app.cash.sqldelight.db.SqlDriver
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockRequestHandleScope
import io.ktor.client.engine.mock.respond
import io.ktor.client.request.HttpRequestData
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.recording.TestClock
import no.thomasforsberg.localtracks.storage.createInMemoryMBTilesDriver
import no.thomasforsberg.localtracks.storage.createTestDatabase
import kotlin.random.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue
import kotlin.time.Instant

class RegionDownloaderTest {
    private val now = Instant.parse("2026-11-22T12:00:00Z")
    private val repository = MapRegionRepository(createTestDatabase())

    // The downloader closes the store when done; the tests keep reading the same in-memory file afterwards.
    private val driver = object : SqlDriver by createInMemoryMBTilesDriver() {
        override fun close() {}
    }
    private val store = MBTilesStore(driver)

    // One grid cell at zoom 11, plus its four children at zoom 12.
    private val fiveTiles = RegionSpec(TileArea(11, 1084, 594, 1084, 594), minZoom = 11, maxZoom = 12)

    private val requests = mutableListOf<HttpRequestData>()
    private val recording = Mutex()

    private fun downloader(
        parallelRequests: Int = 4,
        respond: suspend MockRequestHandleScope.(HttpRequestData) -> io.ktor.client.request.HttpResponseData = { respondTile() },
    ) = RegionDownloader(
        client = tileHttpClient(
            MockEngine { request ->
                recording.withLock { requests += request }
                respond(request)
            },
            retryBaseDelayMillis = 1,
        ),
        repository = repository,
        openStore = { store },
        clock = TestClock(now),
        parallelRequests = parallelRequests,
        random = Random(42),
    )

    private fun MockRequestHandleScope.respondTile() = respond(byteArrayOf(1, 2, 3, 4), HttpStatusCode.OK)

    private fun createRegion(spec: RegionSpec = fiveTiles) = repository.create(MapRegionKind.AREA, "Nordmarka", spec, now)

    @Test
    fun downloadsEveryTileAndCompletesTheRegion() = runTest {
        val region = createRegion()

        downloader().download(region.id)

        assertEquals(fiveTiles.tiles().toSet(), store.storedTiles())
        val done = repository.region(region.id)!!
        assertTrue(done.isComplete)
        assertEquals(5, done.downloadedTiles)
        assertEquals(20, done.downloadedBytes)
        assertEquals("© Kartverket", store.metadata()["attribution"])
    }

    @Test
    fun requestsKartverketTopoTilesInWmtsOrderWithoutIdentifyingTheUser() = runTest {
        val region = createRegion(RegionSpec(TileArea(11, 1084, 594, 1084, 594), minZoom = 11, maxZoom = 11))

        downloader().download(region.id)

        val request = requests.single()
        assertEquals("https://cache.kartverket.no/v1/wmts/1.0.0/topo/default/webmercator/11/594/1084.png", request.url.toString())
        assertEquals("LocalTracks/1", request.headers[HttpHeaders.UserAgent])
    }

    @Test
    fun requestsTilesInRandomOrder() = runTest {
        val spec = RegionSpec(TileArea(11, 1084, 594, 1084, 594), minZoom = 11, maxZoom = 13)
        val region = createRegion(spec)

        downloader(parallelRequests = 1).download(region.id)

        val requested = requests.map { it.url.encodedPath }
        val inGridOrder = spec.tiles().map { KartverketTopo.url(it).substringAfter("kartverket.no") }.toList()
        assertEquals(inGridOrder.toSet(), requested.toSet())
        assertNotEquals(inGridOrder, requested)
    }

    @Test
    fun continuesAnInterruptedDownloadWithoutFetchingStoredTilesAgain() = runTest {
        val region = createRegion()
        val alreadyStored = fiveTiles.tiles().take(3).associateWith { byteArrayOf(7) }
        store.putAll(alreadyStored)

        downloader().download(region.id)

        assertEquals(2, requests.size)
        assertEquals(5, repository.region(region.id)?.downloadedTiles)
        assertEquals(3 + 2 * 4, repository.region(region.id)?.downloadedBytes)
    }

    @Test
    fun retriesServerErrors() = runTest {
        val region = createRegion()
        var failures = 0

        downloader { if (failures++ < 2) respond("", HttpStatusCode.ServiceUnavailable) else respondTile() }.download(region.id)

        assertTrue(repository.region(region.id)!!.isComplete)
    }

    @Test
    fun aMissingTileFailsTheDownloadButKeepsWhatArrived() = runTest {
        val region = createRegion()
        val missing = fiveTiles.tiles().last()

        assertFailsWith<TileDownloadException> {
            downloader(parallelRequests = 1) { request ->
                if (request.url.toString() == KartverketTopo.url(missing)) respond("", HttpStatusCode.NotFound) else respondTile()
            }.download(region.id)
        }

        assertFalse(repository.region(region.id)!!.isComplete)
        assertFalse(missing in store.storedTiles())
        // Tiles requested before the missing one are stored.
        val before = requests.indexOfFirst { it.url.toString() == KartverketTopo.url(missing) }
        assertEquals(before, store.storedTiles().size)
    }
}
