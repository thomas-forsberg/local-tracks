package no.thomasforsberg.localtracks.recording

import kotlin.time.Instant

// Raw platform location update. Negative accuracy means invalid, as on iOS.
data class LocationFix(
    val time: Instant,
    val latitude: Double,
    val longitude: Double,
    val horizontalAccuracyMeters: Double,
    val altitudeMeters: Double?,
    val speedMetersPerSecond: Double?,
)

// Raw barometer sample. Relative altitude is measured from when the platform started barometer updates.
data class BarometerReading(
    val time: Instant,
    val relativeAltitudeMeters: Double,
    val pressureKilopascals: Double,
)
