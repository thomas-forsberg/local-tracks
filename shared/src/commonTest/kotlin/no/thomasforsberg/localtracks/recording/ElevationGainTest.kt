package no.thomasforsberg.localtracks.recording

import kotlin.test.Test
import kotlin.test.assertEquals

class ElevationGainTest {
    private fun gainOver(vararg altitudes: Double): Double =
        altitudes.fold(ElevationGain.NONE) { gain, altitude -> gain.adding(altitude) }.meters

    @Test
    fun countsASteadyClimbInStepsOfAtLeastTheThreshold() {
        // 0 → 10 m in 1 m steps: counted at 3, 6 and 9; the last metre stays below the threshold.
        assertEquals(9.0, gainOver(*(0..10).map(Int::toDouble).toDoubleArray()))
    }

    @Test
    fun ignoresNoiseSmallerThanTheThreshold() {
        assertEquals(0.0, gainOver(100.0, 101.2, 99.4, 100.8, 98.9, 100.6, 99.1, 101.0))
    }

    @Test
    fun descentsLowerTheReferenceSoTheNextClimbCountsInFull() {
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
}
