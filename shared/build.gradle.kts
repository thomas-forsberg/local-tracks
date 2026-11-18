plugins {
    alias(libs.plugins.kotlin.multiplatform)
    alias(libs.plugins.skie)
    alias(libs.plugins.sqldelight)
}

kotlin {
    jvmToolchain(21)

    // JVM target: fast unit tests on any OS, and the base for Android later.
    jvm()

    listOf(iosArm64(), iosSimulatorArm64()).forEach {
        it.binaries.framework {
            baseName = "Shared"
            isStatic = true
            binaryOption("bundleId", "no.thomasforsberg.localtracks.shared")
        }
    }

    sourceSets {
        all {
            languageSettings.optIn("kotlin.time.ExperimentalTime")
            languageSettings.optIn("kotlin.experimental.ExperimentalObjCRefinement")
        }
        commonMain.dependencies {
            implementation(libs.kotlinx.coroutines.core)
            implementation(libs.sqldelight.coroutines)
        }
        iosMain.dependencies {
            implementation(libs.sqldelight.native.driver)
        }
        commonTest.dependencies {
            implementation(kotlin("test"))
            implementation(libs.kotlinx.coroutines.test)
            implementation(libs.kotlinx.io.core)
        }
        jvmTest.dependencies {
            implementation(libs.sqldelight.sqlite.driver)
        }
    }
}

sqldelight {
    databases {
        create("LocalTracksDatabase") {
            packageName = "no.thomasforsberg.localtracks.db"
            // Snapshots of each released schema version; migrations are verified against them at build time.
            schemaOutputDirectory = file("src/commonMain/sqldelight/databases")
            verifyMigrations = true
        }
    }
}

// Tests read recorded GPX files from fixtures/gpx via this environment variable.
val gpxFixturesDir = rootProject.layout.projectDirectory.dir("fixtures/gpx").asFile.absolutePath

tasks.withType<Test>().configureEach {
    environment("GPX_FIXTURES_DIR", gpxFixturesDir)
}

tasks.withType<org.jetbrains.kotlin.gradle.targets.native.tasks.KotlinNativeTest>().configureEach {
    environment("GPX_FIXTURES_DIR", gpxFixturesDir)
    // simctl forwards SIMCTL_CHILD_* variables into the simulator process.
    environment("SIMCTL_CHILD_GPX_FIXTURES_DIR", gpxFixturesDir)
}

// CI boots a simulator early so its slow first boot overlaps with compiling; reuse it instead of booting another.
providers.environmentVariable("SIMULATOR_UDID").orNull?.let { udid ->
    tasks.withType<org.jetbrains.kotlin.gradle.targets.native.tasks.KotlinNativeSimulatorTest>().configureEach {
        device = udid
        standalone = false
    }
}
