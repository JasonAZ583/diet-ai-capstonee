import Foundation
import Combine

@MainActor
final class ChatViewModel: ObservableObject {
    /// Shared instance so chat history survives the sheet being dismissed
    /// and reopened. Persisted to disk via `save()` after every change.
    static let shared = ChatViewModel()

    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending: Bool = false
    @Published var errorMessage: String?

    private let storeURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("dietai-chat.json")
    }()

    init() { load() }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        draft = ""

        let userMsg = ChatMessage(role: "user", content: text)
        messages.append(userMsg)
        save()
        isSending = true

        do {
            // Backend expects history WITHOUT the latest user message.
            let history = messages.dropLast().map {
                ChatMessage(role: $0.role, content: $0.content)
            }
            let response = try await APIClient.shared.chat(
                message: text,
                history: Array(history)
            )
            messages.append(ChatMessage(role: "assistant", content: response.reply))
            save()

            if let logged = response.logged, !logged.isEmpty {
                // The AI just persisted meal(s) — tell the dashboard and
                // calendar to pull the new state.
                NotificationCenter.default.post(name: .mealsChanged, object: nil)
            }
        } catch {
            errorMessage = error.localizedDescription
            // Roll the user message back so they can retry.
            if messages.last?.role == "user" { messages.removeLast() }
            save()
            draft = text
        }
        isSending = false
    }

    func clearHistory() {
        messages.removeAll()
        save()
    }

    // MARK: - Persistence

    private func save() {
        do {
            let data = try JSONEncoder().encode(messages)
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            // Non-fatal — chat history just won't survive next launch.
            print("ChatViewModel save failed: \(error)")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        if let restored = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            messages = restored
        }
    }
}

extension Notification.Name {
    /// Fired when meals were created/deleted out-of-band (e.g. by chat tool
    /// calls) so other views know to reload.
    static let mealsChanged = Notification.Name("DietAI.mealsChanged")
}
