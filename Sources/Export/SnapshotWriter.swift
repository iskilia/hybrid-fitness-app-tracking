import Foundation

// TV3.1 / TV3.3 — Atomic, debounced JSON snapshot writer.
//
// JSON envelope strategy: JSONExporter produces a flat `[table: [rows]]` dict.
// SnapshotWriter wraps it in {"schema_version":"2.0","data":<existing>} so the
// top-level field is unambiguous and appears first in sorted-key output.
// ("data" sorts after "schema_version" lexicographically, matching .sortedKeys.)

public enum WriteMode: Sendable {
    case idle
    case full
    case manifest
}

public actor SnapshotWriter {

    private let documentsURL: URL
    private let dbManager: DatabaseManager
    private let sizeThresholdBytes: Int

    private var pendingTask: Task<Void, Never>?
    public private(set) var lastWriteMode: WriteMode = .idle

    public init(
        documentsURL: URL,
        dbManager: DatabaseManager,
        sizeThresholdBytes: Int = 10 * 1024 * 1024
    ) {
        self.documentsURL = documentsURL
        self.dbManager = dbManager
        self.sizeThresholdBytes = sizeThresholdBytes
    }

    // Debounced write: multiple calls within 250 ms collapse to one final write.
    public func write() {
        pendingTask?.cancel()
        pendingTask = Task {
            do {
                try await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            } catch {
                return // cancelled — a newer call took over
            }
            await performWrite()
        }
    }

    // MARK: - Private

    private func performWrite() async {
        let targetURL = documentsURL.appendingPathComponent("hybrid-latest.json")

        // TV3.3: size-threshold fallback
        if let dbURL = dbManager.dbFileURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: dbURL.path),
           let size = attrs[.size] as? Int,
           size > sizeThresholdBytes {
            writeManifest(to: targetURL, dbSizeBytes: size)
            lastWriteMode = .manifest
            return
        }

        do {
            let data = try await buildSnapshotData()
            try atomicWrite(data: data, to: targetURL)
            lastWriteMode = .full
        } catch {
            // Silent failure — snapshot is best-effort; app function is unaffected.
        }
    }

    private func buildSnapshotData() async throws -> Data {
        // Reuse JSONExporter to produce the full export, then read its output.
        let exporter = JSONExporter(dbManager: dbManager)
        let fileURL = try await exporter.export()
        let exportedData = try Data(contentsOf: fileURL)

        // Deserialise, wrap with schema_version envelope, re-serialise with stable options.
        let existingObject = try JSONSerialization.jsonObject(with: exportedData)
        let envelope: [String: Any] = [
            "schema_version": SchemaDoc.schemaVersion,
            "data": existingObject,
        ]
        return try JSONSerialization.data(
            withJSONObject: envelope,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private func writeManifest(to targetURL: URL, dbSizeBytes: Int) {
        let iso8601: String = {
            let f = ISO8601DateFormatter()
            return f.string(from: Date())
        }()
        let manifest: [String: Any] = [
            "schema_version": SchemaDoc.schemaVersion,
            "mode": "manifest",
            "db_size_bytes": dbSizeBytes,
            "message": "Database is over \(sizeThresholdBytes) bytes; use Settings → Export for a full snapshot.",
            "generated_at": iso8601,
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? atomicWrite(data: data, to: targetURL)
    }

    private func atomicWrite(data: Data, to targetURL: URL) throws {
        let tempURL = documentsURL.appendingPathComponent("hybrid-latest.tmp.json")
        try data.write(to: tempURL, options: .atomic)
        _ = try FileManager.default.replaceItemAt(targetURL, withItemAt: tempURL)
    }
}
