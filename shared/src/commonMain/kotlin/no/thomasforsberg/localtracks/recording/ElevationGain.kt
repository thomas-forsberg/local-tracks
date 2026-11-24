package no.thomasforsberg.localtracks.recording

const val ELEVATION_GAIN_THRESHOLD_METERS = 3.0

// Total climb with hysteresis. A climb starts once the altitude is the threshold above the lowest point,
// and then counts in full: every metre above its highest point so far, until the altitude drops the
// threshold below that point. Barometer noise smaller than the threshold therefore never adds up.
data class ElevationGain(
    val meters: Double,
    // Lowest altitude since the last climb; null until the first altitude of a segment.
    val lowMeters: Double?,
    // Highest altitude of the climb in progress; null when not climbing.
    val peakMeters: Double? = null,
) {
    fun adding(altitudeMeters: Double, thresholdMeters: Double = ELEVATION_GAIN_THRESHOLD_METERS): ElevationGain {
        val low = lowMeters ?: return copy(lowMeters = altitudeMeters)
        val peak = peakMeters
        return when {
            peak == null && altitudeMeters - low >= thresholdMeters -> copy(meters = meters + altitudeMeters - low, peakMeters = altitudeMeters)
            peak == null -> if (altitudeMeters < low) copy(lowMeters = altitudeMeters) else this
            altitudeMeters > peak -> copy(meters = meters + altitudeMeters - peak, peakMeters = altitudeMeters)
            peak - altitudeMeters >= thresholdMeters -> copy(lowMeters = altitudeMeters, peakMeters = null)
            else -> this
        }
    }

    // Barometric altitude is relative to when the sensor started, and climbing while paused
    // (in a car, on a lift) must not count, so each segment measures from its own first altitude.
    fun startingNewSegment(): ElevationGain = copy(lowMeters = null, peakMeters = null)

    companion object {
        val NONE = ElevationGain(meters = 0.0, lowMeters = null)
    }
}

// The climb over recorded points, as counted while recording; null without barometer readings.
fun List<RecordedPoint>.elevationGainMeters(): Double? {
    if (none { it.point.barometer != null }) return null
    return groupBy { it.segmentIndex }.values.fold(0.0) { total, segment ->
        total + segment.mapNotNull { it.point.barometer?.relativeAltitudeMeters }
            .fold(ElevationGain.NONE) { gain, altitude -> gain.adding(altitude) }.meters
    }
}
