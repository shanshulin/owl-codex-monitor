import Foundation

struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let message: String
    let data: T
}

struct LoginResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

struct Account: Decodable {
    let balance: Double
}

struct DashboardStats: Decodable {
    let totalRequests: Int
    let todayRequests: Int
    let totalTokens: Int64
    let todayTokens: Int64
    let totalActualCost: Double
    let todayActualCost: Double

    enum CodingKeys: String, CodingKey {
        case totalRequests = "total_requests"
        case todayRequests = "today_requests"
        case totalTokens = "total_tokens"
        case todayTokens = "today_tokens"
        case totalActualCost = "total_actual_cost"
        case todayActualCost = "today_actual_cost"
    }
}

struct SubscriptionGroup: Decodable {
    let name: String
    let dailyLimitUSD: Double?
    let weeklyLimitUSD: Double?
    let monthlyLimitUSD: Double?
    let dailyLimitRolloverEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case name
        case dailyLimitUSD = "daily_limit_usd"
        case weeklyLimitUSD = "weekly_limit_usd"
        case monthlyLimitUSD = "monthly_limit_usd"
        case dailyLimitRolloverEnabled = "daily_limit_rollover_enabled"
    }
}

struct Subscription: Decodable {
    let id: Int
    let status: String
    let expiresAt: String?
    let effectiveDailyLimitUSD: Double?
    let dailyUsageUSD: Double?
    let weeklyUsageUSD: Double?
    let monthlyUsageUSD: Double?
    let dailyWindowStart: String?
    let dailyRolloverAmountUSD: Double?
    let dailyRolloverRemainingUSD: Double?
    let dailyRolloverWindowStart: String?
    let noDailyLimitEffective: Bool?
    let group: SubscriptionGroup?

    enum CodingKeys: String, CodingKey {
        case id, status, group
        case expiresAt = "expires_at"
        case effectiveDailyLimitUSD = "effective_daily_limit_usd"
        case dailyUsageUSD = "daily_usage_usd"
        case weeklyUsageUSD = "weekly_usage_usd"
        case monthlyUsageUSD = "monthly_usage_usd"
        case dailyWindowStart = "daily_window_start"
        case dailyRolloverAmountUSD = "daily_rollover_amount_usd"
        case dailyRolloverRemainingUSD = "daily_rollover_remaining_usd"
        case dailyRolloverWindowStart = "daily_rollover_window_start"
        case noDailyLimitEffective = "no_daily_limit_effective"
    }

    var primaryQuota: QuotaUsage? {
        monthlyQuota ?? weeklyQuota ?? dailyQuota
    }

    var dailyQuota: QuotaUsage? {
        guard noDailyLimitEffective != true,
              let baseLimit = effectiveDailyLimitUSD ?? group?.dailyLimitUSD,
              baseLimit > 0 else { return nil }
        let rollover = activeRollover
        return QuotaUsage(
            period: "今日",
            used: (dailyUsageUSD ?? 0) + (rollover?.used ?? 0),
            limit: baseLimit + (rollover?.amount ?? 0)
        )
    }

    var weeklyQuota: QuotaUsage? {
        guard let limit = group?.weeklyLimitUSD, limit > 0 else { return nil }
        return QuotaUsage(period: "本周", used: weeklyUsageUSD ?? 0, limit: limit)
    }

    var monthlyQuota: QuotaUsage? {
        guard let limit = group?.monthlyLimitUSD, limit > 0 else { return nil }
        return QuotaUsage(period: "本月", used: monthlyUsageUSD ?? 0, limit: limit)
    }

    var activeRollover: RolloverUsage? {
        guard noDailyLimitEffective != true,
              group?.dailyLimitRolloverEnabled != false,
              let amount = dailyRolloverAmountUSD, amount > 0,
              let rolloverStart = parseISO8601(dailyRolloverWindowStart),
              let dailyStart = parseISO8601(dailyWindowStart),
              abs(rolloverStart.timeIntervalSince(dailyStart)) < 1,
              Date() < dailyStart.addingTimeInterval(24 * 60 * 60) else {
            return nil
        }
        let remaining = min(max(dailyRolloverRemainingUSD ?? 0, 0), amount)
        return RolloverUsage(amount: amount, remaining: remaining)
    }
}

private func parseISO8601(_ value: String?) -> Date? {
    guard let value else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: value) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value)
}

struct RolloverUsage: Equatable {
    let amount: Double
    let remaining: Double

    var used: Double { max(amount - remaining, 0) }
}

struct QuotaUsage: Equatable {
    let period: String
    let used: Double
    let limit: Double

    var fraction: Double {
        guard limit > 0 else { return 0 }
        return min(max(used / limit, 0), 1)
    }
}

struct MonitorSnapshot {
    let account: Account
    let stats: DashboardStats
    let activeSubscription: Subscription?
    let refreshedAt: Date
}

