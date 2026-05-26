import SwiftUI

struct MacroRing: View {
    let value: Double
    let goal: Double
    var label: String = "REMAINING"
    var sub: String? = "kcal · today"
    var size: CGFloat = 240
    var stroke: CGFloat = 14
    var color: Color = Deck.accent
    var trackColor: Color = Deck.track

    @State private var animPct: Double = 0

    private var pct: Double { max(0, min(1, value / max(goal, 1))) }
    private var remaining: Int { Int((goal - value).rounded()) }

    var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: stroke)

            Circle()
                .trim(from: 0, to: animPct)
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.0, dampingFraction: 0.85), value: animPct)

            VStack(spacing: 6) {
                Text("\(remaining)")
                    .font(.deckSerif(size * 0.32))
                    .foregroundStyle(Deck.text)
                MonoCaption(text: label)
                if let sub = sub {
                    Text(sub)
                        .font(.deckMono(11))
                        .foregroundStyle(Deck.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            // Slight delay so the ring animates in.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { animPct = pct }
        }
        .onChange(of: pct) { _, newValue in animPct = newValue }
    }
}

struct MacroBar: View {
    let label: String
    let value: Double
    let goal: Double
    var color: Color

    private var pct: Double { goal > 0 ? min(value / goal, 1.0) : 0 }

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                MonoCaption(text: label)
                Spacer()
                HStack(spacing: 0) {
                    Text("\(Int(value.rounded()))")
                        .font(.deckMono(12))
                        .foregroundStyle(Deck.text)
                    Text("/\(Int(goal.rounded()))g")
                        .font(.deckMono(12))
                        .foregroundStyle(Deck.muted)
                }
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Deck.track)
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * pct)
                        .animation(.spring(response: 1.0, dampingFraction: 0.85), value: pct)
                }
            }
            .frame(height: 4)
        }
    }
}
