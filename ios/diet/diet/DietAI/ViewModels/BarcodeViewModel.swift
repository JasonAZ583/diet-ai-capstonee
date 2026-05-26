import Foundation
import Combine

@MainActor
final class BarcodeViewModel: ObservableObject {
    enum Stage {
        case scanning
        case lookingUp(code: String)
        case found(BarcodeProduct)
        case notFound(code: String)
        case adding
        case added(FoodItem)
        case error(String)
    }

    @Published var stage: Stage = .scanning

    func onScan(code: String) async {
        stage = .lookingUp(code: code)
        do {
            let response = try await APIClient.shared.lookupBarcode(code)
            if let product = response.product, response.found {
                stage = .found(product)
            } else {
                stage = .notFound(code: code)
            }
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    func addCurrent(quantity: Double) async {
        guard case .found(let product) = stage, let code = product.barcode else { return }
        let qty = max(0.01, quantity)
        stage = .adding
        do {
            let item = try await APIClient.shared.addFromBarcode(code, quantity: qty)
            stage = .added(item)
        } catch {
            stage = .error(error.localizedDescription)
        }
    }

    func resetToScan() {
        stage = .scanning
    }
}
