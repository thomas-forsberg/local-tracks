package no.thomasforsberg.localtracks.gpx

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.time.Instant

// Minimal track-point reader for fixtures and simulation, not a full XML parser
// (no namespaced elements, CDATA or comments). Replaced by a real parser in phase 5.
object GpxParser {
    private val trackPoint = Regex("""<trkpt\b([^>]*?)(?:/>|>([\s\S]*?)</trkpt>)""")
    private val latitude = attribute("lat")
    private val longitude = attribute("lon")
    private val elevation = element("ele")
    private val time = element("time")

    fun parseTrackPoints(gpx: String): List<TrackPoint> =
        trackPoint.findAll(gpx).map { match ->
            val attributes = match.groupValues[1]
            val body = match.groupValues[2]
            TrackPoint(
                latitude = latitude.required(attributes, "lat").toDouble(),
                longitude = longitude.required(attributes, "lon").toDouble(),
                elevationMeters = elevation.optional(body)?.toDouble(),
                time = time.optional(body)?.let(Instant::parse),
            )
        }.toList()

    private fun attribute(name: String) = Regex("""\b$name\s*=\s*["']([^"']*)["']""")

    private fun element(name: String) = Regex("""<$name>\s*([^<]*?)\s*</$name>""")

    private fun Regex.optional(input: String): String? = find(input)?.groupValues?.get(1)

    private fun Regex.required(input: String, name: String): String =
        requireNotNull(optional(input)) { "trkpt without $name attribute: <trkpt$input>" }
}
