package no.thomasforsberg.localtracks.routes

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import no.thomasforsberg.localtracks.storage.ActivityRepository
import no.thomasforsberg.localtracks.storage.ActivitySummary
import kotlin.coroutines.CoroutineContext
import kotlin.time.Clock

data class RouteAttempt(val activity: ActivitySummary, val reversed: Boolean)

// A route with every attempt at it (all sports), oldest first.
data class RouteSummary(
    val id: Long,
    // Null until the user names it.
    val name: String?,
    val referenceActivityId: Long,
    val lengthMeters: Double,
    val shape: RouteShape,
    val attempts: List<RouteAttempt>,
)

// Finds routes among the finished activities and keeps them up to date. Matching runs over the stored
// points on the phone; nothing leaves it.
class RouteLibrary(
    private val database: LocalTracksDatabase,
    private val activities: ActivityRepository,
    private val clock: Clock = Clock.System,
    private val workContext: CoroutineContext = Dispatchers.Default,
) {
    // For Swift, where Kotlin default arguments aren't available.
    constructor(database: LocalTracksDatabase, activities: ActivityRepository) : this(database, activities, Clock.System)

    private val queries get() = database.routeQueries
    // One matching run at a time (e.g. at launch and after a recording stops).
    private val matching = Mutex()

    // Checks every finished activity not checked before, oldest first: on first use that's all of them,
    // afterwards just the newly finished ones. Returns how many were checked.
    suspend fun matchNewActivities(): Int = matching.withLock {
        withContext(workContext) {
            tidyUp()
            // Tracks are read once per run; this stays local, so nothing is shared between threads.
            val tracks = mutableMapOf<Long, RouteTrack?>()
            val unchecked = queries.unchecked().executeAsList()
            unchecked.forEach { check(it) { id -> tracks.getOrPut(id) { track(id) } } }
            unchecked.size
        }
    }

    fun routes(): List<RouteSummary> = queries.allRoutes().executeAsList().mapNotNull { summary(it.id) }

    fun route(id: Long): RouteSummary? = summary(id)

    fun routeFor(activityId: Long): RouteSummary? =
        queries.membership(activityId).executeAsOneOrNull()?.route_id?.let(::summary)

    fun rename(routeId: Long, name: String) {
        queries.rename(name.trim().takeIf { it.isNotEmpty() }, routeId)
    }

    private fun check(activityId: Long, track: (Long) -> RouteTrack?) {
        val track = track(activityId)
        if (track == null) {
            queries.assign(activityId, null, false)
            return
        }
        // An existing route first: compared with its reference attempt.
        for (route in queries.allRoutes().executeAsList()) {
            val reference = track(route.reference_activity_id) ?: continue
            val match = RouteMatching.match(track, reference) ?: continue
            queries.assign(activityId, route.id, match.reversed)
            return
        }
        // Then earlier activities that matched nothing: together they make a new route.
        for (otherId in queries.unmatched().executeAsList()) {
            val other = track(otherId) ?: continue
            val match = RouteMatching.match(track, other) ?: continue
            database.transaction {
                queries.insertRoute(otherId, clock.now())
                val routeId = queries.lastInsertedId().executeAsOne()
                queries.assign(otherId, routeId, false)
                queries.assign(activityId, routeId, match.reversed)
            }
            return
        }
        queries.assign(activityId, null, false)
    }

    // After deletions: forget deleted activities, keep each route's reference valid, and dissolve routes
    // left with a single attempt.
    private fun tidyUp() = database.transaction {
        queries.forgetDeletedActivities()
        queries.moveReferenceToAMember()
        queries.releaseLoneMembers()
        queries.deleteEmptyRoutes()
    }

    private fun summary(routeId: Long): RouteSummary? {
        val route = queries.routeById(routeId).executeAsOneOrNull() ?: return null
        val attempts = queries.members(routeId).executeAsList()
            .mapNotNull { member -> activities.activity(member.activity_id)?.let { RouteAttempt(it, member.reversed) } }
            .sortedBy { it.activity.startedAt }
        val reference = attempts.firstOrNull { it.activity.id == route.reference_activity_id } ?: attempts.firstOrNull() ?: return null
        val line = track(reference.activity.id)?.line.orEmpty()
        return RouteSummary(route.id, route.name, reference.activity.id, reference.activity.totals.distanceMeters, RouteMatching.shape(line), attempts)
    }

    private fun track(activityId: Long): RouteTrack? {
        val activity = activities.activity(activityId) ?: return null
        val points = activities.trackPoints(activityId).map { GeoPoint(it.point.latitude, it.point.longitude) }
        // An automatic recording's GPS starts some way from home; the stretch before it starts at home.
        val leadIn = activity.leadIn
        val start = if (leadIn?.startLatitude != null && leadIn.startLongitude != null) GeoPoint(leadIn.startLatitude, leadIn.startLongitude) else null
        val line = (listOfNotNull(start) + points).resampled(RouteMatching.SPACING_METERS)
        return if (line.size < 2) null else RouteTrack(activityId, activity.sport, activity.totals.distanceMeters, line)
    }
}
