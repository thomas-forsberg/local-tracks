import Foundation
import Testing
@testable import LocalTracks

struct DatabaseDirectoryTests {
    private let base = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)

    @Test func createsTheFolderExcludedFromBackupByDefault() throws {
        let directory = try DatabaseDirectory.prepare(in: base)

        #expect(FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func canBeIncludedInBackupAndIsSafeToPrepareAgain() throws {
        _ = try DatabaseDirectory.prepare(in: base)

        let directory = try DatabaseDirectory.prepare(in: base, excludedFromBackup: false)

        #expect(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    }
}
