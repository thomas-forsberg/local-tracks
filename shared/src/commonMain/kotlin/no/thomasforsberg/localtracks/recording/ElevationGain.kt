package no.thomasforsberg.localtracks.recording

const val ELEVATION_GAIN_THRESHOLD_METERS = 3.0

// Total climb with hysteresis: a rise only counts once it is at least the threshold above the lowest
// altitude since the last counted rise. Barometer noise and small bumps therefore never add up.
// The last few metres of a climb (less than the threshold) are not counted.
data class ElevationGain(
    val meters: Double,
    // Altitude the next rise is measured from; null until the first altitude of a segment.
    val referenceMeters: Double?,
) {
    fun adding(altitudeMeters: Double, thresholdMeters: Double = ELEVATION_GAIN_THRESHOLD_METERS): ElevationGain {
        val reference = referenceMeters ?: return copy(referenceMeters = altitudeMeters)
        return when {
            altitudeMeters - reference >= thresholdMeters -> ElevationGain(meters + (altitudeMeters - reference), altitudeMeters)
            altitudeMeters < reference -> copy(referenceMeters = altitudeMeters)
            else -> this
        }
    }

    // Barometric altitude is relative to when the sensor started, and climbing while paused
    // (in a car, on a lift) must not count, so each segment measures from its own first altitude.
    fun startingNewSegment(): ElevationGain = copy(referenceMeters = null)

    companion object {
        val NONE = ElevationGain(meters = 0.0, referenceMeters = null)
    }
}
