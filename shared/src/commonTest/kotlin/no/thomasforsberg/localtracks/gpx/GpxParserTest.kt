package no.thomasforsberg.localtracks.gpx

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.time.Instant

class GpxParserTest {
    @Test
    fun readsPointsWithVaryingAttributeOrderQuotesAndOptionalElements() {
        val gpx = """
            <gpx><trk><trkseg>
              <trkpt lat="59.9765" lon="10.729"><ele>184.2</ele><time>2026-09-12T07:00:00Z</time></trkpt>
              <trkpt lon='10.7291' lat='59.9766'>
                <time>2026-09-12T07:00:01Z</time>
              </trkpt>
              <trkpt lat="59.9767" lon="10.7292"/>
            </trkseg></trk></gpx>
        """.trimIndent()

        assertEquals(
            listOf(
                TrackPoint(59.9765, 10.729, 184.2, Instant.parse("2026-09-12T07:00:00Z")),
                TrackPoint(59.9766, 10.7291, null, Instant.parse("2026-09-12T07:00:01Z")),
                TrackPoint(59.9767, 10.7292, null, null),
            ),
            GpxParser.parseTrackPoints(gpx),
        )
    }

    @Test
    fun ignoresElementsThatOnlyStartWithTrkpt() {
        assertEquals(emptyList(), GpxParser.parseTrackPoints("""<trkpts lat="1" lon="2"/>"""))
    }

    @Test
    fun rejectsPointWithoutLongitude() {
        assertFailsWith<IllegalArgumentException> {
            GpxParser.parseTrackPoints("""<trkpt lat="59.9765"/>""")
        }
    }
}
