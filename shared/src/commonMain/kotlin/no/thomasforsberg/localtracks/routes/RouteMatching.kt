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
// same route walked the other way), have about the same length, and each lies almost entirely within
// a narrow corridor around the other. Checking both ways matters: a short walk lies inside a long
// one's corridor, but not the other way round.
object RouteMatching {
    const val SPACING_METERS = 25.0
    const val CORRIDOR_METERS = 40.0
    const val MIN_COVERAGE = 0.9
    // The same loop measures within 1–2 % from walk to walk; gaps (the app killed) and the backfilled
    // start of automatic recordings add a little more. The floor keeps short loops from being held to
    // a few metres.
    const val LENGTH_TOLERANCE = 0.05
    const val MIN_LENGTH_TOLERANCE_METERS = 100.0
    const val ENDPOINT_TOLERANCE_METERS = 150.0
    // Shorter activities (a walk to the mailbox) aren't routes.
    const val MIN_ROUTE_METERS = 500.0

    // Also what catches the same loop walked twice in one go: that lies entirely within the corridor.
    fun lengthsCompatible(a: Double, b: Double): Boolean =
        min(a, b) >= MIN_ROUTE_METERS && abs(a - b) <= max(MIN_LENGTH_TOLERANCE_METERS, LENGTH_TOLERANCE * max(a, b))

    fun match(a: RouteTrack, b: RouteTrack): TrackMatch? {
        if (!lengthsCompatible(a.lengthMeters, b.lengthMeters) || a.line.size < 2 || b.line.size < 2) return null
        val plane = Plane(a.line.first().latitude)
        val pa = a.line.map(plane::project)
        val pb = b.line.map(plane::project)
        fun near(p: Xy, q: Xy) = p.distanceTo(q) <= ENDPOINT_TOLERANCE_METERS
        val sameEnds = near(pa.first(), pb.first()) && near(pa.last(), pb.last())
        val swappedEnds = near(pa.first(), pb.last()) && near(pa.last(), pb.first())
        if (!sameEnds && !swappedEnds) return null
        val aAlongB = coverage(pa, pb, CORRIDOR_METERS)
        if (aAlongB.fraction < MIN_COVERAGE) return null
        if (coverage(pb, pa, CORRIDOR_METERS).fraction < MIN_COVERAGE) return null
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
