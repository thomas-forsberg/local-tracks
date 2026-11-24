package no.thomasforsberg.localtracks.recording

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.time.Instant

class ElevationGainTest {
    private fun gainOver(vararg altitudes: Double): Double =
        altitudes.fold(ElevationGain.NONE) { gain, altitude -> gain.adding(altitude) }.meters

    @Test
    fun countsASteadyClimbInFull() {
        assertEquals(10.0, gainOver(*(0..10).map(Int::toDouble).toDoubleArray()))
    }

    @Test
    fun countsClimbsThatAreNotMultiplesOfTheThreshold() {
        assertEquals(7.4, gainOver(0.0, 1.2, 2.5, 3.1, 4.8, 6.0, 7.4), absoluteTolerance = 1e-9)
    }

    @Test
    fun ignoresNoiseSmallerThanTheThreshold() {
        assertEquals(0.0, gainOver(100.0, 101.2, 99.4, 100.8, 98.9, 100.6, 99.1, 101.0))
    }

    @Test
    fun noiseOnAFlatStretchMidClimbOnlyCountsAboveTheHighestPoint() {
        // Up 10, flat with ±1 m noise, up 10 more.
        assertEquals(20.0, gainOver(0.0, 5.0, 10.0, 9.2, 10.6, 9.4, 10.8, 9.0, 10.5, 15.0, 20.0), absoluteTolerance = 1e-9)
    }

    @Test
    fun aDipSmallerThanTheThresholdDoesNotEndTheClimb() {
        // Up 10, down 2, back up: the 2 m regained isn't counted again.
        assertEquals(15.0, gainOver(0.0, 10.0, 8.0, 15.0))
    }

    @Test
    fun descentsEndTheClimbSoTheNextOneCountsFromTheBottom() {
        // Up 10, down 10, up 10.
        assertEquals(20.0, gainOver(0.0, 10.0, 5.0, 0.0, 10.0))
    }

    @Test
    fun countsLargeJumpsAtOnce() {
        assertEquals(25.0, gainOver(200.0, 225.0))
    }

    @Test
    fun newSegmentStartsFromItsOwnFirstAltitude() {
        val beforePause = ElevationGain.NONE.adding(0.0).adding(50.0)

        // After resuming, the barometer reads 0 again (or we drove up a hill while paused).
        val afterResume = beforePause.startingNewSegment().adding(120.0).adding(124.0)

        assertEquals(54.0, afterResume.meters)
    }

    @Test
    fun recordedPointsAreCountedPerSegment() {
        fun point(segment: Int, altitude: Double?) = RecordedPoint(
            segment,
            TrackPoint(59.9, 10.7, null, Instant.fromEpochSeconds(0), barometer = altitude?.let { BarometerReading(Instant.fromEpochSeconds(0), it, 100.0) }),
        )
        val points = listOf(point(0, 0.0), point(0, null), point(0, 7.5), point(1, 0.0), point(1, 4.2))

        assertEquals(11.7, points.elevationGainMeters()!!, absoluteTolerance = 1e-9)
        assertNull(listOf(point(0, null)).elevationGainMeters(), "no barometer")
    }
}
