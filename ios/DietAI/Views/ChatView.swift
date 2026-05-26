import SwiftUI

struct ChatView: View {
    @ObservedObject private var vm = ChatViewModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingClearConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Deck.text)
                }
                Spacer()
                MonoCaption(text: "POST /api/chat")
                Spacer()
                Button { showingClearConfirm = true } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(vm.messages.isEmpty ? Deck.muted.opacity(0.4) : Deck.muted)
                }
                .disabled(vm.messages.isEmpty)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)

            VStack(alignment: .leading, spacing: 6) {
                Text("AI Coach.")
                    .font(.deckSerif(36))
                    .foregroundStyle(Deck.text)
                    .tracking(-0.5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 14)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if vm.messages.isEmpty {
                            emptyState
                                .padding(.top, 40)
                        }
                        ForEach(vm.messages) { msg in
                            MessageBubble(message: msg).id(msg.id)
                        }
                        if vm.isSending {
                            HStack(spacing: 8) {
                                ProgressView().tint(Deck.accent).scaleEffect(0.8)
                                Text("thinking…")
                                    .font(.deckMono(12))
                                    .foregroundStyle(Deck.muted)
                            }
                            .padding(.leading, 18)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .padding(.bottom, 12)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            inputBar
        }
        .background(Deck.bg.ignoresSafeArea())
        .alert("Error", isPresented: .constant(vm.errorMessage != nil), actions: {
            Button("OK") { vm.errorMessage = nil }
        }, message: {
            Text(vm.errorMessage ?? "")
        })
        .confirmationDialog("Clear chat history?", isPresented: $showingClearConfirm, titleVisibility: .visible) {
            Button("Clear", role: .destructive) { vm.clearHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 44))
                .foregroundStyle(Deck.accent)
            Text("Ask about your diet")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text("Try “What did I eat yesterday?” or “Suggest a high-protein lunch.”")
                .font(.deckSans(13))
                .foregroundStyle(Deck.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("Ask about your diet…", text: $vm.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
                .foregroundStyle(Deck.text)
                .tint(Deck.accent)
                .disabled(vm.isSending)

            Button {
                Task { await vm.send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Deck.ink)
                    .frame(width: 42, height: 42)
                    .background(Deck.accent, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending)
            .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 16)
        .background(Deck.bg)
        .overlay(Rectangle().fill(Deck.rule).frame(height: 1), alignment: .top)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == "user" { Spacer(minLength: 40) }
            Text(message.content)
                .font(.deckSans(14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    message.role == "user" ? Deck.accent : Deck.card,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(message.role == "user" ? .clear : Deck.rule)
                )
                .foregroundStyle(message.role == "user" ? Deck.ink : Deck.text)
            if message.role == "assistant" { Spacer(minLength: 40) }
        }
    }
}

#Preview {
    ChatView().preferredColorScheme(.dark)
}
