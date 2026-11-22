package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.recording.RecordingState.Finished
import no.thomasforsberg.localtracks.recording.RecordingState.Idle
import no.thomasforsberg.localtracks.recording.RecordingState.Paused
import no.thomasforsberg.localtracks.recording.RecordingState.Recording
import no.thomasforsberg.localtracks.track.TrackMeasurement
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class RecordingSessionTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")
    private val clock = TestClock(start)
    private val session = RecordingSession(clock)

    // ~111 m per 0.001° of latitude.
    private fun fix(
        secondsAfterStart: Int,
        latitude: Double = 59.9 + secondsAfterStart * 0.0001,
        accuracy: Double = 5.0,
        speed: Double? = null,
    ) = LocationFix(
        time = start + secondsAfterStart.seconds,
        latitude = latitude,
        longitude = 10.7,
        horizontalAccuracyMeters = accuracy,
        altitudeMeters = 180.0,
        speedMetersPerSecond = speed,
    )

    private fun progress() = assertNotNull(session.state.value.progressOrNull())

    @Test
    fun startsIdleAndIgnoresFixesUntilStarted() {
        assertEquals(Idle, session.state.value)
        assertNull(session.onLocation(fix(1)))
    }

    @Test
    fun recordsAccurateFixesAndAccumulatesDistance() {
        session.start(Sport.CYCLING)

        val first = assertNotNull(session.onLocation(fix(1)))
        session.onLocation(fix(2))
        session.onLocation(fix(3))

        assertEquals(0, first.segmentIndex)
        assertEquals(3, progress().pointCount)
        assertEquals(22.24, progress().distanceMeters, absoluteTolerance = 0.01)
        assertEquals(Sport.CYCLING, progress().sport)
    }

    @Test
    fun dropsInaccurateAndInvalidFixes() {
        session.start(Sport.RUNNING)

        assertNull(session.onLocation(fix(1, accuracy = 25.0)))
        assertNull(session.onLocation(fix(2, accuracy = -1.0)))
        assertNotNull(session.onLocation(fix(3, accuracy = 20.0)))
        assertEquals(1, progress().pointCount)
    }

    @Test
    fun dropsFixesFromBeforeStartAndOutOfOrderOrDuplicateFixes() {
        clock.advanceBy(10.seconds)
        session.start(Sport.HIKING)

        assertNull(session.onLocation(fix(5)), "cached fix from before start")
        assertNotNull(session.onLocation(fix(12)))
        assertNull(session.onLocation(fix(12)), "duplicate")
        assertNull(session.onLocation(fix(11)), "out of order")
        assertEquals(1, progress().pointCount)
    }

    @Test
    fun pauseIgnoresFixesAndResumeStartsNewSegmentWithoutBridgingDistance() {
        session.start(Sport.CYCLING)
        session.onLocation(fix(1))
        session.onLocation(fix(2))
        val distanceBeforePause = progress().distanceMeters

        clock.now = start + 3.seconds
        assertTrue(session.pause())
        assertNull(session.onLocation(fix(4)))

        clock.now = start + 60.seconds
        assertTrue(session.resume())
        // Moved ~1 km while paused; that gap must not count.
        val afterResume = assertNotNull(session.onLocation(fix(61, latitude = 59.91)))
        session.onLocation(fix(62, latitude = 59.9101))

        assertEquals(1, afterResume.segmentIndex)
        assertEquals(distanceBeforePause + 11.12, progress().distanceMeters, absoluteTolerance = 0.01)
    }

    @Test
    fun activeTimeExcludesPausesWhileElapsedIncludesThem() {
        session.start(Sport.HIKING)
        clock.advanceBy(10.minutes)
        session.pause()
        clock.advanceBy(5.minutes)
        session.resume()
        clock.advanceBy(20.minutes)

        val state = session.state.value
        assertEquals(30.minutes, state.activeTime(clock.now))
        assertEquals(35.minutes, state.elapsed(clock.now))
        assertEquals(1800.0, state.activeTimeSeconds(clock.now))
        assertEquals(2100.0, state.elapsedSeconds(clock.now))

        session.stop()
        clock.advanceBy(1.minutes)
        val finished = assertIs<Finished>(session.state.value)
        assertEquals(30.minutes, finished.activeTime(clock.now))
        assertEquals(35.minutes, finished.elapsed(clock.now))
    }

    @Test
    fun averageSpeedUsesActiveTime() {
        session.start(Sport.CYCLING)
        session.onLocation(fix(0, latitude = 59.9))
        clock.advanceBy(100.seconds)
        session.onLocation(fix(100, latitude = 59.909))

        assertEquals(10.0, assertNotNull(session.state.value.averageSpeedMetersPerSecond(clock.now)), absoluteTolerance = 0.01)
    }

    @Test
    fun currentSpeedPrefersReportedSpeedAndFallsBackToComputed() {
        session.start(Sport.RUNNING)
        session.onLocation(fix(0))
        assertNull(progress().currentSpeedMetersPerSecond)

        session.onLocation(fix(1))
        assertEquals(11.12, assertNotNull(progress().currentSpeedMetersPerSecond), absoluteTolerance = 0.01)

        session.onLocation(fix(2, speed = 3.5))
        assertEquals(3.5, progress().currentSpeedMetersPerSecond)

        session.onLocation(fix(3, speed = -1.0))
        assertEquals(11.12, assertNotNull(progress().currentSpeedMetersPerSecond), absoluteTolerance = 0.01)
    }

    @Test
    fun attachesOnlyFreshBarometerReadings() {
        session.start(Sport.HIKING)
        val reading = BarometerReading(start + 1.seconds, relativeAltitudeMeters = 2.5, pressureKilopascals = 99.1)
        session.onBarometer(reading)

        assertEquals(reading, session.onLocation(fix(3))?.point?.barometer)
        assertNull(assertNotNull(session.onLocation(fix(7))).point.barometer, "6 s old reading is stale")
    }

    @Test
    fun accumulatesElevationGainFromBarometerAndNotAcrossPauses() {
        fun recordAt(second: Int, relativeAltitude: Double) {
            clock.now = start + second.seconds
            session.onBarometer(BarometerReading(clock.now, relativeAltitude, pressureKilopascals = 99.0))
            session.onLocation(fix(second))
        }
        session.start(Sport.HIKING)
        recordAt(1, 0.0)
        recordAt(2, 4.0)
        recordAt(3, 8.0)
        assertEquals(8.0, progress().elevationGain.meters)

        session.pause()
        clock.now = start + 60.seconds
        session.resume()
        // Higher after the pause (e.g. driven up a hill): measured from the new segment's first altitude.
        recordAt(61, 50.0)
        recordAt(62, 55.0)

        assertEquals(13.0, progress().elevationGain.meters)
    }

    @Test
    fun attachesTheLatestMotionStateToEachPointUntilItChanges() {
        session.start(Sport.HIKING)
        assertNull(assertNotNull(session.onLocation(fix(1))).point.stationaryByMotion)

        session.onMotion(stationary = true)
        assertEquals(true, assertNotNull(session.onLocation(fix(2))).point.stationaryByMotion)
        assertEquals(true, assertNotNull(session.onLocation(fix(30))).point.stationaryByMotion, "no expiry: only sent on change")

        session.onMotion(stationary = false)
        assertEquals(false, assertNotNull(session.onLocation(fix(31))).point.stationaryByMotion)
    }

    @Test
    fun ignoresInvalidTransitions() {
        assertFalse(session.pause())
        assertFalse(session.resume())
        assertFalse(session.stop())

        assertTrue(session.start(Sport.CYCLING))
        assertFalse(session.start(Sport.RUNNING))
        assertFalse(session.resume())
        assertIs<Recording>(session.state.value)

        assertTrue(session.pause())
        assertFalse(session.pause())
        assertIs<Paused>(session.state.value)
    }

    @Test
    fun restoreOnlyFromIdleOrFinishedAndAlwaysAsPaused() {
        val saved = ActivityProgress.startingAt(Sport.HIKING, start).copy(measurement = TrackMeasurement.continuing(500.0, Duration.ZERO), pointCount = 40, segmentIndex = 2)

        session.start(Sport.CYCLING)
        assertFalse(session.restore(saved))

        session.stop()
        assertTrue(session.restore(saved))
        val paused = assertIs<Paused>(session.state.value)
        assertEquals(saved, paused.progress)

        session.resume()
        assertEquals(3, assertNotNull(session.onLocation(fix(1))).segmentIndex)
        assertEquals(41, progress().pointCount)
    }

    @Test
    fun countsStepsOnlyWhileRecording() {
        session.start(Sport.HIKING)
        assertNull(progress().steps, "no pedometer reading yet")

        session.onSteps(40)
        session.pause()
        session.onSteps(55)
        session.resume()
        session.onSteps(60)

        assertEquals(45, progress().steps)
    }

    @Test
    fun stepsContinueWhenThePedometerRestarts() {
        session.start(Sport.HIKING)
        session.onSteps(100)
        session.onSteps(7)

        assertEquals(107, progress().steps)
    }

    @Test
    fun ignoresStepsForSportsThatDontCountThem() {
        session.start(Sport.CYCLING)
        session.onSteps(40)

        assertNull(progress().steps)
    }

    @Test
    fun stoppedSessionIgnoresFixesAndCanStartAgainFresh() {
        session.start(Sport.CYCLING)
        session.onLocation(fix(1))
        session.stop()

        assertNull(session.onLocation(fix(2)))

        clock.advanceBy(1.minutes)
        assertTrue(session.start(Sport.RUNNING))
        assertEquals(0, progress().pointCount)
        assertEquals(Sport.RUNNING, progress().sport)
        assertEquals(Duration.ZERO, session.state.value.activeTime(clock.now))
    }
}
