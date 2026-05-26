import Foundation
import Combine

@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var progress: DailyProgress?
    @Published var isLoading = false
    @Published var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            progress = try await APIClient.shared.dashboard()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
