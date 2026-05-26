import SwiftUI

struct CalendarLogView: View {
    @StateObject private var vm = CalendarLogViewModel()
    @State private var loggingHour: HourPick?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                dateNavigator
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                weekStrip
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                if let progress = vm.progress {
                    macroSummary(progress: progress)
                        .padding(.horizontal, 24)
                        .padding(.top, 18)

                    timeline(progress: progress)
                        .padding(.top, 16)
                        .padding(.bottom, 110)
                } else if vm.isLoading {
                    ProgressView()
                        .tint(Deck.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let err = vm.errorMessage {
                    DeckCard {
                        VStack(alignment: .leading, spacing: 6) {
                            MonoCaption(text: "Failed to load", color: Deck.warning)
                            Text(err)
                                .font(.deckMono(12))
                                .foregroundStyle(Deck.muted)
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Deck.bg)
        .refreshable { await vm.load() }
        .task { if vm.progress == nil { await vm.load() } }
        .onReceive(NotificationCenter.default.publisher(for: .mealsChanged)) { _ in
            Task { await vm.load() }
        }
        .sheet(item: $loggingHour) { pick in
            LogMealSheet(targetDate: pick.date, targetHour: pick.hour) {
                Task { await vm.load() }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoCaption(text: "Food log")
            Text("Timeline.")
                .font(.deckSerif(36))
                .foregroundStyle(Deck.text)
                .tracking(-0.5)
        }
        .padding(.top, 60)
    }

    // MARK: - Date navigator

    private var dateNavigator: some View {
        HStack {
            Button { vm.step(byDays: -1) } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Deck.text)
                    .frame(width: 34, height: 34)
                    .background(Deck.card, in: Circle())
                    .overlay(Circle().stroke(Deck.rule))
            }
            .buttonStyle(.plain)

            Spacer()

            Text(longDateLabel)
                .font(.deckSerif(20))
                .foregroundStyle(Deck.text)

            Spacer()

            Button { vm.step(byDays: 1) } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Deck.text)
                    .frame(width: 34, height: 34)
                    .background(Deck.card, in: Circle())
                    .overlay(Circle().stroke(Deck.rule))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        HStack(spacing: 6) {
            ForEach(vm.weekDays, id: \.self) { day in
                weekDayCell(date: day)
            }
        }
    }

    private func weekDayCell(date: Date) -> some View {
        let isSelected = Calendar.current.isDate(date, inSameDayAs: vm.selectedDate)
        let isToday = Calendar.current.isDateInToday(date)
        return Button {
            vm.select(date: date)
        } label: {
            VStack(spacing: 6) {
                Text(weekdayLetter(date))
                    .font(.deckMono(10))
                    .tracking(1.4)
                    .foregroundStyle(Deck.muted)
                Text(dayNumber(date))
                    .font(.deckSans(15, weight: .medium))
                    .foregroundStyle(isSelected ? Deck.ink : Deck.text)
                    .frame(width: 34, height: 34)
                    .background(
                        isSelected
                        ? AnyShapeStyle(Deck.accent)
                        : AnyShapeStyle(Color.clear),
                        in: Circle()
                    )
                    .overlay(
                        Circle().stroke(
                            isToday && !isSelected ? Deck.accent : .clear,
                            lineWidth: 1
                        )
                    )
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Macro summary

    private func macroSummary(progress: DailyProgress) -> some View {
        let items: [(symbol: String, label: String, value: Double, goal: Double, color: Color)] = [
            ("flame.fill", "kcal", progress.consumed.calories, progress.goals.calories, Deck.accent),
            ("p.circle.fill", "P", progress.consumed.protein, progress.goals.protein, Deck.proteinBar),
            ("f.circle.fill", "F", progress.consumed.fat, progress.goals.fat, Deck.fatBar),
            ("c.circle.fill", "C", progress.consumed.carbs, progress.goals.carbs, Deck.carbsBar),
        ]
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.label) { item in
                    macroChip(symbol: item.symbol, value: item.value, goal: item.goal, color: item.color, label: item.label)
                }
            }
        }
    }

    private func macroChip(symbol: String, value: Double, goal: Double, color: Color, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(Int(value.rounded()))")
                    .font(.deckSans(13, weight: .semibold))
                    .foregroundStyle(Deck.text)
                Text("/ \(Int(goal.rounded()))")
                    .font(.deckMono(10))
                    .foregroundStyle(Deck.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Deck.track)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * min(1, value / max(goal, 1)))
                }
            }
            .frame(height: 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Timeline

    private func timeline(progress: DailyProgress) -> some View {
        let buckets = vm.mealsByHour()
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(vm.hourSlots, id: \.self) { hour in
                let meals = buckets[hour] ?? []
                hourRow(hour: hour, meals: meals)
            }
        }
        .padding(.horizontal, 16)
    }

