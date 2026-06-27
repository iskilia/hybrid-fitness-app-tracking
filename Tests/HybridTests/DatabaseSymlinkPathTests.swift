import XCTest
import SQLite3
@testable import Hybrid

/// Reproduction for the on-device "open: unable to open database file" failure where
/// the directory exists and is writable. The device's container lives under /var, a
/// symlink to /private/var. We open with SQLITE_OPEN_NOFOLLOW, and Apple's libsqlite3
/// rejects a symlink anywhere in the path — so the open fails on device but not in the
/// simulator (whose temp paths are not under a symlink). This recreates that by opening
/// a database whose path traverses an intermediate symlinked directory.
final class DatabaseSymlinkPathTests: XCTestCase {

    func testOpenThroughIntermediateSymlinkedDirectory() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-symlink-\(UUID().uuidString)", isDirectory: true)
        let realDir = base.appendingPathComponent("real", isDirectory: true)
        let linkDir = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createDirectory(at: realDir, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkDir, withDestinationURL: realDir)
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }

        // Path traverses `link` (a symlink) — mirrors /var -> /private/var on device.
        let url = linkDir.appendingPathComponent("Hybrid.sqlite")
        XCTAssertNoThrow(
            try DatabaseManager(url: url),
            "opening a database through a symlinked directory must succeed"
        )
    }
}
