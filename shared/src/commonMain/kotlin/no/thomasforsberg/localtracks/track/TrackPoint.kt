package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.BarometerReading
import kotlin.time.Instant

data class TrackPoint(
    val latitude: Double,
    val longitude: Double,
    // GPS altitude; barometric data, when recorded, is kept raw in barometer.
    val elevationMeters: Double?,
    val time: Instant?,
    val horizontalAccuracyMeters: Double? = null,
    val speedMetersPerSecond: Double? = null,
    val barometer: BarometerReading? = null,
)