    private func hourRow(hour: Int, meals: [MealLog]) -> some View {
        // Two-column layout: fixed-width time gutter on the left, content on
        // the right. This keeps every "+" perfectly aligned across rows.
        HStack(alignment: .top, spacing: 12) {
            Button {
                loggingHour = HourPick(date: vm.selectedDate, hour: hour)
            } label: {
                HStack(spacing: 6) {
                    Text(hourLabel(hour))
                        .font(.deckMono(11))
                        .foregroundStyle(meals.isEmpty ? Deck.muted.opacity(0.7) : Deck.text)
                        .frame(width: 46, alignment: .trailing)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Deck.muted)
                        .frame(width: 18, height: 18)
                        .background(Deck.card, in: Circle())
                        .overlay(Circle().stroke(Deck.rule))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 76, alignment: .leading)

            VStack(alignment: .leading, spacing: 6) {
                if meals.isEmpty {
                    Color.clear.frame(height: 1)
                } else {
                    ForEach(meals) { meal in
                        TimelineMealCard(meal: meal) {
                            Task { await vm.deleteMeal(meal) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Date helpers

    private var longDateLabel: String {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f.string(from: vm.selectedDate)
    }

    private func weekdayLetter(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEEEE" // single letter
        return f.string(from: date).uppercased()
    }

    private func dayNumber(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    private func hourLabel(_ hour: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = hour
        let date = Calendar.current.date(from: comps) ?? Date()
        return f.string(from: date)
    }
}

private struct TimelineMealCard: View {
    let meal: MealLog
    let onDelete: () -> Void

    @State private var confirmingDelete = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(emoji(for: meal.name))
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(Deck.bg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Deck.rule))

            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name)
                    .font(.deckSerif(15))
                    .foregroundStyle(Deck.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Deck.accent)
                    Text("\(Int(meal.calories.rounded()))")
                        .font(.deckMono(11))
                        .foregroundStyle(Deck.text)
                    Text("\(Int(meal.protein.rounded()))P  \(Int(meal.fat.rounded()))F  \(Int(meal.carbs.rounded()))C · \(Int(meal.amount.rounded()))g")
                        .font(.deckMono(10))
                        .foregroundStyle(Deck.muted)
                }
            }
            Spacer()
            Button {
                confirmingDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Deck.muted)
                    .frame(width: 32, height: 32)
                    .background(Deck.bg, in: Circle())
                    .overlay(Circle().stroke(Deck.rule))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete meal", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete this meal?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Vault quantities will be restored.")
        }
    }

    /// Pick a contextual emoji from common keywords. Cheap, but it makes the
    /// timeline feel populated (no images needed).
    private func emoji(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("egg") { return "🍳" }
        if n.contains("salad") { return "🥗" }
        if n.contains("yogurt") || n.contains("greek") { return "🥣" }
        if n.contains("rice") { return "🍚" }
        if n.contains("chicken") { return "🍗" }
        if n.contains("salmon") || n.contains("fish") { return "🐟" }
        if n.contains("avocado") { return "🥑" }
        if n.contains("toast") || n.contains("bread") { return "🍞" }
        if n.contains("oat") { return "🌾" }
        if n.contains("banana") { return "🍌" }
        if n.contains("blueberr") || n.contains("berr") { return "🫐" }
        if n.contains("tomato") { return "🍅" }
        if n.contains("pepper") { return "🫑" }
        if n.contains("broccoli") { return "🥦" }
        if n.contains("eggplant") { return "🍆" }
        if n.contains("tofu") { return "🍱" }
        return "🍽"
    }
}

struct HourPick: Identifiable, Hashable {
    let date: Date
    let hour: Int
    var id: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: date))-\(hour)"
    }
}

#Preview {
    CalendarLogView()
        .preferredColorScheme(.dark)
}
