package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import no.thomasforsberg.localtracks.db.LocalTracksDatabase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.seconds

// Migrates a database in the exact version-1 layout, as on devices that recorded before version 2.
class MigrationTest {
    private val version1Schema = listOf(
        """CREATE TABLE activity (
            id INTEGER PRIMARY KEY AUTOINCREMENT, sport TEXT NOT NULL, started_at INTEGER NOT NULL, finished_at INTEGER,
            active_time_ms INTEGER NOT NULL DEFAULT 0, distance_meters REAL NOT NULL DEFAULT 0,
            point_count INTEGER NOT NULL DEFAULT 0, elevation_gain_meters REAL NOT NULL DEFAULT 0)""",
        "CREATE INDEX activity_started_at ON activity (started_at)",
        """CREATE TABLE track_point (
            activity_id INTEGER NOT NULL, seq INTEGER NOT NULL, segment INTEGER NOT NULL, time INTEGER NOT NULL,
            latitude REAL NOT NULL, longitude REAL NOT NULL, elevation_meters REAL, horizontal_accuracy_meters REAL,
            speed_mps REAL, baro_time INTEGER, baro_relative_altitude_meters REAL, baro_pressure_kpa REAL,
            PRIMARY KEY (activity_id, seq)) WITHOUT ROWID""",
    )

    @Test
    fun version1ActivitiesAreKeptAndReMeasured() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        version1Schema.forEach { driver.execute(null, it, 0) }
        val start = 1_789_196_400_000L
        driver.execute(null, "INSERT INTO activity VALUES (1, 'HIKING', $start, ${start + 600_000}, 600000, 999.0, 6, 12.5)", 0)
        // 5 m/s north for 4 s, then 2 s standing still (iOS reports speed 0).
        listOf(0.0 to 5.0, 1.0 to 5.0, 2.0 to 5.0, 3.0 to 5.0, 4.0 to 5.0, 5.0 to 0.0).forEachIndexed { seq, (second, speed) ->
            val north = minOf(second, 4.0) * 5.0
            driver.execute(
                null,
                "INSERT INTO track_point VALUES (1, $seq, 0, ${start + (second * 1000).toLong()}, ${59.9 + north / 111_195.08}, 10.7, NULL, 5.0, $speed, NULL, NULL, NULL)",
                0,
            )
        }

        migrateDatabase(driver, oldVersion = 1, newVersion = LocalTracksDatabase.Schema.version)

        val activity = ActivityRepository(createDatabase(driver)).activity(1)!!
        // 20 m walked; the last moving point is averaged with the stop, which costs a third of a 5 m step.
        assertEquals(18.33, activity.totals.distanceMeters, absoluteTolerance = 0.01, "re-measured from the points")
        assertEquals(4.seconds, activity.totals.movingTime, "the last second was standing still")
        assertEquals(600.0, activity.totals.activeTimeSeconds, "untouched")
        assertEquals(12.5, activity.totals.elevationGainMeters, "untouched")
        assertTrue(activity.finishedAt != null)
    }

    @Test
    fun version8ChecksUnmatchedActivitiesAgainAndKeepsRoutes() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        LocalTracksDatabase.Schema.create(driver)
        driver.execute(null, "INSERT INTO route (id, name, reference_activity_id, created_at) VALUES (1, 'Lake', 1, 0)", 0)
        driver.execute(null, "INSERT INTO route_activity VALUES (1, 1, 0), (2, 1, 1), (3, NULL, 0)", 0)

        migrateDatabase(driver, oldVersion = 8, newVersion = LocalTracksDatabase.Schema.version)

        val queries = createDatabase(driver).routeQueries
        assertEquals(listOf(1L, 2L), queries.members(1).executeAsList().map { it.activity_id }.sorted())
        assertEquals(null, queries.membership(3).executeAsOneOrNull(), "unchecked again")
        assertEquals("Lake", queries.routeById(1).executeAsOne().name)
    }

    @Test
    fun version9CountsClimbsAgainFromTheBarometer() {
        val driver = JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY)
        LocalTracksDatabase.Schema.create(driver)
        driver.execute(null, "INSERT INTO activity (id, sport, started_at, elevation_gain_meters) VALUES (1, 'HIKING', 0, 6.0), (2, 'HIKING', 0, 12.5)", 0)
        // Activity 1 climbed 7.4 m, counted as 6 m in steps of 3; activity 2 has no barometer readings.
        listOf(0.0, 3.1, 7.4).forEachIndexed { seq, altitude ->
            driver.execute(null, "INSERT INTO track_point (activity_id, seq, segment, time, latitude, longitude, baro_time, baro_relative_altitude_meters, baro_pressure_kpa) VALUES (1, $seq, 0, $seq, 59.9, 10.7, $seq, $altitude, 100.0)", 0)
        }
        driver.execute(null, "INSERT INTO track_point (activity_id, seq, segment, time, latitude, longitude) VALUES (2, 0, 0, 0, 59.9, 10.7)", 0)

        migrateDatabase(driver, oldVersion = 9, newVersion = LocalTracksDatabase.Schema.version)

        val repository = ActivityRepository(createDatabase(driver))
        assertEquals(7.4, repository.activity(1)!!.totals.elevationGainMeters, absoluteTolerance = 1e-9)
        assertEquals(12.5, repository.activity(2)!!.totals.elevationGainMeters, "untouched")
    }
}
