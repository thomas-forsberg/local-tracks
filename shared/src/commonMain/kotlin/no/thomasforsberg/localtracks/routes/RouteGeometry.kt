package no.thomasforsberg.localtracks.routes

import no.thomasforsberg.localtracks.geo.distanceMeters
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sqrt

data class GeoPoint(val latitude: Double, val longitude: Double)

// A track flattened onto a local plane in metres around a reference latitude: accurate enough for
// comparing two walks in the same area, and much cheaper than great-circle maths for every pair.
internal class Plane(referenceLatitude: Double) {
    private val metersPerDegreeLatitude = 111_195.0
    private val metersPerDegreeLongitude = metersPerDegreeLatitude * cos(referenceLatitude * PI / 180)

    fun project(point: GeoPoint) = Xy(point.longitude * metersPerDegreeLongitude, point.latitude * metersPerDegreeLatitude)
}

internal data class Xy(val x: Double, val y: Double)

fun List<GeoPoint>.lengthMeters(): Double =
    zipWithNext().sumOf { (a, b) -> distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude) }

// Points every `spacing` metres along the line, so two tracks recorded at different speeds or rates
// are compared on equal terms.
fun List<GeoPoint>.resampled(spacingMeters: Double): List<GeoPoint> {
    if (size < 2) return this
    val result = mutableListOf(first())
    var untilNext = spacingMeters
    for ((a, b) in zipWithNext()) {
        val step = distanceMeters(a.latitude, a.longitude, b.latitude, b.longitude)
        if (step == 0.0) continue
        var at = 0.0
        while (at + untilNext <= step) {
            at += untilNext
            val f = at / step
            result += GeoPoint(a.latitude + (b.latitude - a.latitude) * f, a.longitude + (b.longitude - a.longitude) * f)
            untilNext = spacingMeters
        }
        untilNext -= step - at
    }
    if (result.last() != last()) result += last()
    return result
}

// Share of `points` lying within `corridor` metres of `line`, and for each point the position along
// `line` (segment index) it is nearest to, for telling the direction.
internal fun coverage(points: List<Xy>, line: List<Xy>, corridorMeters: Double): Coverage {
    var inside = 0
    val nearest = IntArray(points.size)
    points.forEachIndexed { i, p ->
        var best = Double.MAX_VALUE
        var bestSegment = 0
        for (s in 0 until line.size - 1) {
            val d = distanceToSegment(p, line[s], line[s + 1])
            if (d < best) {
                best = d
                bestSegment = s
            }
        }
        if (best <= corridorMeters) inside++
        nearest[i] = bestSegment
    }
    return Coverage(if (points.isEmpty()) 0.0 else inside.toDouble() / points.size, nearest)
}

internal class Coverage(val fraction: Double, val nearestSegment: IntArray) {
    // Whether walking along the points moves backwards along the line: more steps go down than up.
    val isReversed: Boolean
        get() {
            var forward = 0
            var backward = 0
            for (i in 1 until nearestSegment.size) {
                val d = nearestSegment[i] - nearestSegment[i - 1]
                if (d > 0) forward++ else if (d < 0) backward++
            }
            return backward > forward
        }
}

private fun distanceToSegment(p: Xy, a: Xy, b: Xy): Double {
    val dx = b.x - a.x
    val dy = b.y - a.y
    val lengthSquared = dx * dx + dy * dy
    if (lengthSquared == 0.0) return hypot(p.x - a.x, p.y - a.y)
    val t = (((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared).coerceIn(0.0, 1.0)
    return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
}

// Positive for an anticlockwise loop on the map (east right, north up), negative for clockwise.
internal fun signedArea(points: List<Xy>): Double =
    points.indices.sumOf { i ->
        val a = points[i]
        val b = points[(i + 1) % points.size]
        a.x * b.y - b.x * a.y
    } / 2

// The part of the line from where it first gets further than `trim` metres from both its ends, to
// where it last is; empty if it never does.
internal fun List<Xy>.middle(trimMeters: Double): List<Xy> {
    if (size < 2) return emptyList()
    val start = first()
    val end = last()
    fun away(p: Xy) = p.distanceTo(start) > trimMeters && p.distanceTo(end) > trimMeters
    val from = indexOfFirst(::away)
    val to = indexOfLast(::away)
    return if (from < 0 || to <= from) emptyList() else subList(from, to + 1)
}

internal fun List<Xy>.length(): Double = zipWithNext().sumOf { (a, b) -> a.distanceTo(b) }

internal fun Xy.distanceTo(other: Xy) = sqrt((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y))
