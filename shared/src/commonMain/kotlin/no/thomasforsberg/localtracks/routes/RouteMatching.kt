package no.thomasforsberg.localtracks.routes

import no.thomasforsberg.localtracks.recording.Sport
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

// An activity's path for matching: resampled evenly, starting where it really began (home, for an
// automatic recording whose GPS started later).
data class RouteTrack(val activityId: Long, val sport: Sport, val lengthMeters: Double, val line: List<GeoPoint>)

data class TrackMatch(val reversed: Boolean)

// Two activities follow the same route when they start and end in the same places (or swapped: the
// same route walked the other way), and their middles have about the same length and each lies almost
// entirely within a narrow corridor around the other. Checking both ways matters: a short walk lies
// inside a long one's corridor, but not the other way round.
//
// Only the middles are compared because the ends differ between recordings of the same route: the
// straight line from the door before an automatic recording's GPS started, GPS settling after a manual
// start, a recording stopped a little early.
object RouteMatching {
    const val SPACING_METERS = 25.0
    const val CORRIDOR_METERS = 40.0
    const val MIN_COVERAGE = 0.9
    const val END_TRIM_METERS = 200.0
    // The corridor already decides whether two walks take the same path; length only has to catch the
    // same loop walked twice in one go, which lies entirely within the corridor. Recordings of the same
    // path measure up to ~10 % apart (GPS noise adds more length at a higher point rate).
    const val LENGTH_TOLERANCE = 0.2
    const val MIN_LENGTH_TOLERANCE_METERS = 100.0
    const val ENDPOINT_TOLERANCE_METERS = 150.0
    // Shorter activities (a walk to the mailbox) aren't routes.
    const val MIN_ROUTE_METERS = 500.0

    fun lengthsCompatible(a: Double, b: Double): Boolean =
        abs(a - b) <= max(MIN_LENGTH_TOLERANCE_METERS, LENGTH_TOLERANCE * max(a, b))

    fun match(a: RouteTrack, b: RouteTrack): TrackMatch? {
        if (min(a.lengthMeters, b.lengthMeters) < MIN_ROUTE_METERS || a.line.size < 2 || b.line.size < 2) return null
        val plane = Plane(a.line.first().latitude)
        val pa = a.line.map(plane::project)
        val pb = b.line.map(plane::project)
        fun near(p: Xy, q: Xy) = p.distanceTo(q) <= ENDPOINT_TOLERANCE_METERS
        val sameEnds = near(pa.first(), pb.first()) && near(pa.last(), pb.last())
        val swappedEnds = near(pa.first(), pb.last()) && near(pa.last(), pb.first())
        if (!sameEnds && !swappedEnds) return null
        val ma = pa.middle(END_TRIM_METERS)
        val mb = pb.middle(END_TRIM_METERS)
        // A route that never gets far from its ends (a small loop round the block) is compared whole.
        val (ca, cb) = if (ma.size < 2 || mb.size < 2) pa to pb else ma to mb
        if (!lengthsCompatible(ca.length(), cb.length())) return null
        val aAlongB = coverage(ca, cb, CORRIDOR_METERS)
        if (aAlongB.fraction < MIN_COVERAGE) return null
        if (coverage(cb, ca, CORRIDOR_METERS).fraction < MIN_COVERAGE) return null
        return TrackMatch(reversed = aAlongB.isReversed)
    }

    // Whether the route returns to its start, and if so which way round it goes.
    fun shape(line: List<GeoPoint>): RouteShape {
        if (line.size < 3) return RouteShape.NOT_A_LOOP
        val plane = Plane(line.first().latitude)
        val points = line.map(plane::project)
        if (points.first().distanceTo(points.last()) > ENDPOINT_TOLERANCE_METERS) return RouteShape.NOT_A_LOOP
        return if (signedArea(points) < 0) RouteShape.CLOCKWISE_LOOP else RouteShape.ANTICLOCKWISE_LOOP
    }
}

enum class RouteShape { CLOCKWISE_LOOP, ANTICLOCKWISE_LOOP, NOT_A_LOOP }
