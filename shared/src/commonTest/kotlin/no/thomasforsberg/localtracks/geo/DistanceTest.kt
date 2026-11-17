package no.thomasforsberg.localtracks.geo

import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.math.PI
import kotlin.test.Test
import kotlin.test.assertEquals

class DistanceTest {
    private fun point(latitude: Double, longitude: Double) = TrackPoint(latitude, longitude, null, null)

    @Test
    fun oneDegreeAlongTheEquatorIsOneThreeHundredSixtiethOfTheCircumference() {
        assertEquals(
            expected = PI * EARTH_MEAN_RADIUS_METERS / 180,
            actual = distanceMeters(point(0.0, 0.0), point(0.0, 1.0)),
            absoluteTolerance = 1e-6,
        )
    }

    @Test
    fun samePointIsZero() {
        assertEquals(0.0, distanceMeters(point(59.9765, 10.729), point(59.9765, 10.729)))
    }

    @Test
    fun isSymmetric() {
        val oslo = point(59.9111, 10.7528)
        val bergen = point(60.3913, 5.3221)
        assertEquals(distanceMeters(oslo, bergen), distanceMeters(bergen, oslo), absoluteTolerance = 1e-9)
    }

    @Test
    fun handlesAntipodalPoints() {
        assertEquals(
            expected = PI * EARTH_MEAN_RADIUS_METERS,
            actual = distanceMeters(point(0.0, 0.0), point(0.0, 180.0)),
            absoluteTolerance = 1e-6,
        )
    }
}
