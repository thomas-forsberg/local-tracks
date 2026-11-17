package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.driver.native.NativeSqliteDriver
import app.cash.sqldelight.driver.native.wrapConnection
import co.touchlab.sqliter.DatabaseConfiguration
import no.thomasforsberg.localtracks.db.LocalTracksDatabase

// The caller owns the directory: create it with the right file protection and backup exclusion first.
fun createIosDatabase(directoryPath: String, fileName: String = "local-tracks.db"): LocalTracksDatabase {
    val schema = LocalTracksDatabase.Schema
    val driver = NativeSqliteDriver(
        DatabaseConfiguration(
            name = fileName,
            version = schema.version.toInt(),
            create = { connection -> wrapConnection(connection) { schema.create(it) } },
            upgrade = { connection, oldVersion, newVersion ->
                wrapConnection(connection) { schema.migrate(it, oldVersion.toLong(), newVersion.toLong()) }
            },
            extendedConfig = DatabaseConfiguration.Extended(basePath = directoryPath),
        ),
    )
    return createDatabase(driver)
}
