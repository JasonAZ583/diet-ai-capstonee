import Foundation

// All models are explicitly `nonisolated` so their `Codable` conformances can
// be invoked from inside `actor APIClient`. Without this, Swift 6 strict
// concurrency infers them as `@MainActor`-isolated (because the project sets
// "Default Actor Isolation = MainActor"), which makes them unusable from any
// other isolation domain.

// MARK: - Food Vault

nonisolated struct FoodItem: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let brand: String?
    let barcode: String?
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let quantity: Double
    let serving_size: Double
    let unit: String
}

nonisolated struct FoodItemCreate: Codable, Sendable {
    var name: String
    var brand: String?
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0
    var quantity: Double = 1
    var serving_size: Double = 100
    var unit: String = "g"
}

// MARK: - Barcode

nonisolated struct BarcodeProduct: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let barcode: String?
    let brand: String?
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let fiber: Double
    let quantity: Double
    let serving_size: Double
    let unit: String

    /// Identifiable conformance — barcode if available, falls back to name.
    var id: String { barcode ?? name }
}

nonisolated struct BarcodeResponse: Codable, Sendable {
    let found: Bool
    let product: BarcodeProduct?
    let message: String
}

// MARK: - Goals

nonisolated struct DailyGoals: Codable, Hashable, Sendable {
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let is_manual: Bool?
}

// MARK: - Meals

nonisolated struct MealLog: Identifiable, Codable, Hashable, Sendable {
    let id: Int
    let name: String
    let food_item_id: Int?
    let date: String
    let amount: Double
    let servings: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let created_at: String
}

nonisolated struct MealLogCreate: Codable, Sendable {
    var food_item_id: Int?
    var name: String?
    var amount: Double = 100
    var servings: Double = 1
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    /// ISO-8601 timestamp. When set, the server logs the meal at this time
    /// instead of "now" — used by the calendar to drop a meal in a chosen hour.
    var eaten_at: String?
}

// MARK: - Dashboard

nonisolated struct DailyProgress: Codable, Sendable {
    let date: String
    let goals: DailyGoals
    let consumed: DailyGoals
    let remaining: DailyGoals
    let meals: [MealLog]
}

// MARK: - AI Meal Suggestions

nonisolated struct MealIngredient: Codable, Hashable, Identifiable, Sendable {
    var id: String { "\(food_item_id)-\(name)" }
    let food_item_id: Int
    let name: String
    let amount_grams: Double
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
}

nonisolated struct MealSuggestion: Codable, Hashable, Identifiable, Sendable {
    var id: String { name }
    let name: String
    let description: String
    let ingredients: [MealIngredient]
    let total_calories: Double
    let total_protein: Double
    let total_carbs: Double
    let total_fat: Double
    let is_makeable: Bool
    let missing_items: [String]
    let instructions: [String]
}

nonisolated struct MealSuggestionsResponse: Codable, Sendable {
    let suggestions: [MealSuggestion]
    let remaining_budget: DailyGoals
}

nonisolated struct ConfirmMealRequest: Codable, Sendable {
    let suggestion_index: Int
    let name: String?
    let ingredients: [MealIngredient]?
}

// MARK: - Chat

nonisolated struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    let role: String
    let content: String

    enum CodingKeys: String, CodingKey { case role, content }
}

nonisolated struct ChatRequest: Codable, Sendable {
    let message: String
    let history: [ChatMessage]
}

nonisolated struct LoggedMealAction: Codable, Sendable, Hashable {
    let id: Int
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let eaten_at: String?
}

nonisolated struct ChatResponse: Codable, Sendable {
    let reply: String
    let used_ai: Bool
    let logged: [LoggedMealAction]?
}
