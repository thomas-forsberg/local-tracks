package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

class ActivityAnalysisTest {
    private val start = Instant.parse("2026-09-12T07:00:00Z")

    // One point per second, heading north at the given speed.
    private fun walk(seconds: Int, speed: Double, gps: (Int) -> Double? = { null }, baro: (Int) -> Double? = { null }) =
        (0..seconds).map { second ->
            RecordedPoint(
                segmentIndex = 0,
                point = TrackPoint(
                    latitude = 59.9 + second * speed / 111_195.08,
                    longitude = 10.7,
                    elevationMeters = gps(second),
                    time = start + second.seconds,
                    horizontalAccuracyMeters = 5.0,
                    speedMetersPerSecond = speed,
                    barometer = baro(second)?.let { BarometerReading(start + second.seconds, it, 100.0) },
                ),
            )
        }

    @Test
    fun splitsAreWholeKilometresByMovingTimeThenTheRest() {
        val analysis = analyze(walk(seconds = 300, speed = 5.0), Sport.RUNNING, maxSamples = 500)

        assertEquals(listOf(1000.0, 500.0), analysis.splits.map { (it.distanceMeters * 100).toLong() / 100.0 })
        assertEquals(200.0, analysis.splits[0].movingTimeSeconds, absoluteTolerance = 0.01)
        assertEquals(100.0, analysis.splits[1].movingTimeSeconds, absoluteTolerance = 0.01)
        assertEquals(5.0, assertNotNull(analysis.splits[0].averageSpeedMetersPerSecond), absoluteTolerance = 0.01)
    }

    @Test
    fun elevationHasTheBarometersShapeAtTheGpsLevel() {
        // GPS altitude: ~120 m but noisy. Barometer: smooth 0 → 30 m climb, relative to the start.
        val points = walk(
            seconds = 300,
            speed = 2.0,
            gps = { 120.0 + it / 10.0 + if (it % 2 == 0) 6.0 else -6.0 },
            baro = { it / 10.0 },
        )

        val profile = analyze(points, Sport.HIKING, maxSamples = 500).profile

        assertEquals(120.0, assertNotNull(profile.first().elevationMeters), absoluteTolerance = 1.0)
        assertEquals(150.0, assertNotNull(profile.last().elevationMeters), absoluteTolerance = 1.0)
        assertEquals(30.0, assertNotNull(analyze(points, Sport.HIKING, 500).splits.first().elevationChangeMeters), absoluteTolerance = 1.0)
    }

    @Test
    fun elevationFallsBackToGpsWithoutABarometer() {
        val profile = analyze(walk(seconds = 10, speed = 2.0, gps = { 80.0 }), Sport.HIKING, maxSamples = 500).profile

        assertEquals(80.0, profile.first().elevationMeters)
    }

    @Test
    fun noAltitudeAtAllMeansNoElevation() {
        val analysis = analyze(walk(seconds = 10, speed = 2.0), Sport.HIKING, maxSamples = 500)

        assertTrue(analysis.profile.all { it.elevationMeters == null })
        assertNull(analysis.splits.first().elevationChangeMeters)
    }

    @Test
    fun profileIsDownsampledButEndsAtTheFullDistance() {
        val analysis = analyze(walk(seconds = 1000, speed = 3.0), Sport.RUNNING, maxSamples = 100)

        assertTrue(analysis.profile.size <= 101)
        assertEquals(3000.0, analysis.profile.last().distanceMeters, absoluteTolerance = 0.1)
    }

    @Test
    fun maxSpeedIgnoresASingleGpsSpike() {
        val points = walk(seconds = 20, speed = 5.0).mapIndexed { index, recorded ->
            if (index == 10) recorded.copy(point = recorded.point.copy(speedMetersPerSecond = 50.0)) else recorded
        }

        assertTrue(assertNotNull(analyze(points, Sport.CYCLING, maxSamples = 500).maxSpeedMetersPerSecond) < 15)
    }

    @Test
    fun noPointsMeansAnEmptyAnalysis() {
        val analysis = analyze(emptyList(), Sport.HIKING, maxSamples = 100)

        assertTrue(analysis.profile.isEmpty())
        assertTrue(analysis.splits.isEmpty())
        assertNull(analysis.maxSpeedMetersPerSecond)
    }
}
