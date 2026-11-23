package no.thomasforsberg.localtracks.storage

import no.thomasforsberg.localtracks.auto.AutoRecordStore
import no.thomasforsberg.localtracks.auto.HomeLocation
import no.thomasforsberg.localtracks.recording.LeadIn
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

// The version 7 data fix: stretches recorded before their start point was stored began at home.
class LeadInStartTest {
    private val database = createTestDatabase()
    private val repository = ActivityRepository(database)
    private val start = Instant.parse("2026-11-23T10:27:03Z")

    @Test
    fun olderStretchesStartAtTheSavedHome() {
        val older = repository.startActivity(Sport.HIKING, start, autoStarted = true, leadIn = LeadIn(260.seconds, 381.0, 464))
        val manual = repository.startActivity(Sport.HIKING, start, autoStarted = false, leadIn = null)
        AutoRecordStore(database).setHome(HomeLocation(59.94, 10.72))

        database.activityQueries.fillLeadInStartFromHome()

        assertEquals(59.94, repository.activity(older)?.leadIn?.startLatitude)
        assertEquals(10.72, repository.activity(older)?.leadIn?.startLongitude)
        assertNull(repository.activity(manual)?.leadIn)
    }

    @Test
    fun aStoredStartIsKept() {
        val id = repository.startActivity(Sport.HIKING, start, autoStarted = true, leadIn = LeadIn(60.seconds, 80.0, null, 59.0, 10.0))
        AutoRecordStore(database).setHome(HomeLocation(59.94, 10.72))

        database.activityQueries.fillLeadInStartFromHome()

        assertEquals(59.0, repository.activity(id)?.leadIn?.startLatitude)
    }
}
