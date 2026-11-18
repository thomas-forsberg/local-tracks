package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Track_point
import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.track.TrackPoint
import kotlin.coroutines.CoroutineContext
import kotlin.native.HiddenFromObjC
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Instant

data class ActivitySummary(
    val id: Long,
    val sport: Sport,
    val startedAt: Instant,
    val finishedAt: Instant?,
    val totals: ActivityTotals,
)

data class ActivityTotals(
    @property:HiddenFromObjC val activeTime: Duration,
    val distanceMeters: Double,
    val pointCount: Int,
    val elevationGainMeters: Double = 0.0,
) {
    // Kotlin's Duration reaches Swift as its raw internal encoding, so Swift gets plain seconds instead.
    val activeTimeSeconds: Double get() = activeTime.toDouble(DurationUnit.SECONDS)
}

class ActivityRepository(
    private val database: LocalTracksDatabase,
    private val queryContext: CoroutineContext = Dispatchers.Default,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(database: LocalTracksDatabase) : this(database, Dispatchers.Default)

    private val activities get() = database.activityQueries
    private val trackPoints get() = database.trackPointQueries

    fun startActivity(sport: Sport, startedAt: Instant): Long = database.transactionWithResult {
        activities.insert(sport, startedAt)
        activities.lastInsertedId().executeAsOne()
    }

    // Points and totals are written in one transaction, so they always agree after a crash.
    fun appendPoints(activityId: Long, firstSeq: Int, points: List<RecordedPoint>, totals: ActivityTotals) {
        database.transaction {
            points.forEachIndexed { index, recorded -> trackPoints.insert(recorded.toRow(activityId, firstSeq + index)) }
            activities.updateTotals(
                totals.activeTime.inWholeMilliseconds,
                totals.distanceMeters,
                totals.pointCount.toLong(),
                totals.elevationGainMeters,
                activityId,
            )
        }
    }

    fun finishActivity(activityId: Long, finishedAt: Instant, totals: ActivityTotals) {
        activities.finish(
            finishedAt,
            totals.activeTime.inWholeMilliseconds,
            totals.distanceMeters,
            totals.pointCount.toLong(),
            totals.elevationGainMeters,
            activityId,
        )
    }

    fun activity(id: Long): ActivitySummary? = activities.byId(id, ::activitySummary).executeAsOneOrNull()

    fun latestUnfinishedActivity(): ActivitySummary? = activities.latestUnfinished(::activitySummary).executeAsOneOrNull()

    // Finished activities, newest first; emits again whenever the table changes.
    fun finishedActivities(): Flow<List<ActivitySummary>> =
        activities.finished(::activitySummary).asFlow().mapToList(queryContext)

    fun trackPoints(activityId: Long): List<RecordedPoint> =
        trackPoints.forActivity(activityId).executeAsList().map { it.toRecordedPoint() }

    fun lastTrackPoint(activityId: Long): RecordedPoint? =
        trackPoints.lastForActivity(activityId).executeAsOneOrNull()?.toRecordedPoint()

    fun delete(activityId: Long) {
        database.transaction {
            trackPoints.deleteForActivity(activityId)
            activities.delete(activityId)
        }
    }
}

// Row mapper shared by all activity queries.
private fun activitySummary(
    id: Long,
    sport: Sport,
    startedAt: Instant,
    finishedAt: Instant?,
    activeTimeMs: Long,
    distanceMeters: Double,
    pointCount: Long,
    elevationGainMeters: Double,
) = ActivitySummary(
    id,
    sport,
    startedAt,
    finishedAt,
    ActivityTotals(activeTimeMs.milliseconds, distanceMeters, pointCount.toInt(), elevationGainMeters),
)

private fun RecordedPoint.toRow(activityId: Long, seq: Int) = Track_point(
    activity_id = activityId,
    seq = seq.toLong(),
    segment = segmentIndex.toLong(),
    time = requireNotNull(point.time) { "Recorded points always have a time" },
    latitude = point.latitude,
    longitude = point.longitude,
    elevation_meters = point.elevationMeters,
    horizontal_accuracy_meters = point.horizontalAccuracyMeters,
    speed_mps = point.speedMetersPerSecond,
    baro_time = point.barometer?.time,
    baro_relative_altitude_meters = point.barometer?.relativeAltitudeMeters,
    baro_pressure_kpa = point.barometer?.pressureKilopascals,
)

private fun Track_point.toRecordedPoint() = RecordedPoint(
    segmentIndex = segment.toInt(),
    point = TrackPoint(
        latitude = latitude,
        longitude = longitude,
        elevationMeters = elevation_meters,
        time = time,
        horizontalAccuracyMeters = horizontal_accuracy_meters,
        speedMetersPerSecond = speed_mps,
        barometer = baro_time?.let { time ->
            BarometerReading(
                time = time,
                relativeAltitudeMeters = requireNotNull(baro_relative_altitude_meters),
                pressureKilopascals = requireNotNull(baro_pressure_kpa),
            )
        },
    ),
)
