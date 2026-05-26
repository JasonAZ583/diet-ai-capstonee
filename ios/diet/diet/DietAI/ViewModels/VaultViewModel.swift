import Foundation
import Combine

@MainActor
final class VaultViewModel: ObservableObject {
    @Published var items: [FoodItem] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            items = try await APIClient.shared.vault()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func add(_ item: FoodItemCreate) async {
        do {
            let new = try await APIClient.shared.addFoodItem(item)
            items.append(new)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ item: FoodItem) async {
        do {
            try await APIClient.shared.deleteVaultItem(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
