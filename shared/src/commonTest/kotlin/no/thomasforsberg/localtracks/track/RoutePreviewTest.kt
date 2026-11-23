package no.thomasforsberg.localtracks.track

import no.thomasforsberg.localtracks.recording.RecordedPoint
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class RoutePreviewTest {
    private fun point(latitude: Double, longitude: Double, segment: Int = 0) =
        RecordedPoint(segment, TrackPoint(latitude, longitude, elevationMeters = null, time = null))

    @Test
    fun fitsTheRouteInAUnitSquareKeepingItsShape() {
        // 0.02° east at 60° N is about as long as 0.01° north.
        val preview = listOf(point(60.00, 10.00), point(60.00, 10.02), point(60.01, 10.02)).routePreview()!!
        val line = preview.segments.single()

        assertEquals(0.0, line[0].x, 0.01)
        assertEquals(1.0, line[0].y, 0.01, "south is at the bottom")
        assertEquals(1.0, line[1].x, 0.01)
        assertEquals(0.0, line[2].y, 0.01)
    }

    @Test
    fun aNarrowRouteIsCentred() {
        val line = listOf(point(60.00, 10.00), point(60.01, 10.00)).routePreview()!!.segments.single()

        assertEquals(0.5, line[0].x, 0.001)
        assertEquals(0.5, line[1].x, 0.001)
    }

    @Test
    fun keepsSegmentsApartAndThinsLongRoutes() {
        val first = (0 until 500).map { point(60.0 + it * 0.0001, 10.0) }
        val second = (0 until 500).map { point(60.05, 10.0 + it * 0.0001, segment = 1) }

        val preview = (first + second).routePreview(maxPoints = 50)!!

        assertEquals(2, preview.segments.size)
        assertTrue(preview.segments.sumOf { it.size } <= 60)
        assertTrue(preview.segments.flatten().all { it.x in 0.0..1.0 && it.y in 0.0..1.0 })
    }

    @Test
    fun theStretchBeforeGpsRunsFromItsStartToTheFirstPointAndIsFittedToo() {
        val preview = listOf(point(60.00, 10.00), point(60.01, 10.00)).routePreview(leadInStart = 59.99 to 10.00)!!
        val leadIn = preview.leadIn!!

        assertEquals(1.0, leadIn[0].y, 0.01, "the start, furthest south, at the bottom")
        assertEquals(preview.segments[0][0], leadIn[1])
        assertTrue(preview.segments.flatten().all { it.y in 0.0..0.51 }, "the route now takes the upper half")
    }

    @Test
    fun nothingToDrawForASinglePointOrStandingStill() {
        assertNull(listOf(point(60.0, 10.0)).routePreview())
        assertNull(listOf(point(60.0, 10.0), point(60.0, 10.0)).routePreview())
    }
}
