import SwiftUI

/// Conversion factors to grams. Liquids approximate at 1g/ml — fine for the
/// demo where most stuff is solid. The user can always switch to grams for
/// accuracy.
enum PortionUnit: String, CaseIterable, Identifiable {
    case g, oz, lb, kg, ml, cup
    var id: String { rawValue }
    var label: String {
        switch self {
        case .g: return "g"
        case .oz: return "oz"
        case .lb: return "lb"
        case .kg: return "kg"
        case .ml: return "ml"
        case .cup: return "cup"
        }
    }
    var gramsPerUnit: Double {
        switch self {
        case .g:   return 1.0
        case .oz:  return 28.3495
        case .lb:  return 453.592
        case .kg:  return 1000.0
        case .ml:  return 1.0     // assumes water density
        case .cup: return 240.0   // US cup ≈ 240 ml
        }
    }
}

struct PortionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let product: BarcodeProduct
    var onAdd: (Double) async -> Void   // total grams

    @State private var amountText: String
    @State private var unit: PortionUnit
    @State private var isAdding = false
    @FocusState private var amountFocused: Bool

    init(product: BarcodeProduct, onAdd: @escaping (Double) async -> Void) {
        self.product = product
        self.onAdd = onAdd
        // Default the input to a reasonable serving size if one was provided
        // by OFF, otherwise 100g.
        let defaultGrams = product.serving_size > 0 ? product.serving_size : 100
        _amountText = State(initialValue: PortionSheet.formatNumber(defaultGrams))
        _unit = State(initialValue: .g)
    }

    private var amountValue: Double {
        Double(amountText.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private var totalGrams: Double {
        amountValue * unit.gramsPerUnit
    }

    private var ratio: Double { totalGrams / 100.0 }

    private var computedKcal: Double { product.calories * ratio }
    private var computedProtein: Double { product.protein * ratio }
    private var computedCarbs: Double { product.carbs * ratio }
    private var computedFat: Double { product.fat * ratio }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    productHeader
                    amountControl
                    quickAmounts
                    computedMacros
                    perGramFootnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Deck.bg)
            .safeAreaInset(edge: .bottom) {
                addButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 18)
                    .padding(.top, 10)
                    .background(Deck.bg.ignoresSafeArea(edges: .bottom))
            }
            .navigationTitle("Add to vault")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(Deck.accent)
        .preferredColorScheme(.dark)
        .onAppear { amountFocused = true }
    }

    // MARK: - Sections

    private var productHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(product.name)
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
                .lineLimit(2)
            if let brand = product.brand, !brand.isEmpty {
                Text(brand)
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
    }

    private var amountControl: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoCaption(text: "Amount")
            HStack(spacing: 10) {
                TextField("0", text: $amountText)
                    .keyboardType(.decimalPad)
                    .focused($amountFocused)
                    .font(.deckSerif(28))
                    .foregroundStyle(Deck.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
                    .frame(maxWidth: .infinity)

                Menu {
                    ForEach(PortionUnit.allCases) { u in
                        Button(u.label) { unit = u }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(unit.label)
                            .font(.deckSerif(20))
                            .foregroundStyle(Deck.text)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Deck.muted)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
                }
                .menuStyle(.borderlessButton)
            }

            if unit != .g {
                Text("≈ \(PortionSheet.formatNumber(totalGrams))g total")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
        }
    }

    private var quickAmounts: some View {
        HStack(spacing: 8) {
            ForEach(quickPresets, id: \.0) { preset in
                Button {
                    amountText = preset.0
                    unit = preset.1
                } label: {
                    Text("\(preset.0) \(preset.1.label)")
                        .font(.deckMono(12))
                        .foregroundStyle(Deck.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Deck.card, in: Capsule())
                        .overlay(Capsule().stroke(Deck.rule))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var quickPresets: [(String, PortionUnit)] {
        switch unit {
        case .oz:        return [("1", .oz), ("4", .oz), ("8", .oz), ("16", .oz)]
        case .ml, .cup:  return [("100", .ml), ("250", .ml), ("1", .cup), ("2", .cup)]
        case .lb, .kg:   return [("1", .lb), ("0.5", .kg), ("1", .kg)]
        case .g:         return [("50", .g), ("100", .g), ("200", .g), ("500", .g)]
        }
    }

    private var computedMacros: some View {
        VStack(spacing: 10) {
            HStack {
                MonoCaption(text: "Per \(PortionSheet.formatNumber(totalGrams))g")
                Spacer()
            }
            HStack(alignment: .top, spacing: 10) {
                MacroBox(label: "kcal", value: Int(computedKcal.rounded()), color: Deck.accent)
                MacroBox(label: "P g",  value: Int(computedProtein.rounded()), color: Deck.proteinBar)
                MacroBox(label: "C g",  value: Int(computedCarbs.rounded()), color: Deck.carbsBar)
                MacroBox(label: "F g",  value: Int(computedFat.rounded()), color: Deck.fatBar)
            }
        }
    }

    private var perGramFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            MonoCaption(text: "Per 100g (from OFF)")
            Text("\(Int(product.calories.rounded())) kcal · \(Int(product.protein.rounded()))p · \(Int(product.carbs.rounded()))c · \(Int(product.fat.rounded()))f")
                .font(.deckMono(11))
                .foregroundStyle(Deck.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Deck.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var addButton: some View {
        Button {
            Task {
                isAdding = true
                await onAdd(totalGrams)
                isAdding = false
                dismiss()
            }
        } label: {
            HStack(spacing: 8) {
                if isAdding {
                    ProgressView().tint(Deck.ink)
                } else {
                    Image(systemName: "plus")
                }
                Text(isAdding ? "Adding…" : "Add \(PortionSheet.formatNumber(totalGrams))g to vault")
                    .font(.deckSans(15, weight: .medium))
            }
            .foregroundStyle(Deck.ink)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Deck.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isAdding || totalGrams <= 0)
        .opacity(totalGrams <= 0 ? 0.5 : 1)
    }

    // MARK: - Helpers

    static func formatNumber(_ d: Double) -> String {
        if d == d.rounded() {
            return String(Int(d))
        } else {
            return String(format: "%.1f", d)
        }
    }
}

private struct MacroBox: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            MonoCaption(text: label)
            Capsule().fill(color).frame(height: 3)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
    }
}
