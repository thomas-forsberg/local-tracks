package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.FailingDriver
import no.thomasforsberg.localtracks.storage.createDatabase
import no.thomasforsberg.localtracks.storage.createInMemoryDriver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class StorageFailureTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")
    private val clock = TestClock(start)
    private val driver = FailingDriver(createInMemoryDriver())
    private val repository = ActivityRepository(createDatabase(driver))
    private val recorder = ActivityRecorder(RecordingSession(clock), repository, clock)

    private fun recordAt(second: Int) {
        clock.now = start + second.seconds
        recorder.onLocation(LocationFix(clock.now, 59.9 + second * 0.0001, 10.7, 5.0, null, null))
    }

    private fun storedPoints() = repository.trackPoints(assertNotNull(repository.latestUnfinishedActivity()).id)

    @Test
    fun aFailedFlushKeepsThePointsAndWritesThemOnTheNextSuccess() {
        recorder.start(Sport.CYCLING)
        driver.failWrites = true
        (1..5).forEach(::recordAt) // flush at 5 s fails

        assertTrue(recorder.isStorageFailing)
        assertIs<RecordingState.Recording>(recorder.state.value, "recording carries on")
        driver.failWrites = false
        assertEquals(0, storedPoints().size)

        (6..10).forEach(::recordAt) // flush at 10 s succeeds

        assertFalse(recorder.isStorageFailing)
        assertEquals((0 until 10).toList(), storedPoints().indices.toList())
        assertEquals(10, storedPoints().size)
    }

    @Test
    fun ifTheActivityCantBeCreatedAtStartItIsCreatedOnTheFirstSuccessfulWrite() {
        driver.failWrites = true
        assertTrue(recorder.start(Sport.RUNNING))
        assertTrue(recorder.isStorageFailing)
        assertNull(repository.latestUnfinishedActivity())

        driver.failWrites = false
        (1..5).forEach(::recordAt)

        assertEquals(Sport.RUNNING, repository.latestUnfinishedActivity()?.sport)
        assertEquals(start, repository.latestUnfinishedActivity()?.startedAt)
        assertEquals(5, storedPoints().size)
    }

    @Test
    fun ifStoppingFailsTheActivityStaysUnfinishedForRecovery() {
        recorder.start(Sport.HIKING)
        (1..5).forEach(::recordAt)
        driver.failWrites = true

        assertTrue(recorder.stop())

        assertTrue(recorder.isStorageFailing)
        driver.failWrites = false
        assertEquals(5, assertNotNull(recorder.unfinishedActivity()).totals.pointCount)
    }
}
