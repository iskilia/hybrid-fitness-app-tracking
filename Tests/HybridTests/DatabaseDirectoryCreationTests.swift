import XCTest
import SQLite3
@testable import Hybrid

/// Reproduction + regression for the clean-install "Database unavailable — unable to
/// open database file" failure. SQLITE_OPEN_CREATE creates the database *file* but not
/// its parent *directory*. On a fresh device the app's Documents directory may not exist
/// yet, so opening Documents/Hybrid.sqlite fails with SQLITE_CANTOPEN. Every other test
/// opens inside temporaryDirectory (which always exists), so this path was never covered.
final class DatabaseDirectoryCreationTests: XCTestCase {

    /// A file URL one level below a directory that does NOT exist — mirrors a fresh
    /// install where Documents/ has not been created yet.
    private func urlInMissingDirectory() -> (url: URL, parent: URL) {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("hybrid-missing-\(UUID().uuidString)", isDirectory: true)
        return (parent.appendingPathComponent("Hybrid.sqlite"), parent)
    }

    func testOpenCreatesMissingParentDirectory() throws {
        let (url, parent) = urlInMissingDirectory()
        XCTAssertFalse(FileManager.default.fileExists(atPath: parent.path),
                       "precondition: parent directory must not exist yet")
        addTeardownBlock { try? FileManager.default.removeItem(at: parent) }

        // Must not throw SQLITE_CANTOPEN ("unable to open database file"); the manager
        // creates the parent directory first.
        let db = try DatabaseManager(url: url)
        XCTAssertNotNil(db)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "database file must exist on disk after a successful open")
    }
}
