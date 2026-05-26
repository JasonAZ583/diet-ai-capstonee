import SwiftUI

struct HistoryView: View {
    @StateObject private var vm = HistoryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                if !vm.dayBuckets.isEmpty {
                    sparkline(buckets: vm.dayBuckets.prefix(7).reversed().map { $0 })
                        .padding(.horizontal, 24)
                        .padding(.top, 20)
                }

                if vm.isLoading && vm.meals.isEmpty {
                    ProgressView()
                        .tint(Deck.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if vm.dayBuckets.isEmpty {
                    DeckCard(padding: 22) {
                        VStack(alignment: .leading, spacing: 6) {
                            MonoCaption(text: "No history yet")
                            Text("Log a meal to start your history.")
                                .font(.deckSerif(20))
                                .foregroundStyle(Deck.text)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                } else {
                    VStack(spacing: 10) {
                        ForEach(vm.dayBuckets) { bucket in
                            DayRowView(bucket: bucket, goal: 2000)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 110)
                }
            }
        }
        .background(Deck.bg)
        .refreshable { await vm.load() }
        .task { await vm.load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MonoCaption(text: "GET /api/meals/history")
            Text("Last 7 days.")
                .font(.deckSerif(36))
                .foregroundStyle(Deck.text)
                .tracking(-0.5)
        }
        .padding(.top, 60)
    }

    private func sparkline(buckets: [DayBucket]) -> some View {
        let maxCal = max(2400.0, buckets.map(\.calories).max() ?? 2400.0)
        return DeckCard {
            VStack(alignment: .leading, spacing: 12) {
                MonoCaption(text: "Calories vs goal")
                GeometryReader { geo in
                    let count = max(buckets.count, 1)
                    let barW = (geo.size.width - CGFloat(count + 1) * 6) / CGFloat(count)
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(Array(buckets.enumerated()), id: \.offset) { idx, b in
                            let h = (b.calories / maxCal) * geo.size.height
                            let isOver = b.calories > 2000
                            VStack { Spacer() }
                                .frame(width: max(barW, 12), height: max(h, 4))
                                .background(isOver ? Deck.warning : Deck.accent, in: RoundedRectangle(cornerRadius: 3))
                                .opacity(idx == buckets.count - 1 ? 1 : 0.7)
                        }
                    }
                }
                .frame(height: 90)
                HStack {
                    ForEach(buckets) { b in
                        Text(shortDay(from: b.date))
                            .font(.deckMono(10))
                            .foregroundStyle(Deck.muted)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func shortDay(from iso: String) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: iso) else { return iso }
        let out = DateFormatter(); out.dateFormat = "EEE"
        return out.string(from: d)
    }
}

private struct DayRowView: View {
    let bucket: DayBucket
    let goal: Double

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(formattedDate)
                    .font(.deckSerif(17))
                    .foregroundStyle(Deck.text)
                Text("\(bucket.mealCount) meals · \(Int((bucket.calories / goal * 100).rounded()))% of goal")
                    .font(.deckMono(11))
                    .foregroundStyle(Deck.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(Int(bucket.calories.rounded()))")
                    .font(.deckSerif(22))
                    .foregroundStyle(bucket.calories > goal ? Deck.warning : Deck.text)
                Text("/\(Int(goal)) kcal")
                    .font(.deckMono(10))
                    .foregroundStyle(Deck.muted)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
    }

    private var formattedDate: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: bucket.date) else { return bucket.date }
        let out = DateFormatter(); out.dateFormat = "EEE · MMM d"
        return out.string(from: d)
    }
}

#Preview {
    HistoryView()
        .preferredColorScheme(.dark)
}
