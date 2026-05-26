import SwiftUI

// MARK: - Deck palette (matches the design canvas Deck theme)

enum Deck {
    static let bg     = Color(red: 0x0E/255, green: 0x14/255, blue: 0x11/255) // #0E1411
    static let card   = Color(red: 0x15/255, green: 0x20/255, blue: 0x1A/255) // #15201A
    static let text   = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE3/255) // #F4EFE3
    static let muted  = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE3/255).opacity(0.55)
    static let rule   = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE3/255).opacity(0.10)
    static let track  = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE3/255).opacity(0.10)
    static let accent = Color(red: 0xC8/255, green: 0xFF/255, blue: 0x4F/255) // #C8FF4F
    static let ink    = Color(red: 0x0E/255, green: 0x14/255, blue: 0x11/255) // accent foreground

    // Macro accents from the design
    static let proteinBar = Color(red: 0xF4/255, green: 0xEF/255, blue: 0xE3/255) // off-white
    static let carbsBar   = accent
    static let fatBar     = Color(red: 0xE0/255, green: 0x7A/255, blue: 0x5F/255) // #E07A5F (terracotta)
    static let warning    = fatBar

    /// Used for "missing ingredients" suggestion cards — a deeper, more
    /// saturated green that signals the user can't actually make this meal
    /// without a trip to the store.
    static let cardMissing = Color(red: 0x0A/255, green: 0x2A/255, blue: 0x1A/255) // #0A2A1A
    static let ruleMissing = Color(red: 0xC8/255, green: 0xFF/255, blue: 0x4F/255).opacity(0.18)
}

// MARK: - Typography

extension Font {
    /// Display — serif (New York), used for hero numbers and headlines.
    static func deckSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Mono — monospaced labels and meta.
    static func deckMono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// Sans — body, used for primary copy.
    static func deckSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }
}

// MARK: - Mono caption helper

struct MonoCaption: View {
    let text: String
    var color: Color = Deck.muted
    var size: CGFloat = 10

    var body: some View {
        Text(text.uppercased())
            .font(.deckMono(size))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

// MARK: - Card surface

struct DeckCard<Content: View>: View {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .background(Deck.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Deck.rule, lineWidth: 1)
            )
    }
}

// MARK: - Liquid Glass surface

/// Applies Apple's Liquid Glass material to a view. On iOS 26+ this uses the
/// real `.glassEffect()` modifier (translucent, color-reflective, reactive
/// to touch). On iOS 17/18 it falls back to `.ultraThinMaterial`, which
/// gives a similar blurred, translucent look.
struct LiquidGlassBackground<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.modifier(GlassEffectModifier(shape: shape, interactive: interactive, tint: tint))
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
    }
}

@available(iOS 26.0, *)
private struct GlassEffectModifier<S: Shape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        // Compose the Glass variant with optional tint/interactive flags.
        var glass: Glass = .regular
        if let tint = tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return content.glassEffect(glass, in: shape)
    }
}

extension View {
    /// Applies the standard Liquid Glass surface in the given shape.
    func liquidGlass<S: Shape>(
        in shape: S,
        interactive: Bool = false,
        tint: Color? = nil
    ) -> some View {
        modifier(LiquidGlassBackground(shape: shape, interactive: interactive, tint: tint))
    }
}

/// Wraps content in a `GlassEffectContainer` on iOS 26+ so multiple glass
/// surfaces can morph and merge. On older systems it just passes the content
/// through unchanged.
struct LiquidGlassGroup<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Pill / chip

struct DeckChip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(.deckMono(11))
                .tracking(1.2)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .foregroundStyle(isOn ? Deck.ink : Deck.text)
                .background(isOn ? Deck.accent : .clear, in: Capsule())
                .overlay(Capsule().stroke(isOn ? Deck.accent : Deck.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
