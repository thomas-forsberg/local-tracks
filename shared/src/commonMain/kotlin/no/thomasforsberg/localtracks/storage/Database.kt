package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.ColumnAdapter
import app.cash.sqldelight.EnumColumnAdapter
import app.cash.sqldelight.db.SqlDriver
import no.thomasforsberg.localtracks.db.Activity
import no.thomasforsberg.localtracks.db.Auto_record
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Map_region
import no.thomasforsberg.localtracks.db.Route
import no.thomasforsberg.localtracks.db.Track_point
import no.thomasforsberg.localtracks.recording.elevationGainMeters
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
    auto_recordAdapter = Auto_record.Adapter(
        phaseAdapter = EnumColumnAdapter(),
        left_home_atAdapter = InstantAdapter,
        arrived_home_atAdapter = InstantAdapter,
    ),
    routeAdapter = Route.Adapter(created_atAdapter = InstantAdapter),
    map_regionAdapter = Map_region.Adapter(
        kindAdapter = EnumColumnAdapter(),
        created_atAdapter = InstantAdapter,
        completed_atAdapter = InstantAdapter,
    ),
)

// Schema steps first, then data fixes. Data fixes use today's queries, so they can only run once the
// schema is fully up to date (an AfterVersion callback would run against an intermediate schema).
fun migrateDatabase(driver: SqlDriver, oldVersion: Long, newVersion: Long) {
    LocalTracksDatabase.Schema.migrate(driver, oldVersion, newVersion)
    // Version 2 added moving time and smoothed distance: re-measure older activities from their raw points.
    if (oldVersion < 2) remeasureAllActivities(createDatabase(driver))
    // Version 7 stores where the stretch before GPS started began; earlier ones started at home.
    if (oldVersion < 7) createDatabase(driver).activityQueries.fillLeadInStartFromHome()
    // Version 10 counts each climb in full instead of in threshold-sized steps.
    if (oldVersion < 10) recountElevationGain(createDatabase(driver))
}

// Activities without barometer readings keep their stored climb.
fun recountElevationGain(database: LocalTracksDatabase) {
    val repository = ActivityRepository(database)
    database.activityQueries.allIds().executeAsList().forEach { activity ->
        val meters = repository.trackPoints(activity.id).elevationGainMeters() ?: return@forEach
        database.activityQueries.updateElevationGain(meters, activity.id)
    }
}

fun remeasureAllActivities(database: LocalTracksDatabase) {
    val repository = ActivityRepository(database)
    database.activityQueries.allIds().executeAsList().forEach { (id, sport, leadInMs, leadInMeters) ->
        val measurement = repository.trackPoints(id).measure(sport)
        // The stretch before GPS started has no points; it's counted on top.
        database.activityQueries.updateMeasurement(
            measurement.distanceMeters + (leadInMeters ?: 0.0),
            measurement.movingTime.inWholeMilliseconds + (leadInMs ?: 0),
            id,
        )
    }
}

// Stored as epoch milliseconds; sub-millisecond precision is not needed for tracks.
internal object InstantAdapter : ColumnAdapter<Instant, Long> {
    override fun decode(databaseValue: Long): Instant = Instant.fromEpochMilliseconds(databaseValue)

    override fun encode(value: Instant): Long = value.toEpochMilliseconds()
}
