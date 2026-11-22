package no.thomasforsberg.localtracks.maps

import kotlin.math.PI
import kotlin.math.atan
import kotlin.math.floor
import kotlin.math.ln
import kotlin.math.sinh
import kotlin.math.tan

// A map tile in the XYZ scheme used by web maps: x grows east, y grows south, 2^zoom tiles per side.
data class TileId(val zoom: Int, val x: Int, val y: Int)

data class BoundingBox(val west: Double, val south: Double, val east: Double, val north: Double)

// Web Mercator (EPSG:3857), the projection of Kartverket's "webmercator" tiles and of MapLibre.
object WebMercator {
    // Beyond this latitude Web Mercator is undefined; tile 0 and 2^z-1 reach it.
    const val MAX_LATITUDE = 85.05112878

    fun tileX(longitude: Double, zoom: Int): Double = (longitude + 180) / 360 * tilesPerSide(zoom)

    fun tileY(latitude: Double, zoom: Int): Double {
        val radians = latitude.coerceIn(-MAX_LATITUDE, MAX_LATITUDE) * PI / 180
        return (1 - ln(tan(radians) + 1 / kotlin.math.cos(radians)) / PI) / 2 * tilesPerSide(zoom)
    }

    fun longitude(tileX: Int, zoom: Int): Double = tileX.toDouble() / tilesPerSide(zoom) * 360 - 180

    fun latitude(tileY: Int, zoom: Int): Double = atan(sinh(PI * (1 - 2 * tileY.toDouble() / tilesPerSide(zoom)))) * 180 / PI

    fun tilesPerSide(zoom: Int): Int = 1 shl zoom
}

// A rectangle of whole tiles at one zoom level (inclusive). Working in tiles rather than coordinates
// keeps every zoom level exactly aligned, with no floating-point edge cases.
data class TileArea(val zoom: Int, val minX: Int, val minY: Int, val maxX: Int, val maxY: Int) {
    init {
        require(minX <= maxX && minY <= maxY) { "Empty tile area" }
    }

    val tileCount: Long get() = (maxX - minX + 1).toLong() * (maxY - minY + 1)

    // The same area at another zoom: the children of every tile when zooming in, their parents when zooming out.
    fun at(zoom: Int): TileArea = when {
        zoom >= this.zoom -> {
            val shift = zoom - this.zoom
            TileArea(zoom, minX shl shift, minY shl shift, ((maxX + 1) shl shift) - 1, ((maxY + 1) shl shift) - 1)
        }
        else -> {
            val shift = this.zoom - zoom
            TileArea(zoom, minX shr shift, minY shr shift, maxX shr shift, maxY shr shift)
        }
    }

    fun tiles(): Sequence<TileId> = (minY..maxY).asSequence().flatMap { y -> (minX..maxX).asSequence().map { x -> TileId(zoom, x, y) } }

    val bounds: BoundingBox
        get() = BoundingBox(
            west = WebMercator.longitude(minX, zoom),
            south = WebMercator.latitude(maxY + 1, zoom),
            east = WebMercator.longitude(maxX + 1, zoom),
            north = WebMercator.latitude(minY, zoom),
        )

    companion object {
        // The smallest area whose tiles cover the box.
        fun covering(box: BoundingBox, zoom: Int): TileArea {
            val last = WebMercator.tilesPerSide(zoom) - 1
            fun clamp(value: Double) = floor(value).toInt().coerceIn(0, last)
            return TileArea(
                zoom = zoom,
                minX = clamp(WebMercator.tileX(box.west, zoom)),
                minY = clamp(WebMercator.tileY(box.north, zoom)),
                maxX = clamp(WebMercator.tileX(box.east, zoom)),
                maxY = clamp(WebMercator.tileY(box.south, zoom)),
            )
        }
    }
}
