import SwiftUI

private enum VaultFilter: String, CaseIterable, Identifiable {
    case all, proteins, carbs, veg, fats, pantry
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "All"
        case .proteins: return "Protein"
        case .carbs: return "Carbs"
        case .veg: return "Veg"
        case .fats: return "Fats"
        case .pantry: return "Pantry"
        }
    }
}

struct VaultView: View {
    @StateObject private var vm = VaultViewModel()
    @State private var showingAdd = false
    @State private var showingSearch = false
    @State private var filter: VaultFilter = .all

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 24)
                        .padding(.top, 8)

                    if vm.items.isEmpty && !vm.isLoading {
                        EmptyVaultCard {
                            showingAdd = true
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                    } else {
                        chips
                            .padding(.top, 20)

                        VStack(spacing: 10) {
                            ForEach(filtered) { item in
                                VaultRowView(item: item) {
                                    Task { await vm.delete(item) }
                                }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 12)
                        .padding(.bottom, 110)
                    }

                    if vm.isLoading && vm.items.isEmpty {
                        ProgressView()
                            .tint(Deck.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
            }
            .background(Deck.bg)

            if !vm.items.isEmpty {
                Button {
                    showingAdd = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Deck.ink)
                        .frame(width: 56, height: 56)
                        .background(Deck.accent, in: Circle())
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 8)
                }
                .padding(.trailing, 22)
                .padding(.bottom, 88)
                .buttonStyle(.plain)
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .onReceive(NotificationCenter.default.publisher(for: .mealsChanged)) { _ in
            Task { await vm.load() }
        }
        .sheet(isPresented: $showingAdd) {
            AddFoodSheet { newItem in
                Task { await vm.add(newItem) }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showingSearch) {
            FoodSearchSheet {
                Task { await vm.load() }
            }
        }
        .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: {
            Text(vm.errorMessage ?? "")
        })
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                MonoCaption(text: "Vault · \(vm.items.count) items")
                Text("What I have.")
                    .font(.deckSerif(36))
                    .foregroundStyle(Deck.text)
                    .tracking(-0.5)
            }

            Button { showingSearch = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Deck.muted)
                    Text("Search foods…")
                        .font(.deckSans(14))
                        .foregroundStyle(Deck.muted)
                    Spacer()
                    MonoCaption(text: "OFF · 4M", color: Deck.accent)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 60)
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(VaultFilter.allCases) { f in
                    DeckChip(label: f.label, isOn: filter == f) { filter = f }
                }
            }
            .padding(.horizontal, 24)
        }
    }

    private var filtered: [FoodItem] {
        guard filter != .all else { return vm.items }
        return vm.items.filter { item in
            let c = max(item.calories, 1)
            switch filter {
            case .proteins: return item.protein / c > 0.08
            case .carbs:    return item.carbs / c > 0.06
            case .veg:      return item.calories < 50
            case .fats:     return item.fat / c > 0.08
            case .pantry:   return true
            case .all:      return true
            }
        }
    }
}

// MARK: - Vault row

private struct VaultRowView: View {
    let item: FoodItem
    let onDelete: () -> Void
    @State private var qty: Double = 0
    @State private var confirmingDelete = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name)
                        .font(.deckSerif(17))
                        .foregroundStyle(Deck.text)
                        .lineLimit(1)
                    if let brand = item.brand, !brand.isEmpty {
                        Text("· \(brand)")
                            .font(.deckMono(10))
                            .foregroundStyle(Deck.muted)
                            .lineLimit(1)
                    }
                }
                Text("\(Int(item.calories))cal · \(Int(item.protein))p · \(Int(item.carbs))c · \(Int(item.fat))f / \(Int(item.serving_size))\(item.unit)")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
            Spacer()

            HStack(spacing: 8) {
                // Qty stepper
                HStack(spacing: 6) {
                    Button {
                        qty = max(0, (qty - 0.5).rounded(toPlaces: 1))
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Deck.text)
                            .frame(width: 26, height: 26)
                    }
                    Text(String(format: "%.1f", qty))
                        .font(.deckMono(13))
                        .foregroundStyle(Deck.text)
                        .frame(minWidth: 30)
                    Button {
                        qty = (qty + 0.5).rounded(toPlaces: 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Deck.text)
                            .frame(width: 26, height: 26)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Deck.bg, in: Capsule())
                .overlay(Capsule().stroke(Deck.rule))
                .buttonStyle(.plain)

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
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        }
        .onAppear { qty = item.quantity }
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}

// MARK: - Empty state

private struct EmptyVaultCard: View {
    let onAdd: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.system(size: 36))
                    .foregroundStyle(Deck.muted)
                Text("Empty vault")
                    .font(.deckSerif(22))
                    .foregroundStyle(Deck.text)
                Text("Add an item to start. The AI engine needs ingredients to suggest meals.")
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

            ActionTile(icon: "plus", label: "Add manually", action: onAdd)
        }
    }
}

// MARK: - Add sheet

struct AddFoodSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdd: (FoodItemCreate) -> Void

    @State private var name = ""
    @State private var brand = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var quantity = "1"
    @State private var servingSize = "100"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                } header: { Text("FOOD") }

                Section {
                    TextField("Calories", text: $calories).keyboardType(.decimalPad)
                    TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                    TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad)
                    TextField("Fat (g)", text: $fat).keyboardType(.decimalPad)
                } header: { Text("PER \(servingSize)g") }

                Section {
                    TextField("Quantity", text: $quantity).keyboardType(.decimalPad)
                    TextField("Serving size (g)", text: $servingSize).keyboardType(.decimalPad)
                } header: { Text("STOCK") }
            }
            .scrollContentBackground(.hidden)
            .background(Deck.bg)
            .navigationTitle("Add Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(FoodItemCreate(
                            name: name,
                            brand: brand.isEmpty ? nil : brand,
                            calories: Double(calories) ?? 0,
                            protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0,
                            fat: Double(fat) ?? 0,
                            quantity: Double(quantity) ?? 1,
                            serving_size: Double(servingSize) ?? 100
                        ))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .tint(Deck.accent)
    }
}

#Preview {
    VaultView()
        .preferredColorScheme(.dark)
}
