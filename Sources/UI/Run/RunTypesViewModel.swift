import Foundation
import Observation

// MARK: - RunTypesViewModel

@Observable
@MainActor
final class RunTypesViewModel {
    var allTemplates: [RunTemplate] = []
    var searchText: String = ""
    var selectedType: RunType? = nil
    var isLoading = false
    var errorMessage: String?

    let dbManager: DatabaseManager

    init(dbManager: DatabaseManager) {
        self.dbManager = dbManager
    }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let repo = RunTemplateRepository(dbManager: dbManager)
            allTemplates = try await repo.listAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Filtered results

    var filteredTemplates: [RunTemplate] {
        allTemplates.filter { template in
            let matchesType = selectedType == nil || template.runType == selectedType
            let matchesSearch = searchText.isEmpty
                || template.name.localizedCaseInsensitiveContains(searchText)
            return matchesType && matchesSearch
        }
    }

    // MARK: - Filter toggle

    func toggleTypeFilter(_ type: RunType) {
        selectedType = selectedType == type ? nil : type
    }
}
