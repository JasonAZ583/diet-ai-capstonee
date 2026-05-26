import Foundation
import Combine

@MainActor
final class CalendarLogViewModel: ObservableObject {
    @Published var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @Published var progress: DailyProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let calendar = Calendar.current

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            progress = try await APIClient.shared.dashboard(date: selectedDate)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func select(date: Date) {
        selectedDate = calendar.startOfDay(for: date)
        Task { await load() }
    }

    func step(byDays delta: Int) {
        guard let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) else { return }
        select(date: next)
    }

    func deleteMeal(_ meal: MealLog) async {
        do {
            try await APIClient.shared.deleteMeal(id: meal.id)
            // Remove locally for an instant UI update before reload.
            if var p = progress {
                p = DailyProgress(
                    date: p.date,
                    goals: p.goals,
                    consumed: p.consumed,
                    remaining: p.remaining,
                    meals: p.meals.filter { $0.id != meal.id }
                )
                progress = p
            }
            await load()
            // The backend restored ingredients to the vault — wake up vault,
            // dashboard, and any other listener so the new quantities show
            // immediately without a manual pull-to-refresh.
            NotificationCenter.default.post(name: .mealsChanged, object: nil)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Days for the week strip — Mon-Sun containing `selectedDate`.
    var weekDays: [Date] {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        let weekday = cal.component(.weekday, from: selectedDate)
        // Calculate days back to Monday.
        let offset = (weekday + 5) % 7 // Monday=0, Tuesday=1, ..., Sunday=6
        guard let monday = cal.date(byAdding: .day, value: -offset, to: selectedDate) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    /// Returns logged meals grouped by hour-of-day (0..23).
    func mealsByHour() -> [Int: [MealLog]] {
        var result: [Int: [MealLog]] = [:]
        for meal in progress?.meals ?? [] {
            guard let d = Self.parseTimestamp(meal.created_at) else { continue }
            let hour = calendar.component(.hour, from: d)
            result[hour, default: []].append(meal)
        }
        return result
    }

    /// Parses both tz-aware ISO ("2026-05-03T23:00:00Z") and naive ISO
    /// ("2026-05-03T23:00:00") timestamps. SQLAlchemy stores naive datetimes
    /// in SQLite, so the server emits the latter — `ISO8601DateFormatter` on
    /// its own can't read those.
    static func parseTimestamp(_ s: String) -> Date? {
        let isoF = ISO8601DateFormatter()
        isoF.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = isoF.date(from: s) { return d }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }

        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone.current
        for fmt in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
        ] {
            naive.dateFormat = fmt
            if let d = naive.date(from: s) { return d }
        }
        return nil
    }

    /// 24 hour slots from 6 AM through 11 PM (covers the typical eating window
    /// without cluttering with overnight slots; expand later if needed).
    var hourSlots: [Int] { Array(6...23) }
}
