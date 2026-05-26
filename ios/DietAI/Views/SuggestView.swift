import SwiftUI

struct SuggestView: View {
    @ObservedObject private var vm = SuggestViewModel.shared
    @State private var openIndex: Int?
    @State private var confirmingIndex: Int?

    private let mealTypes = ["breakfast", "lunch", "dinner", "snack"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                mealTypeChips
                    .padding(.top, 20)

                Group {
                    switch vm.stage {
                    case .idle:    idleState
                    case .loading: loadingState
                    case .list:    listState
                    case .error:   errorState
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 110)
            }
        }
        .background(Deck.bg)
        // No auto-fire — the user generates explicitly via the empty-state
        // CTA, the header refresh button, or pull-to-refresh.
        .refreshable { await vm.load() }
        .sheet(item: Binding<IndexedSuggestion?>(
            get: {
                guard let idx = openIndex, vm.suggestions.indices.contains(idx) else {
                    return nil
                }
                return IndexedSuggestion(index: idx, suggestion: vm.suggestions[idx])
            },
            // Swift 6 strict concurrency requires the (Value, Transaction)
            // setter shape. We don't use the transaction.
            set: { newValue, _ in openIndex = newValue?.index }
        )) { wrapped in
            SuggestionDetail(
                suggestion: wrapped.suggestion,
                index: wrapped.index,
                isConfirming: confirmingIndex == wrapped.index,
                onConfirm: {
                    confirmingIndex = wrapped.index
                    Task {
                        let ok = await vm.confirm(index: wrapped.index)
                        confirmingIndex = nil
                        if ok {
                            // Close the detail sheet. Do NOT regenerate —
                            // the user explicitly chose this meal; the
                            // remaining suggestions are still valid until
                            // they hit refresh themselves.
                            openIndex = nil
                        }
                    }
                }
            )
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Deck.accent)
                    MonoCaption(text: "AI · Dedalus · claude-haiku", color: Deck.accent)
                }
                Spacer()
                if !vm.suggestions.isEmpty {
                    Button {
                        Task { await vm.load() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Deck.text)
                            .frame(width: 32, height: 32)
                            .background(Deck.card, in: Circle())
                            .overlay(Circle().stroke(Deck.rule))
                    }
                    .buttonStyle(.plain)
                    .disabled(vm.stage == .loading)
                }
            }
            Text("What should I eat?")
                .font(.deckSerif(36))
                .foregroundStyle(Deck.text)
                .tracking(-0.5)
            Text("AI reads your vault and remaining macros, then proposes makeable meals.")
                .font(.deckSans(13))
                .foregroundStyle(Deck.muted)
                .padding(.top, 4)
        }
        .padding(.top, 60)
    }

    private var mealTypeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mealTypes, id: \.self) { m in
                    DeckChip(label: m, isOn: vm.mealType == m) {
                        if vm.mealType != m {
                            vm.mealType = m
                            // Reset to idle so the user explicitly regenerates
                            // for the new meal type (no surprise API hits).
                            vm.suggestions = []
                            vm.stage = .idle
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - States

    private var idleState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(Deck.accent)
                .padding(.top, 40)
            Text("No suggestions yet")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text("Tap generate to ask the AI for \(vm.mealType) ideas using your vault and remaining macros.")
                .font(.deckSans(13))
                .foregroundStyle(Deck.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                Task { await vm.load() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Generate \(vm.mealType) ideas")
                }
                .font(.deckSans(15, weight: .medium))
                .foregroundStyle(Deck.ink)
                .padding(.vertical, 16)
                .padding(.horizontal, 22)
                .background(Deck.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            DeckCard(padding: 20) {
                VStack(alignment: .leading, spacing: 14) {
                    MonoCaption(text: "POST /api/meals/suggest", color: Deck.accent)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("→ reading vault…").font(.deckMono(12)).foregroundStyle(Deck.muted)
                        Text("→ \(Int(vm.remaining?.calories ?? 0)) kcal remaining").font(.deckMono(12)).foregroundStyle(Deck.muted)
                        Text("→ Dedalus · gpt-4o-mini · \(vm.mealType)").font(.deckMono(12)).foregroundStyle(Deck.muted)
                        Text("→ validating Pydantic schema…").font(.deckMono(12)).foregroundStyle(Deck.muted)
                    }
                    HStack(spacing: 10) {
                        ProgressView().tint(Deck.accent)
                        Text("thinking…").font(.deckMono(12)).foregroundStyle(Deck.muted)
                    }
                    .padding(.top, 6)
                }
            }
            ForEach(0..<3) { _ in skeletonCard }
        }
    }

    private var skeletonCard: some View {
        DeckCard {
            VStack(alignment: .leading, spacing: 8) {
                Capsule().fill(Deck.rule).frame(maxWidth: 200).frame(height: 18)
                Capsule().fill(Deck.rule.opacity(0.6)).frame(height: 10)
                Capsule().fill(Deck.rule.opacity(0.6)).frame(height: 10).padding(.trailing, 60)
            }
        }
        .opacity(0.4)
    }

    private var listState: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoCaption(text: "\(vm.suggestions.count) suggestions · \(vm.mealType)")
                .padding(.bottom, 4)
            if vm.suggestions.isEmpty {
                emptySuggestions
            } else {
                ForEach(Array(vm.suggestions.enumerated()), id: \.offset) { idx, s in
                    SuggestionCard(suggestion: s) {
                        openIndex = idx
                    }
                }
            }
        }
    }

    private var emptySuggestions: some View {
        DeckCard(padding: 22) {
            VStack(alignment: .leading, spacing: 8) {
                MonoCaption(text: "Empty result")
                Text("Nothing makeable from your vault.")
                    .font(.deckSerif(20))
                    .foregroundStyle(Deck.text)
                Text("Add ingredients to the vault, then try again.")
                    .font(.deckSans(13))
                    .foregroundStyle(Deck.muted)
            }
        }
    }

    private var errorState: some View {
        DeckCard(padding: 22) {
            VStack(alignment: .leading, spacing: 10) {
                MonoCaption(text: "⚠ Could not load", color: Deck.warning)
                Text("Suggestion request failed.")
                    .font(.deckSerif(20))
                    .foregroundStyle(Deck.text)
                Text(vm.errorMessage ?? "Unknown error.")
                    .font(.deckSans(13))
                    .foregroundStyle(Deck.muted)
                Button {
                    Task { await vm.load() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.deckSans(14, weight: .medium))
                    .foregroundStyle(Deck.ink)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Deck.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Deck.warning, lineWidth: 1)
        )
    }
}

