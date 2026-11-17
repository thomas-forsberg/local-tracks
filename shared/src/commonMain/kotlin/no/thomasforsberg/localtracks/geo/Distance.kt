package no.thomasforsberg.localtracks.geo

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.math.PI
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

const val EARTH_MEAN_RADIUS_METERS = 6_371_008.8

// Haversine on a sphere: within ~0.5 % of the ellipsoidal distance, far below GPS noise.
fun distanceMeters(from: TrackPoint, to: TrackPoint): Double {
    val fromLatitude = from.latitude.toRadians()
    val toLatitude = to.latitude.toRadians()
    val h = sin((toLatitude - fromLatitude) / 2).pow(2) +
        cos(fromLatitude) * cos(toLatitude) * sin((to.longitude - from.longitude).toRadians() / 2).pow(2)
    return 2 * EARTH_MEAN_RADIUS_METERS * asin(sqrt(h.coerceAtMost(1.0)))
}

private fun Double.toRadians() = this * PI / 180
