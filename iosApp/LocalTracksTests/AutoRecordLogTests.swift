import Foundation
import Testing
@testable import LocalTracks

@MainActor
struct AutoRecordLogTests {
    private let file = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).txt")

    @Test func linesAreTimestampedInOrder() {
        let log = AutoRecordLog(file: file, now: { Date(timeIntervalSince1970: 0) })
        log.add("Home event: outside")
        log.add("AT_HOME → WATCHING")

        #expect(log.lines().count == 2)
        #expect(log.lines().last?.hasSuffix("  AT_HOME → WATCHING") == true)
    }

    @Test func keepsOnlyTheNewestLines() {
        let log = AutoRecordLog(file: file, maxLines: 10)
        (1...25).forEach { log.add("line \($0)") }

        let lines = log.lines()
        #expect(lines.count <= 12)
        #expect(lines.last?.hasSuffix("line 25") == true)
    }
}
