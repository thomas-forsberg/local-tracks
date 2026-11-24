package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.coroutines.asFlow
import app.cash.sqldelight.coroutines.mapToList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.db.Track_point
import no.thomasforsberg.localtracks.recording.BarometerReading
import no.thomasforsberg.localtracks.recording.LeadIn
import no.thomasforsberg.localtracks.recording.RecordedPoint
import no.thomasforsberg.localtracks.recording.Sport
import no.thomasforsberg.localtracks.track.RoutePreview
import no.thomasforsberg.localtracks.track.TrackPoint
import no.thomasforsberg.localtracks.track.activeKcalPerKg
import no.thomasforsberg.localtracks.track.routePreview
import kotlin.coroutines.CoroutineContext
import kotlin.native.HiddenFromObjC
import kotlin.time.Duration
import kotlin.time.DurationUnit
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds
import kotlin.time.Instant

data class ActivitySummary(
    val id: Long,
    val sport: Sport,
    val startedAt: Instant,
    val finishedAt: Instant?,
    val totals: ActivityTotals,
    // Started by auto-record rather than by hand.
    val autoStarted: Boolean = false,
    // The stretch before GPS recording started, already included in the totals; null if none.
    val leadIn: LeadIn? = null,
    // Active energy per kg of body weight; null until finished.
    val activeKcalPerKg: Double? = null,
)

data class ActivityTotals(
    @property:HiddenFromObjC val activeTime: Duration,
    val distanceMeters: Double,
    val pointCount: Int,
    val elevationGainMeters: Double = 0.0,
    @property:HiddenFromObjC val movingTime: Duration = Duration.ZERO,
    // Null when steps weren't counted.
    val stepCount: Int? = null,
) {
    // Kotlin's Duration reaches Swift as its raw internal encoding, so Swift gets plain seconds instead.
    val activeTimeSeconds: Double get() = activeTime.toDouble(DurationUnit.SECONDS)
    val movingTimeSeconds: Double get() = movingTime.toDouble(DurationUnit.SECONDS)

    companion object {
        // For Swift: the primary constructor takes a Duration, which Swift can't pass correctly.
        fun ofSeconds(
            activeTimeSeconds: Double,
            distanceMeters: Double,
            pointCount: Int,
            elevationGainMeters: Double,
            movingTimeSeconds: Double,
            stepCount: Int?,
        ) = ActivityTotals(activeTimeSeconds.seconds, distanceMeters, pointCount, elevationGainMeters, movingTimeSeconds.seconds, stepCount)
    }
}

class ActivityRepository(
    private val database: LocalTracksDatabase,
    private val queryContext: CoroutineContext = Dispatchers.Default,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(database: LocalTracksDatabase) : this(database, Dispatchers.Default)

    private val activities get() = database.activityQueries
    private val trackPoints get() = database.trackPointQueries

    fun startActivity(sport: Sport, startedAt: Instant): Long = startActivity(sport, startedAt, autoStarted = false, leadIn = null)

    fun startActivity(sport: Sport, startedAt: Instant, autoStarted: Boolean, leadIn: LeadIn?): Long = database.transactionWithResult {
        activities.insert(
            sport, startedAt, autoStarted,
            leadIn?.duration?.inWholeMilliseconds, leadIn?.distanceMeters, leadIn?.steps?.toLong(),
            leadIn?.startLatitude, leadIn?.startLongitude,
        )
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
                totals.movingTime.inWholeMilliseconds,
                totals.stepCount?.toLong(),
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
            totals.movingTime.inWholeMilliseconds,
            totals.stepCount?.toLong(),
            activityId,
        )
        updateEnergy(activityId)
    }

    fun updateEnergy(activityId: Long) {
        val activity = activity(activityId) ?: return
        activities.updateEnergy(activeKcalPerKg(trackPoints(activityId), activity.sport, activity.leadIn), activityId)
    }

    fun activity(id: Long): ActivitySummary? = activities.byId(id, ::activitySummary).executeAsOneOrNull()

    fun latestUnfinishedActivity(): ActivitySummary? = activities.latestUnfinished(::activitySummary).executeAsOneOrNull()

    // Finished activities, newest first; emits again whenever the table changes.
    fun finishedActivities(): Flow<List<ActivitySummary>> =
        activities.finished(::activitySummary).asFlow().mapToList(queryContext)

    fun trackPoints(activityId: Long): List<RecordedPoint> =
        trackPoints.forActivity(activityId).executeAsList().map { it.toRecordedPoint() }

    // For Swift, where Kotlin default arguments aren't available.
    fun routePreview(activityId: Long): RoutePreview? {
        val leadIn = activity(activityId)?.leadIn
        val start = if (leadIn?.startLatitude != null && leadIn.startLongitude != null) leadIn.startLatitude to leadIn.startLongitude else null
        return trackPoints(activityId).routePreview(leadInStart = start)
    }

    fun lastTrackPoint(activityId: Long): RecordedPoint? =
        trackPoints.lastForActivity(activityId).executeAsOneOrNull()?.toRecordedPoint()

    fun delete(activityId: Long) {
        database.transaction {
            trackPoints.deleteForActivity(activityId)
            activities.delete(activityId)
        }
        // Its route membership is tidied up by RouteLibrary.
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
    movingTimeMs: Long,
    stepCount: Long?,
    autoStarted: Boolean,
    leadInMs: Long?,
    leadInMeters: Double?,
    leadInSteps: Long?,
    leadInLatitude: Double?,
    leadInLongitude: Double?,
    activeKcalPerKg: Double?,
) = ActivitySummary(
    id,
    sport,
    startedAt,
    finishedAt,
    ActivityTotals(activeTimeMs.milliseconds, distanceMeters, pointCount.toInt(), elevationGainMeters, movingTimeMs.milliseconds, stepCount?.toInt()),
    autoStarted,
    if (leadInMs != null && leadInMeters != null) {
        LeadIn(leadInMs.milliseconds, leadInMeters, leadInSteps?.toInt(), leadInLatitude, leadInLongitude)
    } else {
        null
    },
    activeKcalPerKg,
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
    stationary_by_motion = point.stationaryByMotion,
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
        stationaryByMotion = stationary_by_motion,
    ),
)
