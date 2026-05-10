import Foundation
import Observation

// MARK: - EditableBlock

struct EditableBlock: Identifiable {
    var id: UUID = UUID()
    var blockType: IntervalBlockType = .work
    var distanceKm: String = ""
    var durationSecs: String = ""
    var targetPaceSecs: String = ""
    var repeatCount: String = "1"
    var sortOrder: Int = 0
}

// MARK: - CustomRunTemplateEditorViewModel

@Observable
@MainActor
final class CustomRunTemplateEditorViewModel {
    var name: String = ""
    var runType: RunType = .steady
    var distanceKm: String = ""
    var paceMinMin: String = ""
    var paceMinSec: String = ""
    var paceMaxMin: String = ""
    var paceMaxSec: String = ""
    var hrMin: String = ""
    var hrMax: String = ""
    var notes: String = ""
    var blocks: [EditableBlock] = []
    var isSaving = false
    var errorMessage: String?

    private let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Block management

    func addBlock() {
        var block = EditableBlock()
        block.sortOrder = blocks.count
        blocks.append(block)
    }

    func removeBlock(at offsets: IndexSet) {
        blocks.remove(atOffsets: offsets)
        for i in blocks.indices { blocks[i].sortOrder = i }
    }

    // MARK: - Save

    func save() async -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Name is required."
            return false
        }
        isSaving = true
        defer { isSaving = false }

        let now = Date()
        let template = RunTemplate(
            id: 0,
            clientUUID: UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            runType: runType,
            targetTotalDistanceKm: Double(distanceKm),
            targetWorkDistanceKm: nil,
            targetPaceSecsMin: paceSecs(min: paceMinMin, sec: paceMinSec),
            targetPaceSecsMax: paceSecs(min: paceMaxMin, sec: paceMaxSec),
            hrZoneMin: nil,
            hrZoneMax: nil,
            hrBpmMin: Int(hrMin),
            hrBpmMax: Int(hrMax),
            isCustom: true,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )

        let runBlocks: [RunIntervalBlock] = blocks.enumerated().map { idx, b in
            RunIntervalBlock(
                id: 0,
                runTemplateID: 0,
                sortOrder: idx,
                blockType: b.blockType,
                repeatCount: Int(b.repeatCount) ?? 1,
                distanceKm: Double(b.distanceKm),
                durationSecs: Int(b.durationSecs),
                targetPaceSecs: Int(b.targetPaceSecs),
                hrZone: nil,
                notes: nil
            )
        }

        do {
            let repo = RunTemplateRepository(dbManager: dbManager)
            try await repo.create(template, blocks: runBlocks)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Helpers

    private func paceSecs(min: String, sec: String) -> Int? {
        guard let m = Int(min) else { return nil }
        let s = Int(sec) ?? 0
        return m * 60 + s
    }
}
