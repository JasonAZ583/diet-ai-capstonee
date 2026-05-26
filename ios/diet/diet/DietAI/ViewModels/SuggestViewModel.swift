import Foundation
import Combine

@MainActor
final class SuggestViewModel: ObservableObject {
    /// Shared instance so suggestions survive tab switches — without this,
    /// every visit to the Suggest tab kicks off a fresh /api/meals/suggest
    /// call (an LLM round trip).
    static let shared = SuggestViewModel()

    enum Stage { case idle, loading, list, error }

    @Published var stage: Stage = .idle
    @Published var suggestions: [MealSuggestion] = []
    @Published var remaining: DailyGoals?
    @Published var mealType: String = "dinner"
    @Published var errorMessage: String?

    func load() async {
        stage = .loading
        errorMessage = nil
        do {
            let response = try await APIClient.shared.suggestMeals(numSuggestions: 3, mealType: mealType)
            suggestions = response.suggestions
            remaining = response.remaining_budget
            stage = .list
        } catch {
            errorMessage = error.localizedDescription
            stage = .error
        }
    }

    func confirm(index: Int) async -> Bool {
        guard suggestions.indices.contains(index) else { return false }
        let suggestion = suggestions[index]
        do {
            // Send the full ingredients + name. The backend's fallback path
            // (`_last_suggestions[idx]`) is fragile across uvicorn reloads —
            // passing the data directly makes confirmation deterministic.
            _ = try await APIClient.shared.confirmMeal(
                ConfirmMealRequest(
                    suggestion_index: index,
                    name: suggestion.name,
                    ingredients: suggestion.ingredients
                )
            )
            // Drop the just-confirmed suggestion locally so the user sees
            // immediate feedback without us needing to re-call the LLM.
            suggestions.remove(at: index)
            NotificationCenter.default.post(name: .mealsChanged, object: nil)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
