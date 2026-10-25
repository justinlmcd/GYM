import Foundation

nonisolated enum APIError: LocalizedError {
    case signedOut
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .signedOut: return "Signed out. Sign in again."
        case .server(_, let message): return message
        }
    }

    // Worth keeping a set queued and retrying later: no connection, or the server hiccuped.
    static func isTransient(_ error: Error) -> Bool {
        if error is URLError { return true }
        if case .server(let code, _) = error as? APIError { return code >= 500 || code == 429 }
        return false
    }
}

nonisolated private struct TokenResponse: Decodable {
    let access_token: String
    let refresh_token: String
    let expires_in: Double
}

// Talks to Supabase Auth and the REST API directly, with the same login as the web app.
// Row-level security in setup.sql fills in user_id and keeps rows private.
actor Supabase {
    private(set) var session: Session?
    private let baseURL: URL
    private let key: String

    // The URL and key are handed in from the main actor, so this works however Xcode isolates Config by default.
    init(url: URL, key: String) {
        baseURL = url
        self.key = key
        session = Keychain.load()
    }

    var email: String? { session?.email }

    func signIn(email: String, password: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        try await requestToken(grantType: "password", body: body, email: email)
    }

    func signOut() {
        session = nil
        Keychain.clear()
    }

    func exercises() async throws -> [Exercise] {
        try await get("exercises?select=id,name,unit,target_sets,target_reps,increment&archived=eq.false&order=name")
    }

    // Recent sets, enough to suggest each exercise's next weight. Pages through the 1000-row limit.
    func sets(since day: String) async throws -> [LoggedSet] {
        var all: [LoggedSet] = []
        let page = 1000
        while true {
            let rows: [LoggedSet] = try await get(
                "sets?select=id,exercise_id,performed_on,set_no,weight,reps&performed_on=gte.\(day)&order=performed_on.desc,id&limit=\(page)&offset=\(all.count)")
            all += rows
            if rows.count < page { return all }
        }
    }

    func workouts() async throws -> [Workout] {
        try await get("workouts?select=id,name,exercise_ids&order=name")
    }

    func cardio(on day: String) async throws -> [CardioSession] {
        try await get("cardio?select=id,performed_on,kind,minutes,speed,speed_unit,calories&performed_on=eq.\(day)&order=created_at")
    }

    // Ignore-duplicates on the primary key makes a retry of the same row harmless.
    func insert<T: Encodable & Sendable>(_ row: T, into table: String) async throws {
        var req = try await request(table, method: "POST")
        req.setValue("return=minimal,resolution=ignore-duplicates", forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONEncoder().encode([row])
        _ = try await send(req)
    }

    func delete(from table: String, id: UUID) async throws {
        let req = try await request("\(table)?id=eq.\(id.uuidString.lowercased())", method: "DELETE")
        _ = try await send(req)
    }

    // MARK: - Plumbing

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let data = try await send(try await request(path, method: "GET"))
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(_ path: String, method: String) async throws -> URLRequest {
        let token = try await validToken()
        var req = URLRequest(url: URL(string: "rest/v1/" + path, relativeTo: baseURL)!)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    // Sends once; on an expired token, refreshes and sends once more.
    private func send(_ req: URLRequest, retried: Bool = false) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && !retried {
            try await refresh()
            var again = req
            again.setValue("Bearer \(session?.accessToken ?? "")", forHTTPHeaderField: "Authorization")
            return try await send(again, retried: true)
        }
        guard (200..<300).contains(code) else { throw APIError.server(code, Self.message(data, code)) }
        return data
    }

    private func validToken() async throws -> String {
        guard let s = session else { throw APIError.signedOut }
        if s.expiresAt.timeIntervalSinceNow < 60 { try await refresh() }
        guard let token = session?.accessToken else { throw APIError.signedOut }
        return token
    }

    private func refresh() async throws {
        guard let s = session else { throw APIError.signedOut }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": s.refreshToken])
        do {
            try await requestToken(grantType: "refresh_token", body: body, email: s.email)
        } catch APIError.server(let code, _) where (400..<500).contains(code) {
            signOut()
            throw APIError.signedOut
        }
    }

    private func requestToken(grantType: String, body: Data, email: String) async throws {
        var req = URLRequest(url: URL(string: "auth/v1/token?grant_type=\(grantType)", relativeTo: baseURL)!)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue(key, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.server(code, Self.message(data, code)) }
        let t = try JSONDecoder().decode(TokenResponse.self, from: data)
        let s = Session(accessToken: t.access_token, refreshToken: t.refresh_token,
                        expiresAt: Date().addingTimeInterval(t.expires_in), email: email)
        session = s
        Keychain.save(s)
    }

    private static func message(_ data: Data, _ code: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["msg", "message", "error_description", "error"] {
                if let m = obj[key] as? String, !m.isEmpty { return m }
            }
        }
        return "Request failed (\(code))."
    }
}
