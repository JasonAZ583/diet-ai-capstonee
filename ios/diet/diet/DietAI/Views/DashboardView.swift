import SwiftUI

struct DashboardView: View {
    @StateObject private var vm = DashboardViewModel()
    @State private var showingChat = false
    @State private var showingScanner = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if let progress = vm.progress {
                    // Big ring
                    HStack {
                        Spacer()
                        MacroRing(
                            value: progress.consumed.calories,
                            goal: progress.goals.calories
                        )
                        Spacer()
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    // Macro bars
                    VStack(spacing: 18) {
                        MacroBar(label: "Protein",
                                 value: progress.consumed.protein,
                                 goal: progress.goals.protein,
                                 color: Deck.proteinBar)
                        MacroBar(label: "Carbs",
                                 value: progress.consumed.carbs,
                                 goal: progress.goals.carbs,
                                 color: Deck.carbsBar)
                        MacroBar(label: "Fat",
                                 value: progress.consumed.fat,
                                 goal: progress.goals.fat,
                                 color: Deck.fatBar)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                    // Primary CTA
                    suggestCTA
                        .padding(.horizontal, 24)
                        .padding(.top, 32)

                    // Secondary tiles
                    HStack(spacing: 12) {
                        ActionTile(icon: "barcode.viewfinder", label: "Scan barcode") {
                            showingScanner = true
                        }
                        ActionTile(icon: "bubble.left.and.bubble.right.fill", label: "Ask AI") {
                            showingChat = true
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)

                    // Today's meals
                    todaysMeals(meals: progress.meals)
                        .padding(.top, 32)
                        .padding(.bottom, 100)
                } else if vm.isLoading {
                    ProgressView()
                        .tint(Deck.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if let err = vm.errorMessage {
                    errorView(err)
                        .padding(.top, 60)
                }
            }
        }
        .background(Deck.bg)
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .mealsChanged)) { _ in
            Task { await vm.load() }
        }
        .sheet(isPresented: $showingChat) {
            ChatView()
                .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $showingScanner) {
            BarcodeView()
                .preferredColorScheme(.dark)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                MonoCaption(text: dateString)
                Text("Today.")
                    .font(.deckSerif(36))
                    .foregroundStyle(Deck.text)
                    .tracking(-0.5)
            }
            Spacer()
            Button {
                showingChat = true
            } label: {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Deck.text)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 60)
    }

    private var suggestCTA: some View {
        Button {
            // Tab switching handled by parent if user navigates; here we just nudge.
            NotificationCenter.default.post(name: .switchToSuggest, object: nil)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    MonoCaption(text: "Decision engine", color: Deck.ink.opacity(0.6))
                    Text("Suggest a meal")
                        .font(.deckSerif(22))
                        .foregroundStyle(Deck.ink)
                }
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 22))
                    .foregroundStyle(Deck.ink)
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Deck.ink)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(Deck.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func todaysMeals(meals: [MealLog]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoCaption(text: "Today's meals · \(meals.count)")
                Spacer()
            }
            .padding(.horizontal, 24)

            if meals.isEmpty {
                EmptyMealsCard()
                    .padding(.horizontal, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(meals) { meal in
                        MealRowView(meal: meal)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Deck.warning)
                .font(.largeTitle)
            Text("Could not load")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text(message)
                .font(.deckMono(11))
                .foregroundStyle(Deck.muted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(Deck.accent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEEE · MMM d"
        return f.string(from: Date())
    }
}

extension Notification.Name {
    static let switchToSuggest = Notification.Name("DietAI.switchToSuggest")
    static let switchToVault   = Notification.Name("DietAI.switchToVault")
}

// MARK: - Subviews

struct ActionTile: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(Deck.accent)
                Text(label)
                    .font(.deckSans(14, weight: .medium))
                    .foregroundStyle(Deck.text)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 18)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background(Deck.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Deck.rule))
        }
        .buttonStyle(.plain)
    }
}

struct MealRowView: View {
    let meal: MealLog

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(meal.name)
                    .font(.deckSerif(17))
                    .foregroundStyle(Deck.text)
                    .lineLimit(1)
                Text("\(formattedTime) · \(Int(meal.calories.rounded())) kcal · \(Int(meal.protein.rounded()))p · \(Int(meal.carbs.rounded()))c · \(Int(meal.fat.rounded()))f")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
            Spacer()
            Text("\(formattedServings)× \(Int(meal.amount.rounded()))g")
                .font(.deckMono(10))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(Deck.muted)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
    }

    private var formattedTime: String {
        guard let d = CalendarLogViewModel.parseTimestamp(meal.created_at) else { return "" }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }

    private var formattedServings: String {
        meal.servings.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(meal.servings))"
            : String(format: "%.1f", meal.servings)
    }
}

struct EmptyMealsCard: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "fork.knife")
                .font(.system(size: 32))
                .foregroundStyle(Deck.muted)
            Text("Nothing logged yet")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text("Suggest a meal or scan something to fill your vault.")
                .font(.deckSans(13))
                .foregroundStyle(Deck.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Deck.rule, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        )
    }
}

#Preview {
    DashboardView()
        .background(Deck.bg)
        .preferredColorScheme(.dark)
}
