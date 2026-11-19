package no.thomasforsberg.localtracks.track

import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.GpxFixtures
import no.thomasforsberg.localtracks.gpx.GpxParser
import no.thomasforsberg.localtracks.geo.distanceMeters
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.math.PI
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
        val summary = loop.summary(Sport.CYCLING)

        assertEquals(727, summary.pointCount)
        assertEquals(726.seconds, summary.elapsed)
    }

    @Test
    fun smoothingRemovesMostOfTheGpsJitter() {
        // The fixture is a 520 m radius circle with ~1.5 m of jitter per point.
        val trueLength = 2 * PI * 520
        val raw = loop.zipWithNext(::distanceMeters).sum()
        val smoothed = loop.summary(Sport.CYCLING).distanceMeters

        assertEquals(3682.131, raw, absoluteTolerance = 0.01) // +12.7 %
        assertEquals(trueLength, smoothed, absoluteTolerance = trueLength * 0.01)
        assertEquals(3279.460, smoothed, absoluteTolerance = 0.01) // regression guard: +0.4 %
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
