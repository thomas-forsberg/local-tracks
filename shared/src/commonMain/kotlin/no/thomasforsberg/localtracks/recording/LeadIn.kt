package no.thomasforsberg.localtracks.recording

import kotlin.native.HiddenFromObjC
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Instant

// When an automatic recording starts, the user has already walked a little: iOS notices leaving the
// home circle late, and recording waits until it's clear this isn't the walk to the car.
// distanceMeters and steps come from the pedometer's history for that stretch; the start is home.
data class Departure(
    val at: Instant,
    val distanceMeters: Double,
    val steps: Int?,
    val startLatitude: Double?,
    val startLongitude: Double?,
)

// The stretch before GPS recording started, as stored: counted in the totals, with no GPS points.
// Maps draw it as a dashed line from where it started (home) to the first recorded point.
data class LeadIn(
    @property:HiddenFromObjC val duration: Duration,
    val distanceMeters: Double,
    val steps: Int?,
    val startLatitude: Double? = null,
    val startLongitude: Double? = null,
) {
    // Kotlin's Duration reaches Swift as its raw internal encoding, so Swift gets plain seconds instead.
    val durationSeconds: Double get() = duration.toDouble(DurationUnit.SECONDS)
}
