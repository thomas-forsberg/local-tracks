package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.RecordedPoint
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max

// A point of a route thumbnail, scaled into a unit square: x to the east, y downwards like the screen.
data class PreviewPoint(val x: Double, val y: Double)

// The shape of a route for a small thumbnail: one line per segment, thinned to a few dozen points and
// scaled to fit a unit square without distorting it.
data class RoutePreview(val segments: List<List<PreviewPoint>>) {
    companion object {
        const val DEFAULT_MAX_POINTS = 80
    }
}

// Null when there's nothing to draw (fewer than two points).
fun List<RecordedPoint>.routePreview(maxPoints: Int = RoutePreview.DEFAULT_MAX_POINTS): RoutePreview? {
    if (size < 2) return null
    // Every n-th point, plus each segment's last, so corners stay roughly right and ends meet.
    val step = max(1, (size + maxPoints - 1) / maxPoints)
    val kept = filterIndexed { index, point -> index % step == 0 || index == lastIndex || getOrNull(index + 1)?.segmentIndex != point.segmentIndex }

    // Equirectangular projection: fine at the scale of one activity.
    val midLatitude = (kept.minOf { it.point.latitude } + kept.maxOf { it.point.latitude }) / 2
    val xScale = cos(midLatitude * PI / 180)
    val xs = kept.map { it.point.longitude * xScale }
    val ys = kept.map { -it.point.latitude }
    val minX = xs.min()
    val minY = ys.min()
    val span = max(xs.max() - minX, ys.max() - minY).takeIf { it > 0 } ?: return null
    // Centred in the square along the shorter side.
    val offsetX = (1 - (xs.max() - minX) / span) / 2
    val offsetY = (1 - (ys.max() - minY) / span) / 2

    val segments = kept.indices.groupBy { kept[it].segmentIndex }.values.map { indices ->
        indices.map { PreviewPoint(offsetX + (xs[it] - minX) / span, offsetY + (ys[it] - minY) / span) }
    }
    return RoutePreview(segments.filter { it.size >= 2 }).takeIf { it.segments.isNotEmpty() }
}
