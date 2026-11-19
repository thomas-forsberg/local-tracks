package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.geo.distanceMeters
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class TrackMeasurementTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")
    private val metersPerDegreeLatitude = 111_195.08

    // One point per second, `north` metres north and `east` metres east of the origin.
    private fun point(second: Int, north: Double, east: Double = 0.0, speed: Double? = null, accuracy: Double = 5.0) = TrackPoint(
        latitude = 59.9 + north / metersPerDegreeLatitude,
        longitude = 10.7 + east / (metersPerDegreeLatitude * kotlin.math.cos(59.9 * kotlin.math.PI / 180)),
        elevationMeters = null,
        time = start + second.seconds,
        horizontalAccuracyMeters = accuracy,
        speedMetersPerSecond = speed,
    )

    private fun measure(points: List<TrackPoint>, sport: Sport = Sport.HIKING) =
        points.fold(TrackMeasurement.EMPTY) { measurement, point -> measurement.adding(point, sport) }

    @Test
    fun aStraightLineIsMeasuredExactlyAtEveryPoint() {
        val line = (0..10).map { point(it, north = it * 5.0) }

        (1..line.size).forEach { count ->
            assertEquals((count - 1) * 5.0, measure(line.take(count)).distanceMeters, absoluteTolerance = 0.01)
        }
    }

    @Test
    fun zigZagNoiseIsFlattened() {
        // Walking 50 m north while GPS wobbles 3 m east and west.
        val wobbly = (0..10).map { point(it, north = it * 5.0, east = if (it % 2 == 0) 3.0 else -3.0) }
        val raw = wobbly.zipWithNext { a, b -> distanceMeters(a, b) }.sum()

        val smoothed = measure(wobbly).distanceMeters

        assertEquals(78.10, raw, absoluteTolerance = 0.01)
        // A 3-point average shrinks the ±3 m wobble to ±1 m.
        assertEquals(53.85, smoothed, absoluteTolerance = 0.01)
    }

    @Test
    fun inaccuratePointsPullLess() {
        val wobble = { accuracy: Double -> (0..10).map { point(it, north = it * 5.0, east = if (it % 2 == 0) 0.0 else 6.0, accuracy = if (it % 2 == 0) 5.0 else accuracy) } }

        assertTrue(measure(wobble(30.0)).distanceMeters < measure(wobble(5.0)).distanceMeters)
    }

    @Test
    fun standingStillAddsNoDistanceOrMovingTime() {
        val drifting = (0..10).map { point(it, north = if (it % 2 == 0) 0.0 else 4.0, speed = 0.1) }

        val measurement = measure(drifting)

        assertEquals(0.0, measurement.distanceMeters)
        assertEquals(0.seconds, measurement.movingTime)
        assertFalse(measurement.isMoving)
    }

    @Test
    fun movingTimeUsesTheSportsThreshold() {
        // 0.8 m/s: moving for a hiker, standing still for a cyclist.
        val slow = (0..10).map { point(it, north = it * 0.8, speed = 0.8) }

        assertEquals(10.seconds, measure(slow, Sport.HIKING).movingTime)
        assertEquals(0.seconds, measure(slow, Sport.CYCLING).movingTime)
    }

    @Test
    fun storedPointsAreMeasuredPerSegmentWithoutBridgingTheGap() {
        val first = (0..4).map { RecordedPoint(0, point(it, north = it * 5.0)) }
        val second = (0..4).map { RecordedPoint(1, point(60 + it, north = 1000 + it * 5.0)) }

        val measurement = (first + second).measure(Sport.HIKING)

        assertEquals(40.0, measurement.distanceMeters, absoluteTolerance = 0.01)
        assertEquals(8.seconds, measurement.movingTime)
    }

    @Test
    fun motionSensorsSayingStationaryVetoGpsSpeed() {
        // GPS drift reports 2 m/s while the phone lies still; the accelerometer knows better.
        val drifting = (0..10).map { point(it, north = if (it % 2 == 0) 0.0 else 4.0, speed = 2.0).copy(stationaryByMotion = true) }

        val measurement = measure(drifting)

        assertEquals(0.0, measurement.distanceMeters)
        assertEquals(0.seconds, measurement.movingTime)
    }

    @Test
    fun motionSensorsSayingMovingDontOverrideAStandstillBySpeed() {
        val slow = (0..10).map { point(it, north = it * 0.1, speed = 0.1).copy(stationaryByMotion = false) }

        assertEquals(0.seconds, measure(slow).movingTime)
    }
}
