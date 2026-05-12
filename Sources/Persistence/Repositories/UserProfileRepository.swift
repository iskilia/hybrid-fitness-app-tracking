import Foundation
import SQLite3

// Single-row user_profile (id = 1 enforced by schema CHECK).

struct UserProfileRepository {
    let dbManager: DatabaseManager

    func get() async throws -> UserProfile? {
        try await dbManager.read { db in
            let stmt = try prepare(db, """
                SELECT id, client_uuid, name, weight_unit, distance_unit,
                       body_weight_kg, created_at, updated_at
                FROM user_profile WHERE id = 1;
                """)
            defer { finalize(stmt) }
            guard try step(stmt),
                  let uuidStr = columnText(stmt, 1),
                  let uuid = UUID(uuidString: uuidStr),
                  let name = columnText(stmt, 2),
                  let wuStr = columnText(stmt, 3),
                  let wu = WeightUnit(rawValue: wuStr),
                  let duStr = columnText(stmt, 4),
                  let du = DistanceUnit(rawValue: duStr),
                  let createdAt = columnDate(stmt, 6),
                  let updatedAt = columnDate(stmt, 7)
            else { return nil }
            return UserProfile(
                id: Int(sqlite3_column_int64(stmt, 0)),
                clientUUID: uuid,
                name: name,
                weightUnit: wu,
                distanceUnit: du,
                bodyWeightKg: columnDouble(stmt, 5),
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
    }

    func upsert(weightUnit: WeightUnit, distanceUnit: DistanceUnit, bodyWeightKg: Double?) async throws {
        try await dbManager.transaction { db in
            let now = Date()
            let stmt = try prepare(db, """
                INSERT INTO user_profile (id, client_uuid, name, weight_unit,
                                         distance_unit, body_weight_kg,
                                         created_at, updated_at)
                VALUES (1, ?, '', ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    weight_unit = excluded.weight_unit,
                    distance_unit = excluded.distance_unit,
                    body_weight_kg = excluded.body_weight_kg,
                    updated_at = excluded.updated_at;
                """)
            defer { finalize(stmt) }
            bindUUID(stmt, 1, UUID())
            bindText(stmt, 2, weightUnit.rawValue)
            bindText(stmt, 3, distanceUnit.rawValue)
            bindDouble(stmt, 4, bodyWeightKg)
            bindDate(stmt, 5, now)
            bindDate(stmt, 6, now)
            _ = try step(stmt)
        }
    }
}
