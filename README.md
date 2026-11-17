# Local Tracks

A privacy-first activity tracker for cycling, running, hiking and ski touring.

- **Everything stays on the phone.** No account, no server, no analytics or crash-reporting SDKs.
- Data leaves the device only when you export it yourself.
- Offline maps, so recording a ride makes no network requests.

Status: early development. iOS first, Android later on the same Kotlin core.

## Architecture

| Path | What |
|---|---|
| `shared/` | Kotlin Multiplatform core: track model, metrics, GPX. Targets iOS and JVM. |
| `iosApp/` | SwiftUI app. The Xcode project is generated from `iosApp/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). |
| `fixtures/gpx/` | Recorded tracks used by the tests and by Xcode location simulation. |

Swift calls into Kotlin through a static `Shared` framework, with [SKIE](https://skie.touchlab.co) for idiomatic Swift APIs.

## Building

Requirements: Xcode 26+, JDK 21, XcodeGen (`brew install xcodegen`).

```sh
./gradlew :shared:jvmTest                  # fast core tests
./gradlew :shared:iosSimulatorArm64Test    # core tests on the iOS simulator
cd iosApp && xcodegen && open LocalTracks.xcodeproj
```

To run on a device, create `iosApp/Config/Local.xcconfig` containing `DEVELOPMENT_TEAM = <your team ID>`, then regenerate the project.

The run scheme replays `fixtures/gpx/synthetic-sognsvann-loop.gpx` as the simulator location.

## License

[Apache License 2.0](LICENSE)
