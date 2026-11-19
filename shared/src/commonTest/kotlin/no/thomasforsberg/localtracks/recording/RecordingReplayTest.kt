package no.thomasforsberg.localtracks.recording

import kotlinx.coroutines.test.runTest
import no.thomasforsberg.localtracks.GpxFixtures
import no.thomasforsberg.localtracks.gpx.GpxParser
import no.thomasforsberg.localtracks.track.TrackPoint
import no.thomasforsberg.localtracks.track.replay
import no.thomasforsberg.localtracks.track.summary
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.time.Duration.Companion.seconds

class RecordingReplayTest {
    private val loop = GpxParser.parseTrackPoints(GpxFixtures.read("synthetic-sognsvann-loop.gpx"))

    private fun TrackPoint.asFix() = LocationFix(
        time = assertNotNull(time),
        latitude = latitude,
        longitude = longitude,
        horizontalAccuracyMeters = 5.0,
        altitudeMeters = elevationMeters,
        speedMetersPerSecond = null,
    )

    @Test
    fun recordingAReplayedTrackMatchesItsSummary() = runTest {
        val clock = TestClock(assertNotNull(loop.first().time))
        val session = RecordingSession(clock)
        session.start(Sport.CYCLING)

        loop.replay(speedFactor = 100.0).collect { point ->
            clock.now = assertNotNull(point.time)
            session.onLocation(point.asFix())
        }
        session.stop()

        val finished = assertIs<RecordingState.Finished>(session.state.value)
        assertEquals(loop.size, finished.progress.pointCount)
        assertEquals(loop.summary(Sport.CYCLING).distanceMeters, finished.progress.distanceMeters, absoluteTolerance = 1e-6)
        assertEquals(726.seconds, finished.activeTime(clock.now))
    }
}
