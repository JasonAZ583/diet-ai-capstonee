import Foundation
import Combine

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var meals: [MealLog] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            meals = try await APIClient.shared.mealHistory(limit: 60)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Group meals by date (yyyy-MM-dd) and return summaries newest first.
    var dayBuckets: [DayBucket] {
        let grouped = Dictionary(grouping: meals, by: { $0.date })
        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.compactMap { key in
            let entries = grouped[key] ?? []
            let calories = entries.reduce(0) { $0 + $1.calories }
            return DayBucket(date: key, calories: calories, mealCount: entries.count)
        }
    }
}

struct DayBucket: Identifiable, Hashable {
    let date: String
    let calories: Double
    let mealCount: Int
    var id: String { date }
}
