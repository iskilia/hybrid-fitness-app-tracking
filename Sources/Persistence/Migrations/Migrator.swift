import SQLite3
import Foundation

// MARK: - Public entry point

// App is unreleased; schema is created in place (all CREATE ... IF NOT EXISTS),
// no versioned migrations. Wipe Hybrid.sqlite from the simulator before running.
public func migrate(_ db: OpaquePointer) throws {
    try applySchema(db)
}
