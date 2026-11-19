package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.ColumnAdapter
import app.cash.sqldelight.EnumColumnAdapter
import app.cash.sqldelight.db.AfterVersion
import app.cash.sqldelight.db.SqlDriver
import no.thomasforsberg.localtracks.db.Activity
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Track_point
import no.thomasforsberg.localtracks.track.measure
import kotlin.time.Instant

fun createDatabase(driver: SqlDriver): LocalTracksDatabase = LocalTracksDatabase(
    driver = driver,
    activityAdapter = Activity.Adapter(
        sportAdapter = EnumColumnAdapter(),
        started_atAdapter = InstantAdapter,
        finished_atAdapter = InstantAdapter,
    ),
    track_pointAdapter = Track_point.Adapter(
        timeAdapter = InstantAdapter,
        baro_timeAdapter = InstantAdapter,
    ),
)

// Run after the matching schema migration. Version 2 added moving time and smoothed distance, so
// existing activities are re-measured from their raw points, the same way new recordings are.
val migrationCallbacks: Array<AfterVersion> = arrayOf(
    AfterVersion(1) { driver -> remeasureAllActivities(createDatabase(driver)) },
)

fun remeasureAllActivities(database: LocalTracksDatabase) {
    val repository = ActivityRepository(database)
    database.activityQueries.allIds().executeAsList().forEach { (id, sport) ->
        val measurement = repository.trackPoints(id).measure(sport)
        database.activityQueries.updateMeasurement(measurement.distanceMeters, measurement.movingTime.inWholeMilliseconds, id)
    }
}

// Stored as epoch milliseconds; sub-millisecond precision is not needed for tracks.
internal object InstantAdapter : ColumnAdapter<Instant, Long> {
    override fun decode(databaseValue: Long): Instant = Instant.fromEpochMilliseconds(databaseValue)

    override fun encode(value: Instant): Long = value.toEpochMilliseconds()
}
