package no.thomasforsberg.localtracks.storage

import app.cash.sqldelight.db.QueryResult
import app.cash.sqldelight.db.SqlDriver
import app.cash.sqldelight.db.SqlPreparedStatement

// Wraps a driver so tests can make writes fail, as on a full disk.
class FailingDriver(private val delegate: SqlDriver) : SqlDriver by delegate {
    var failWrites = false

    override fun execute(
        identifier: Int?,
        sql: String,
        parameters: Int,
        binders: (SqlPreparedStatement.() -> Unit)?,
    ): QueryResult<Long> {
        if (failWrites) throw IllegalStateException("disk I/O error (simulated)")
        return delegate.execute(identifier, sql, parameters, binders)
    }
}
