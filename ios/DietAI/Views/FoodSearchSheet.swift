import SwiftUI

/// Search the local Open Food Facts dataset and add a result to the vault.
struct FoodSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onAdded: () -> Void = {}

    @State private var query: String = ""
    @State private var results: [BarcodeProduct] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var task: Task<Void, Never>?
    @State private var portioning: BarcodeProduct?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                    .padding(.horizontal, 18)
                    .padding(.top, 14)

                contentBody
            }
            .background(Deck.bg)
            .navigationTitle("Find food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Search failed", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: {
                Text(errorMessage ?? "")
            })
            .sheet(item: $portioning) { product in
                PortionSheet(product: product) { totalGrams in
                    await add(product, totalGrams: totalGrams)
                }
            }
        }
        .tint(Deck.accent)
        .preferredColorScheme(.dark)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Deck.muted)
            TextField("Search foods…", text: $query)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onSubmit { runSearch() }
                .onChange(of: query) { _, _ in scheduleSearch() }
                .foregroundStyle(Deck.text)
                .tint(Deck.accent)
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Deck.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
    }

    @ViewBuilder
    private var contentBody: some View {
        if isSearching && results.isEmpty {
            VStack(spacing: 8) {
                ProgressView().tint(Deck.accent)
                Text("Searching the food database…")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if query.trimmingCharacters(in: .whitespaces).isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(Deck.muted)
                Text("Search 4M+ foods")
                    .font(.deckSerif(20))
                    .foregroundStyle(Deck.text)
                Text("Type a name or brand. Results come from the bundled Open Food Facts dataset — no internet needed.")
                    .font(.deckSans(13))
                    .foregroundStyle(Deck.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
        } else if results.isEmpty {
            VStack(spacing: 8) {
                Text("No matches")
                    .font(.deckSerif(20))
                    .foregroundStyle(Deck.text)
                Text("Try a shorter or different query.")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(results, id: \.barcode) { item in
                        ResultRow(product: item) {
                            portioning = item
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            }
        }
    }

    private func scheduleSearch() {
        task?.cancel()
        let q = query
        task = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            if q == query { runSearch() }
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else {
            results = []
            return
        }
        isSearching = true
        Task {
            defer { isSearching = false }
            do {
                results = try await APIClient.shared.searchFoods(query: q)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func add(_ product: BarcodeProduct, totalGrams: Double) async {
        do {
            _ = try await APIClient.shared.addToVaultFromSearch(product, totalGrams: totalGrams)
            onAdded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ResultRow: View {
    let product: BarcodeProduct
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.name)
                        .font(.deckSerif(16))
                        .foregroundStyle(Deck.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let brand = product.brand, !brand.isEmpty {
                        Text(brand)
                            .font(.deckMono(10))
                            .foregroundStyle(Deck.muted)
                    }
                    Text("\(Int(product.calories.rounded())) kcal · \(Int(product.protein.rounded()))p · \(Int(product.carbs.rounded()))c · \(Int(product.fat.rounded()))f / 100g")
                        .font(.deckMono(10))
                        .foregroundStyle(Deck.muted)
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Deck.ink)
                    .frame(width: 36, height: 36)
                    .background(Deck.accent, in: Circle())
            }
            .padding(14)
            .background(Deck.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Deck.rule))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    FoodSearchSheet()
}
