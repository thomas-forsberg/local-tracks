package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.GpxFixtures
import no.thomasforsberg.localtracks.gpx.GpxParser
import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.createTestDatabase
import no.thomasforsberg.localtracks.track.summary
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class ActivityRecorderTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")
    private val clock = TestClock(start)
    private val repository = ActivityRepository(createTestDatabase())
    private val recorder = newRecorder()

    // A fresh recorder on the same database, as after an app restart.
    private fun newRecorder() = ActivityRecorder(RecordingSession(clock), repository, clock)

    private fun fixAt(second: Int) = LocationFix(
        time = start + second.seconds,
        latitude = 59.9 + second * 0.0001,
        longitude = 10.7,
        horizontalAccuracyMeters = 5.0,
        altitudeMeters = 180.0,
        speedMetersPerSecond = null,
    )

    // Moves the clock along with the fix, as on a device.
    private fun ActivityRecorder.recordAt(second: Int): Boolean {
        clock.now = start + second.seconds
        return onLocation(fixAt(second))
    }

    private fun storedActivityId() = assertNotNull(repository.latestUnfinishedActivity()).id

    @Test
    fun startCreatesAnUnfinishedActivity() {
        assertTrue(recorder.start(Sport.CYCLING))

        val activity = assertNotNull(repository.latestUnfinishedActivity())
        assertEquals(Sport.CYCLING, activity.sport)
        assertEquals(start, activity.startedAt)
    }

    @Test
    fun writesPointsInBatchesEveryFlushInterval() {
        recorder.start(Sport.CYCLING)
        (1..4).forEach { recorder.recordAt(it) }

        assertEquals(0, repository.trackPoints(storedActivityId()).size)

        recorder.recordAt(5)

        assertEquals(5, repository.trackPoints(storedActivityId()).size)
        assertEquals(5, repository.latestUnfinishedActivity()?.totals?.pointCount)
    }

    @Test
    fun pauseAndExplicitFlushWriteImmediately() {
        recorder.start(Sport.RUNNING)
        recorder.recordAt(1)
        recorder.flush()
        assertEquals(1, repository.trackPoints(storedActivityId()).size)

        recorder.recordAt(2)
        recorder.pause()
        assertEquals(2, repository.trackPoints(storedActivityId()).size)
    }

    @Test
    fun stopWritesRemainingPointsAndFinishesTheActivity() {
        recorder.start(Sport.HIKING)
        val id = storedActivityId()
        (1..3).forEach { recorder.recordAt(it) }
        clock.now = start + 10.seconds

        assertTrue(recorder.stop())

        val activity = assertNotNull(repository.activity(id))
        assertEquals(start + 10.seconds, activity.finishedAt)
        assertEquals(10.seconds, activity.totals.activeTime)
        assertEquals(3, activity.totals.pointCount)
        assertEquals(22.24, activity.totals.distanceMeters, absoluteTolerance = 0.01)
        assertEquals(3, repository.trackPoints(id).size)
        assertNull(recorder.unfinishedActivity())
    }

    @Test
    fun recoversAfterACrashLosingOnlyUnflushedPoints() {
        recorder.start(Sport.CYCLING)
        val id = storedActivityId()
        (1..7).forEach { recorder.recordAt(it) } // flushed at 5 s; 6 and 7 still pending

        // App killed: the old recorder is gone, a new one starts on the same database.
        val restarted = newRecorder()
        clock.now = start + 60.seconds
        assertEquals(id, restarted.unfinishedActivity()?.id)

        assertTrue(restarted.resumeUnfinished())
        val paused = assertIs<RecordingState.Paused>(restarted.state.value)
        assertEquals(5, paused.progress.pointCount)
        assertEquals(44.48, paused.progress.distanceMeters, absoluteTolerance = 0.01)
        assertEquals(5.seconds, paused.activeTime(clock.now))

        restarted.resume()
        restarted.recordAt(61)
        restarted.recordAt(62)
        clock.now = start + 70.seconds
        restarted.stop()

        val points = repository.trackPoints(id)
        assertEquals(listOf(0, 0, 0, 0, 0, 1, 1), points.map { it.segmentIndex })
        assertEquals(7, assertNotNull(repository.activity(id)).totals.pointCount)
        assertEquals(15.seconds, assertNotNull(repository.activity(id)).totals.activeTime)
    }

    @Test
    fun finishUnfinishedEndsAtTheLastStoredPoint() {
        recorder.start(Sport.RUNNING)
        val id = storedActivityId()
        (1..5).forEach { recorder.recordAt(it) }

        val restarted = newRecorder()
        assertTrue(restarted.finishUnfinished())

        assertEquals(start + 5.seconds, repository.activity(id)?.finishedAt)
        assertNull(restarted.unfinishedActivity())
        assertFalse(restarted.resumeUnfinished())
    }

    @Test
    fun recordingAReplayedTrackStoresEveryPoint() {
        val loop = GpxParser.parseTrackPoints(GpxFixtures.read("synthetic-sognsvann-loop.gpx"))
        clock.now = assertNotNull(loop.first().time)
        recorder.start(Sport.CYCLING)
        val id = storedActivityId()

        loop.forEach { point ->
            clock.now = assertNotNull(point.time)
            recorder.onLocation(LocationFix(clock.now, point.latitude, point.longitude, 5.0, point.elevationMeters, null))
        }
        recorder.stop()

        assertEquals(loop.size, repository.trackPoints(id).size)
        assertEquals(loop.summary().distanceMeters, assertNotNull(repository.activity(id)).totals.distanceMeters, absoluteTolerance = 1e-6)
    }
}
