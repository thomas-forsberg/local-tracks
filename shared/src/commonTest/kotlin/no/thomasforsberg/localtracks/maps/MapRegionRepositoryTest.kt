package no.thomasforsberg.localtracks.maps

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.storage.createTestDatabase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Instant

class MapRegionRepositoryTest {
    private val repository = MapRegionRepository(createTestDatabase())
    private val now = Instant.parse("2026-11-22T12:00:00Z")
    private val spec = RegionSpec(TileArea(11, 1084, 594, 1085, 595), REGION_MIN_ZOOM, DEFAULT_REGION_MAX_ZOOM)

    @Test
    fun createsARegionThatIsNotYetDownloaded() {
        val region = repository.create(MapRegionKind.AREA, "Nordmarka", spec, now)

        assertEquals(spec, region.spec)
        assertFalse(region.isComplete)
        assertEquals(0.0, region.progress)
        assertEquals("region-${region.id}.mbtiles", region.fileName)
    }

    @Test
    fun tracksProgressAndCompletion() {
        val id = repository.create(MapRegionKind.AREA, "Nordmarka", spec, now).id

        repository.updateProgress(id, tiles = spec.tileCount / 2, bytes = 1_000)
        assertEquals(0.5, repository.region(id)?.progress ?: 0.0, absoluteTolerance = 0.01)

        repository.complete(id, now + 5.minutes, tiles = spec.tileCount, bytes = 2_000)
        val done = repository.region(id)
        assertTrue(done?.isComplete == true)
        assertEquals(2_000, done?.downloadedBytes)
    }

    @Test
    fun listsTheOverviewFirstThenAreasOldestFirst() = runTest {
        repository.create(MapRegionKind.AREA, "Older", spec, now)
        repository.create(MapRegionKind.AREA, "Newer", spec, now + 1.minutes)
        repository.create(MapRegionKind.OVERVIEW, "Norway", RegionSpec.NORWAY_OVERVIEW, now + 2.minutes)

        assertEquals(listOf("Norway", "Older", "Newer"), repository.regions().first().map { it.name })
    }

    @Test
    fun renamesAndDeletes() {
        val id = repository.create(MapRegionKind.AREA, "Area", spec, now).id

        repository.rename(id, "Nordmarka")
        assertEquals("Nordmarka", repository.region(id)?.name)

        repository.delete(id)
        assertNull(repository.region(id))
    }
}
