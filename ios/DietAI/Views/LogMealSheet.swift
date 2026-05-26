import SwiftUI

/// Sheet for logging a meal — either from the vault or as a manual entry.
/// When `targetDate`/`targetHour` are provided, the meal is logged at that time
/// (used by the calendar timeline). Otherwise, "now" is used.
struct LogMealSheet: View {
    @Environment(\.dismiss) private var dismiss

    let targetDate: Date?
    let targetHour: Int?
    var onLogged: () -> Void = {}

    @State private var vault: [FoodItem] = []
    @State private var isLoadingVault = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    enum Mode: String, CaseIterable, Identifiable {
        case fromVault = "From vault"
        case manual = "Manual"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .fromVault

    // From vault
    @State private var selectedItemID: Int?
    @State private var servings: String = "1"

    // Manual
    @State private var name = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""

    var body: some View {
        NavigationStack {
            Form {
                if let label = targetTimeLabel {
                    Section {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Deck.accent)
                            Text(label)
                                .font(.deckMono(12))
                                .foregroundStyle(Deck.text)
                        }
                    } header: {
                        Text("EATEN AT")
                            .font(.deckMono(10))
                            .tracking(1.4)
                    }
                }

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Deck.bg)

                switch mode {
                case .fromVault:
                    Section {
                        if isLoadingVault {
                            ProgressView().tint(Deck.accent)
                        } else if vault.isEmpty {
                            Text("Vault is empty.")
                                .foregroundStyle(Deck.muted)
                        } else {
                            Picker("Food", selection: $selectedItemID) {
                                Text("Choose…").tag(Int?.none)
                                ForEach(vault) { item in
                                    Text(item.name).tag(Int?.some(item.id))
                                }
                            }
                            TextField("Servings", text: $servings)
                                .keyboardType(.decimalPad)
                        }
                    } header: {
                        Text("PICK FROM VAULT")
                            .font(.deckMono(10))
                            .tracking(1.4)
                    }

                case .manual:
                    Section {
                        TextField("Meal name", text: $name)
                        TextField("Calories", text: $calories).keyboardType(.decimalPad)
                        TextField("Protein (g)", text: $protein).keyboardType(.decimalPad)
                        TextField("Carbs (g)", text: $carbs).keyboardType(.decimalPad)
                        TextField("Fat (g)", text: $fat).keyboardType(.decimalPad)
                    } header: {
                        Text("MEAL")
                            .font(.deckMono(10))
                            .tracking(1.4)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Deck.bg)
            .navigationTitle("Log meal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") {
                        Task { await submit() }
                    }
                    .disabled(!isValid || isSubmitting)
                }
            }
            .task { await loadVault() }
            .alert("Could not log", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
        .tint(Deck.accent)
    }

    // MARK: - Helpers

    private var targetTimeLabel: String? {
        guard let date = targetDate, let hour = targetHour else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d · h a"
        return f.string(from: Calendar.current.date(from: comps) ?? date)
    }

    private var isValid: Bool {
        switch mode {
        case .fromVault: return selectedItemID != nil
        case .manual:    return !name.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private func loadVault() async {
        isLoadingVault = true
        do {
            vault = try await APIClient.shared.vault()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingVault = false
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }

        var payload = MealLogCreate()

        switch mode {
        case .fromVault:
            guard let id = selectedItemID else { return }
            let chosen = vault.first { $0.id == id }
            payload.food_item_id = id
            payload.name = chosen?.name
            payload.amount = chosen?.serving_size ?? 100
            payload.servings = Double(servings) ?? 1

        case .manual:
            payload.name = name.trimmingCharacters(in: .whitespaces)
            payload.amount = 100
            payload.servings = 1
            payload.calories = Double(calories) ?? 0
            payload.protein = Double(protein) ?? 0
            payload.carbs = Double(carbs) ?? 0
            payload.fat = Double(fat) ?? 0
        }

        if let iso = isoTimestamp() {
            payload.eaten_at = iso
        }

        do {
            _ = try await APIClient.shared.logMeal(payload)
            // Vault may have been decremented (vault-source logs) — let
            // every tab know so it can pull fresh state.
            NotificationCenter.default.post(name: .mealsChanged, object: nil)
            onLogged()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isoTimestamp() -> String? {
        guard let date = targetDate, let hour = targetHour else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = hour
        comps.minute = 0
        comps.second = 0
        guard let resolved = Calendar.current.date(from: comps) else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: resolved)
    }
}
