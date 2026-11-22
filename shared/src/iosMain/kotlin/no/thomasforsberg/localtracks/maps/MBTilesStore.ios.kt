package no.thomasforsberg.localtracks.maps

import app.cash.sqldelight.driver.native.NativeSqliteDriver
import app.cash.sqldelight.driver.native.wrapConnection
import co.touchlab.sqliter.DatabaseConfiguration
import co.touchlab.sqliter.JournalMode
import no.thomasforsberg.localtracks.maps.db.MBTilesDatabase

// Opens or creates a region's MBTiles file. The caller owns the directory, as for the activity database.
fun openIosMBTiles(directoryPath: String, fileName: String): MBTilesStore {
    val schema = MBTilesDatabase.Schema
    val driver = NativeSqliteDriver(
        DatabaseConfiguration(
            name = fileName,
            version = schema.version.toInt(),
            create = { connection -> wrapConnection(connection) { schema.create(it) } },
            // A plain rollback journal rather than WAL: MapLibre opens the file as a separate reader,
            // and a single file is simpler to share, delete and exclude from backup.
            journalMode = JournalMode.DELETE,
            extendedConfig = DatabaseConfiguration.Extended(basePath = directoryPath),
        ),
    )
    return MBTilesStore(driver)
}
