import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .badStatus(let code, let body): return "HTTP \(code): \(body)"
        case .decoding(let err): return "Decoding error: \(err.localizedDescription)"
        case .transport(let err): return "Network error: \(err.localizedDescription)"
        }
    }
}

actor APIClient {
    static let shared = APIClient()

    /// Resolved at runtime so the same build works on Simulator and device.
    ///
    /// Lookup order:
    /// 1. `DIETAI_API_BASE_URL` Info.plist key (set per-config in Xcode)
    /// 2. `localhost:8000` on the Simulator
    /// 3. `LAN_BASE_URL` (your Mac's LAN IP) on a real device
    ///
    /// To change the device IP, edit `LAN_BASE_URL` below or set the Info.plist key.
    private static let LAN_BASE_URL = "http://192.168.1.165:8000"

    private let baseURL: URL = {
        if let override = Bundle.main.object(forInfoDictionaryKey: "DIETAI_API_BASE_URL") as? String,
           let url = URL(string: override) {
            return url
        }
        #if targetEnvironment(simulator)
        return URL(string: "http://localhost:8000")!
        #else
        return URL(string: APIClient.LAN_BASE_URL)!
        #endif
    }()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    // MARK: - Generic request

    private func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: Data? = nil
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw APIError.badStatus(code, bodyStr)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    private struct EmptyResponse: Decodable {}

    private func send(
        _ path: String,
        method: String,
        body: Data? = nil
    ) async throws {
        let _: EmptyResponse = try await request(path, method: method, body: body)
    }

    // MARK: - Endpoints

    func dashboard(date: Date? = nil) async throws -> DailyProgress {
        var q: [URLQueryItem] = []
        if let date = date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            q.append(URLQueryItem(name: "target_date", value: f.string(from: date)))
        }
        return try await request("/api/dashboard", query: q)
    }

    func lookupBarcode(_ code: String) async throws -> BarcodeResponse {
        try await request("/api/barcode/\(code)")
    }

    func searchFoods(query: String, limit: Int = 25) async throws -> [BarcodeProduct] {
        let q = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        return try await request("/api/foods/search", query: q)
    }

    /// Add a found product to the vault. Macros from OFF are per-100g. We
    /// keep serving_size at 100g and store quantity = totalGrams / 100, so
    /// every serving in the vault represents 100g of the food.
    func addToVaultFromSearch(_ product: BarcodeProduct, totalGrams: Double) async throws -> FoodItem {
        let qty = max(0.01, totalGrams / 100.0)
        let item = FoodItemCreate(
            name: product.name,
            brand: product.brand,
            calories: product.calories,
            protein: product.protein,
            carbs: product.carbs,
            fat: product.fat,
            fiber: product.fiber,
            quantity: qty,
            serving_size: 100,
            unit: "g"
        )
        let data = try encoder.encode(item)
        return try await request("/api/vault", method: "POST", body: data)
    }

    func addFromBarcode(_ code: String, quantity: Double = 1) async throws -> FoodItem {
        let q = [URLQueryItem(name: "quantity", value: String(quantity))]
        return try await request("/api/barcode/\(code)/add", method: "POST", query: q)
    }

    func vault() async throws -> [FoodItem] {
        try await request("/api/vault")
    }

    func addFoodItem(_ item: FoodItemCreate) async throws -> FoodItem {
        let data = try encoder.encode(item)
        return try await request("/api/vault", method: "POST", body: data)
    }

    func deleteVaultItem(id: Int) async throws {
        // Backend returns {"message": "..."} — decode loosely.
        struct Ack: Decodable { let message: String? }
        let _: Ack = try await request("/api/vault/\(id)", method: "DELETE")
    }

    func meals(date: Date? = nil) async throws -> [MealLog] {
        var q: [URLQueryItem] = []
        if let date = date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            q.append(URLQueryItem(name: "target_date", value: f.string(from: date)))
        }
        return try await request("/api/meals", query: q)
    }

    func logMeal(_ meal: MealLogCreate) async throws -> MealLog {
        let data = try encoder.encode(meal)
        return try await request("/api/meals", method: "POST", body: data)
    }

    func deleteMeal(id: Int) async throws {
        struct Ack: Decodable { let message: String? }
        let _: Ack = try await request("/api/meals/\(id)", method: "DELETE")
    }

    func mealHistory(limit: Int = 30) async throws -> [MealLog] {
        try await request("/api/meals/history", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func suggestMeals(numSuggestions: Int = 3, mealType: String? = nil) async throws -> MealSuggestionsResponse {
        var q: [URLQueryItem] = [URLQueryItem(name: "num_suggestions", value: String(numSuggestions))]
        if let mealType = mealType { q.append(URLQueryItem(name: "meal_type", value: mealType)) }
        return try await request("/api/meals/suggest", query: q)
    }

    func confirmMeal(_ request: ConfirmMealRequest) async throws -> MealLog {
        let data = try encoder.encode(request)
        return try await self.request("/api/meals/confirm", method: "POST", body: data)
    }

    func chat(message: String, history: [ChatMessage]) async throws -> ChatResponse {
        let payload = ChatRequest(message: message, history: history)
        let data = try encoder.encode(payload)
        return try await request("/api/chat", method: "POST", body: data)
    }
}
