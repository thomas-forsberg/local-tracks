package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.ColumnAdapter
import app.cash.sqldelight.EnumColumnAdapter
import app.cash.sqldelight.db.SqlDriver
import no.thomasforsberg.localtracks.db.Activity
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Track_point
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

// Stored as epoch milliseconds; sub-millisecond precision is not needed for tracks.
internal object InstantAdapter : ColumnAdapter<Instant, Long> {
    override fun decode(databaseValue: Long): Instant = Instant.fromEpochMilliseconds(databaseValue)

    override fun encode(value: Instant): Long = value.toEpochMilliseconds()
}
