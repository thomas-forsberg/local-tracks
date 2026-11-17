package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.driver.jdbc.sqlite.JdbcSqliteDriver
import no.thomasforsberg.localtracks.db.LocalTracksDatabase

actual fun createInMemoryDriver(): SqlDriver =
    JdbcSqliteDriver(JdbcSqliteDriver.IN_MEMORY).also { LocalTracksDatabase.Schema.create(it) }
