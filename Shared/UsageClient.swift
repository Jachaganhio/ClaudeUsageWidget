import Foundation

struct UsageClient {
    var session: URLSession = .shared
    var codexAuthURL: URL = ConfigLocation.codexAuthURL

    func fetch(config: WidgetConfig) async -> UsageSnapshot {
        async let claude = fetchClaude(config)
        async let codex = fetchCodex(config)
        return await UsageSnapshot(date: Date(), claude: claude, codex: codex)
    }

    private func get(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw UsageError.invalidResponse }
        guard response.statusCode == 200 else { throw UsageError.http(response.statusCode) }
        return data
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func fetchClaude(_ config: WidgetConfig) async -> ProviderUsage {
        guard config.claudeEnabled != false else { return ProviderUsage(name: "Claude", isEnabled: false) }
        var failure: Error = UsageError.missingClaude
        if let token = config.oauthToken?.nonempty {
            var req = request(URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            do { return try UsageParser.claude(await get(req)) } catch { failure = error }
        }
        if let key = config.sessionKey?.nonempty, let org = config.organizationId?.nonempty {
            // An organization is a UUID; never interpolate arbitrary path/query characters.
            guard UUID(uuidString: org) != nil else {
                return ProviderUsage(name: "Claude", error: "Organization ID must be a UUID.")
            }
            var req = request(URL(string: "https://claude.ai/api/organizations/\(org)/usage")!)
            req.setValue("sessionKey=\(key)", forHTTPHeaderField: "Cookie")
            do { return try UsageParser.claude(await get(req)) } catch { failure = error }
        }
        return ProviderUsage(name: "Claude", error: failure.localizedDescription)
    }

    func fetchCodex(_ config: WidgetConfig) async -> ProviderUsage {
        guard config.codexEnabled != false else { return ProviderUsage(name: "Codex", isEnabled: false) }
        do {
            let token: String
            let account: String?
            if let manual = config.codexAccessToken?.nonempty {
                token = manual
                account = config.codexAccountId?.nonempty
            } else {
                // Re-read each time so Codex's token rotation and account switches are reflected.
                guard let data = try? Data(contentsOf: codexAuthURL),
                      let auth = try? JSONDecoder().decode(CodexAuth.self, from: data),
                      let access = auth.tokens?.access_token?.nonempty else { throw UsageError.missingCodex }
                token = access
                account = auth.tokens?.account_id?.nonempty
            }
            var req = request(URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            if let account { req.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id") }
            return try UsageParser.codex(await get(req))
        } catch {
            return ProviderUsage(name: "Codex", error: error.localizedDescription)
        }
    }
}

private struct CodexAuth: Decodable {
    let tokens: Tokens?
    struct Tokens: Decodable {
        let access_token: String?
        let account_id: String?
    }
}

extension String {
    var nonempty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
