package no.thomasforsberg.localtracks

import kotlinx.cinterop.ExperimentalForeignApi
import kotlinx.cinterop.toKString
import platform.posix.getenv

@OptIn(ExperimentalForeignApi::class)
actual fun environmentVariable(name: String): String? = getenv(name)?.toKString()
