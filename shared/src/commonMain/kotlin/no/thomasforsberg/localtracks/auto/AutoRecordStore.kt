package no.thomasforsberg.localtracks.auto

import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.geo.distanceMeters

// Within this distance of home counts as home. iOS needs at least ~100 m to watch a circle reliably,
// and a smaller circle makes it notice leaving sooner.
const val HOME_RADIUS_METERS = 100.0

data class HomeLocation(val latitude: Double, val longitude: Double) {
    fun distanceMetersTo(latitude: Double, longitude: Double): Double = distanceMeters(this.latitude, this.longitude, latitude, longitude)
}

data class AutoRecordSettings(val enabled: Boolean, val home: HomeLocation?)

// Auto-record's settings and policy state, in the activity database (which stays on the phone).
class AutoRecordStore(private val database: LocalTracksDatabase) {
    private val queries get() = database.autoRecordQueries

    fun settings(): AutoRecordSettings {
        val row = row()
        val home = if (row.home_latitude != null && row.home_longitude != null) HomeLocation(row.home_latitude, row.home_longitude) else null
        return AutoRecordSettings(row.enabled, home)
    }

    fun setEnabled(enabled: Boolean) {
        queries.ensureRow()
        queries.setEnabled(enabled)
    }

    fun setHome(home: HomeLocation?) {
        queries.ensureRow()
        queries.setHome(home?.latitude, home?.longitude)
    }

    fun state(): AutoRecordState = row().let { AutoRecordState(it.phase, it.is_home, it.left_home_at, it.arrived_home_at) }

    fun saveState(state: AutoRecordState) {
        queries.ensureRow()
        queries.saveState(state.phase, state.isHome, state.leftHomeAt, state.arrivedHomeAt)
    }

    private fun row() = queries.transactionWithResult {
        queries.ensureRow()
        queries.get().executeAsOne()
    }
}
