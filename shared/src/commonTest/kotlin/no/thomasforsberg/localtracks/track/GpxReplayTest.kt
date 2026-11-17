package no.thomasforsberg.localtracks.track

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.GpxFixtures
import no.thomasforsberg.localtracks.gpx.GpxParser
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlin.time.measureTimedValue

class GpxReplayTest {
    // 1 Hz synthetic loop with ~1.5 m GPS jitter; expected values come from the generator.
    private val loop = GpxParser.parseTrackPoints(GpxFixtures.read("synthetic-sognsvann-loop.gpx"))

    @Test
    fun summarisesRecordedTrack() {
        val summary = loop.summary()

        assertEquals(727, summary.pointCount)
        assertEquals(3682.131, summary.distanceMeters, absoluteTolerance = 0.01)
        assertEquals(726.seconds, summary.elapsed)
    }

    @Test
    fun replaysEveryPointWithRecordedTimingSpedUp() = runTest {
        val (replayed, took) = testScheduler.timeSource.measureTimedValue { loop.replay(speedFactor = 10.0).toList() }

        assertEquals(loop, replayed)
        assertEquals(72.6.seconds, took)
    }

    @Test
    fun replaysPointsWithoutTimestampsImmediately() = runTest {
        val untimed = loop.take(5).map { it.copy(time = null) }

        val (replayed, took) = testScheduler.timeSource.measureTimedValue { untimed.replay().toList() }

        assertEquals(untimed, replayed)
        assertEquals(Duration.ZERO, took)
    }

    @Test
    fun rejectsNonPositiveSpeedFactor() {
        assertFailsWith<IllegalArgumentException> { loop.replay(speedFactor = 0.0) }
    }
}