enum OwlAPIError: LocalizedError {
    case invalidResponse
    case api(String)
    case loginExpired

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "服务器返回了无法识别的数据"
        case .api(let message): return message
        case .loginExpired: return "登录已过期，请重新登录"
        }
    }
}

actor OwlAPIClient {
    static let shared = OwlAPIClient()

    private let baseURL = URL(string: "https://api.owlai.tech/api/v1")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var accessToken: String?
    private var accessTokenExpiresAt: Date = .distantPast
    private var refreshTask: Task<Void, Error>?

    func hasStoredLogin() -> Bool {
        KeychainStore.read(account: "refresh-token") != nil || storedCredentials != nil
    }

    func login(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        refreshTask?.cancel()
        refreshTask = nil
        let response: LoginResponse = try await post(
            "auth/login",
            body: Body(email: email, password: password),
            authenticated: false,
            isLoginRequest: true
        )
        try KeychainStore.save(password, account: "login-password")
        try persist(response: response, email: email)
    }

    func logout() {
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        accessTokenExpiresAt = .distantPast
        KeychainStore.delete(account: "refresh-token")
        KeychainStore.delete(account: "email")
        KeychainStore.delete(account: "login-password")
    }

    func fetchSnapshot() async throws -> MonitorSnapshot {
        try await ensureAccessToken()
        async let account: Account = get("auth/me")
        async let stats: DashboardStats = get("usage/dashboard/stats")
        async let subscriptions: [Subscription] = get("subscriptions/active")
        return try await MonitorSnapshot(
            account: account,
            stats: stats,
            activeSubscription: subscriptions.first,
            refreshedAt: Date()
        )
    }

    private func ensureAccessToken() async throws {
        if accessToken != nil, accessTokenExpiresAt.timeIntervalSinceNow > 60 { return }
        if let refreshTask {
            try await refreshTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            try await self.refreshAccessToken()
        }
        refreshTask = task
        defer { refreshTask = nil }
        try await task.value
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = KeychainStore.read(account: "refresh-token") else {
            try await reauthenticateWithStoredCredentials()
            return
        }

        struct Body: Encodable { let refreshToken: String
            enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
        }
        do {
            let response: LoginResponse = try await post(
                "auth/refresh",
                body: Body(refreshToken: refreshToken),
                authenticated: false
            )
            try persist(response: response, email: KeychainStore.read(account: "email"))
        } catch OwlAPIError.loginExpired {
            try await reauthenticateWithStoredCredentials()
        } catch OwlAPIError.api(_) {
            try await reauthenticateWithStoredCredentials()
        }
    }

    private var storedCredentials: (email: String, password: String)? {
        guard let email = KeychainStore.read(account: "email"),
              let password = KeychainStore.read(account: "login-password"),
              !email.isEmpty,
              !password.isEmpty else {
            return nil
        }
        return (email, password)
    }

    private func reauthenticateWithStoredCredentials() async throws {
        guard let credentials = storedCredentials else {
            throw OwlAPIError.loginExpired
        }

        struct Body: Encodable { let email: String; let password: String }
        do {
            let response: LoginResponse = try await post(
                "auth/login",
                body: Body(email: credentials.email, password: credentials.password),
                authenticated: false,
                isLoginRequest: true
            )
            try persist(response: response, email: credentials.email)
        } catch OwlAPIError.api(_) {
            throw OwlAPIError.loginExpired
        }
    }

    private func persist(response: LoginResponse, email: String?) throws {
        accessToken = response.accessToken
        accessTokenExpiresAt = Date().addingTimeInterval(TimeInterval(response.expiresIn))
        try KeychainStore.save(response.refreshToken, account: "refresh-token")
        if let email { try KeychainStore.save(email, account: "email") }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "GET"
        return try await send(request, authenticated: true)
    }

    private func post<Body: Encodable, T: Decodable>(
        _ path: String,
        body: Body,
        authenticated: Bool,
        isLoginRequest: Bool = false
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await send(request, authenticated: authenticated, isLoginRequest: isLoginRequest)
    }

    private func send<T: Decodable>(
        _ request: URLRequest,
        authenticated: Bool,
        isLoginRequest: Bool = false
    ) async throws -> T {
        var request = request
        if authenticated {
            guard let accessToken else { throw OwlAPIError.loginExpired }
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OwlAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            if isLoginRequest, let envelope = try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data) {
                throw OwlAPIError.api(envelope.message)
            }
            throw OwlAPIError.loginExpired
        }

        do {
            let envelope = try decoder.decode(APIEnvelope<T>.self, from: data)
            guard envelope.code == 0 else { throw OwlAPIError.api(envelope.message) }
            return envelope.data
        } catch let error as OwlAPIError {
            throw error
        } catch {
            if let envelope = try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data) {
                throw OwlAPIError.api(envelope.message)
            }
            throw OwlAPIError.invalidResponse
        }
    }
}

private struct EmptyPayload: Decodable {}
