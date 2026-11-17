package no.thomasforsberg.localtracks.storage

import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class ActivityRepositoryTest {
    private val repository = ActivityRepository(createTestDatabase())
    private val start = Instant.parse("2026-09-12T07:00:00Z")

    private val fullPoint = RecordedPoint(
        segmentIndex = 2,
        point = TrackPoint(
            latitude = 59.9765123,
            longitude = 10.7290456,
            elevationMeters = 184.2,
            time = start + 1.seconds,
            horizontalAccuracyMeters = 4.5,
            speedMetersPerSecond = 5.25,
            barometer = BarometerReading(start + 1.seconds, relativeAltitudeMeters = -1.75, pressureKilopascals = 99.123),
        ),
    )
    private val minimalPoint = RecordedPoint(
        segmentIndex = 2,
        point = TrackPoint(latitude = 59.98, longitude = 10.73, elevationMeters = null, time = start + 2.seconds),
    )

    @Test
    fun storesPointsLosslessly() {
        val id = repository.startActivity(Sport.HIKING, start)

        repository.appendPoints(id, firstSeq = 0, points = listOf(fullPoint, minimalPoint), totals = ActivityTotals(2.seconds, 10.0, 2))

        assertEquals(listOf(fullPoint, minimalPoint), repository.trackPoints(id))
        assertEquals(minimalPoint, repository.lastTrackPoint(id))
    }

    @Test
    fun keepsTotalsAndLeavesActivityUnfinishedUntilFinished() {
        val id = repository.startActivity(Sport.CYCLING, start)
        repository.appendPoints(id, 0, listOf(fullPoint), ActivityTotals(90.seconds, 123.4, 1))

        val unfinished = assertNotNull(repository.latestUnfinishedActivity())
        assertEquals(ActivitySummary(id, Sport.CYCLING, start, null, ActivityTotals(90.seconds, 123.4, 1)), unfinished)

        repository.finishActivity(id, start + 2.minutes, ActivityTotals(100.seconds, 150.0, 1))

        assertNull(repository.latestUnfinishedActivity())
        assertEquals(start + 2.minutes, repository.activity(id)?.finishedAt)
        assertEquals(ActivityTotals(100.seconds, 150.0, 1), repository.activity(id)?.totals)
    }

    @Test
    fun listsOnlyFinishedActivitiesNewestFirst() = runTest {
        val older = repository.startActivity(Sport.RUNNING, start)
        val newer = repository.startActivity(Sport.CYCLING, start + 1.minutes)
        repository.startActivity(Sport.HIKING, start + 2.minutes)
        repository.finishActivity(older, start + 10.minutes, ActivityTotals(10.minutes, 0.0, 0))
        repository.finishActivity(newer, start + 11.minutes, ActivityTotals(10.minutes, 0.0, 0))

        assertEquals(listOf(newer, older), repository.finishedActivities().first().map { it.id })
    }

    @Test
    fun deleteRemovesActivityAndItsPoints() {
        val id = repository.startActivity(Sport.HIKING, start)
        repository.appendPoints(id, 0, listOf(fullPoint, minimalPoint), ActivityTotals(2.seconds, 10.0, 2))
        val other = repository.startActivity(Sport.HIKING, start + 1.minutes)
        repository.appendPoints(other, 0, listOf(fullPoint), ActivityTotals(1.seconds, 0.0, 1))

        repository.delete(id)

        assertNull(repository.activity(id))
        assertEquals(emptyList(), repository.trackPoints(id))
        assertEquals(1, repository.trackPoints(other).size)
    }
}