private struct IndexedSuggestion: Identifiable {
    let index: Int
    let suggestion: MealSuggestion
    var id: String { "\(index)-\(suggestion.name)" }
}

// MARK: - Card

private struct SuggestionCard: View {
    let suggestion: MealSuggestion
    let onOpen: () -> Void

    private var bgColor: Color {
        suggestion.is_makeable ? Deck.card : Deck.cardMissing
    }
    private var ruleColor: Color {
        suggestion.is_makeable ? Deck.rule : Deck.ruleMissing
    }

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    if suggestion.is_makeable {
                        MonoCaption(
                            text: "Makeable · \(suggestion.ingredients.count) ingredients",
                            color: Deck.accent
                        )
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "cart.badge.questionmark")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Deck.accent.opacity(0.85))
                            MonoCaption(
                                text: "Missing \(suggestion.missing_items.count) · \(suggestion.ingredients.count) total",
                                color: Deck.accent.opacity(0.85)
                            )
                        }
                    }
                    Spacer()
                    Text("\(Int(suggestion.total_calories.rounded())) kcal")
                        .font(.deckMono(11))
                        .foregroundStyle(Deck.muted)
                }
                Text(suggestion.name)
                    .font(.deckSerif(24))
                    .foregroundStyle(Deck.text)
                    .multilineTextAlignment(.leading)
                Text(suggestion.description)
                    .font(.deckSans(13))
                    .foregroundStyle(Deck.muted)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)

                if !suggestion.is_makeable, !suggestion.missing_items.isEmpty {
                    Text("Need: " + suggestion.missing_items.joined(separator: ", "))
                        .font(.deckMono(11))
                        .foregroundStyle(Deck.text.opacity(0.85))
                        .lineLimit(2)
                        .padding(.top, 2)
                }

                HStack(spacing: 12) {
                    macroPill("p", value: suggestion.total_protein)
                    macroPill("c", value: suggestion.total_carbs)
                    macroPill("f", value: suggestion.total_fat)
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(bgColor, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ruleColor, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func macroPill(_ tag: String, value: Double) -> some View {
        HStack(spacing: 0) {
            Text("\(Int(value.rounded()))")
                .font(.deckMono(11))
                .foregroundStyle(Deck.text)
            Text(tag)
                .font(.deckMono(11))
                .foregroundStyle(Deck.muted)
        }
    }
}

// MARK: - Detail sheet

private struct SuggestionDetail: View {
    let suggestion: MealSuggestion
    let index: Int
    let isConfirming: Bool
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(Deck.text)
                        }
                        Spacer()
                        MonoCaption(text: "Suggestion \(index + 1)")
                        Spacer()
                        Color.clear.frame(width: 18)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(suggestion.name)
                            .font(.deckSerif(30))
                            .foregroundStyle(Deck.text)
                            .tracking(-0.5)
                        Text(suggestion.description)
                            .font(.deckSans(14))
                            .foregroundStyle(Deck.muted)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)

                    macroStrip
                        .padding(.horizontal, 24)
                        .padding(.top, 16)

                    ingredientsSection
                        .padding(.horizontal, 24)
                        .padding(.top, 24)

                    instructionsSection
                        .padding(.horizontal, 24)
                        .padding(.top, 26)
                        .padding(.bottom, 140)
                }
            }
            .background(Deck.bg)

            stickyCTA
        }
    }

    private var macroStrip: some View {
        DeckCard(padding: 16) {
            HStack(alignment: .top) {
                ForEach(macroEntries, id: \.0) { entry in
                    VStack(spacing: 4) {
                        Text("\(entry.1)")
                            .font(.deckSerif(22))
                            .foregroundStyle(Deck.text)
                        MonoCaption(text: entry.0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var macroEntries: [(String, Int)] {
        [
            ("kcal", Int(suggestion.total_calories.rounded())),
            ("P g",  Int(suggestion.total_protein.rounded())),
            ("C g",  Int(suggestion.total_carbs.rounded())),
            ("F g",  Int(suggestion.total_fat.rounded())),
        ]
    }

    private var ingredientsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoCaption(text: "Ingredients · from your vault")
            ForEach(suggestion.ingredients) { ing in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ing.name)
                            .font(.deckSerif(16))
                            .foregroundStyle(Deck.text)
                        Text("id:\(ing.food_item_id) · \(Int(ing.calories.rounded()))cal")
                            .font(.deckMono(10))
                            .foregroundStyle(Deck.muted)
                    }
                    Spacer()
                    Text("\(Int(ing.amount_grams.rounded()))g")
                        .font(.deckMono(13))
                        .foregroundStyle(Deck.accent)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
            }
        }
    }

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoCaption(text: "Steps")
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(suggestion.instructions.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(idx + 1).")
                            .font(.deckMono(13))
                            .foregroundStyle(Deck.muted)
                            .frame(width: 22, alignment: .leading)
                        Text(step)
                            .font(.deckSans(14))
                            .foregroundStyle(Deck.text)
                    }
                }
            }
        }
    }

    private var stickyCTA: some View {
        VStack {
            Button {
                onConfirm()
            } label: {
                HStack(spacing: 8) {
                    if isConfirming {
                        ProgressView().tint(Deck.ink)
                    } else {
                        Image(systemName: "checkmark")
                    }
                    Text(isConfirming ? "Logging…" : "Confirm & log this meal")
                        .font(.deckSans(15, weight: .medium))
                }
                .foregroundStyle(Deck.ink)
                .padding(.vertical, 16)
                .padding(.horizontal, 22)
                .frame(maxWidth: .infinity)
                .background(Deck.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isConfirming)
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .padding(.top, 12)
        }
        .background(
            Deck.bg
                .ignoresSafeArea(edges: .bottom)
                .overlay(Rectangle().fill(Deck.rule).frame(height: 1), alignment: .top)
        )
    }
}

#Preview {
    SuggestView()
        .preferredColorScheme(.dark)
}
