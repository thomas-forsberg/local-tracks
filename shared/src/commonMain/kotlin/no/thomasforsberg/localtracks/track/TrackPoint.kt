package no.thomasforsberg.localtracks.track

import kotlin.time.Instant

data class TrackPoint(
    val latitude: Double,
    val longitude: Double,
    val elevationMeters: Double?,
    val time: Instant?,
)
