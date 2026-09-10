import XCTest
@testable import UsageCore

final class UsageCoreTests: XCTestCase {
    func data(_ json: String) -> Data { Data(json.utf8) }

    func testLegacyClaudeDecimalAndDateFormats() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":42.5,"resets_at":"2026-09-07T12:00:00Z"},
         "seven_day":{"utilization":0,"resets_at":"2026-09-08T12:00:00.123Z"},
         "seven_day_overage_included":{"utilization":81.2,"resets_at":1788825600}}
        """))
        XCTAssertEqual(result.metrics.map(\.percent), [42.5, 0, 81.2])
        XCTAssertTrue(result.metrics.allSatisfy { $0.resetsAt != nil })
        XCTAssertEqual(result.metrics.last?.title, "Fable · Weekly")
    }

    func testScopedFablePreferredAndOtherScopesIgnored() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":12}, "seven_day_overage_included":{"utilization":88},
         "limits":[
          {"kind":"spend","percent":98},
          {"kind":"weekly_scoped","percent":70,"scope":{"model":{"display_name":"Opus"}}},
          {"kind":"weekly_scoped","percent":0,"resets_at":"2026-09-07T12:00:00Z",
           "scope":{"model":{"display_name":"Fable 5.1"}}}]}
        """))
        XCTAssertEqual(result.metrics.last?.percent, 0)
        XCTAssertNotNil(result.metrics.last?.resetsAt)
    }

    func testMissingFableAndWeeklyAreUnknownNotZero() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":0}, "seven_day":null, "limits":null}
        """))
        XCTAssertEqual(result.metrics.first?.percentageText, "0%")
        XCTAssertNil(result.metrics[1].percent)
        XCTAssertEqual(result.metrics[2].percentageText, "—")
        XCTAssertThrowsError(try UsageParser.claude(data("{}")))
    }

    func testMalformedValuesDoNotBecomeZeroOrHideOtherWindows() throws {
        let result = try UsageParser.claude(data("""
        {"five_hour":{"utilization":false}, "seven_day":{"utilization":21},
         "seven_day_overage_included":{"utilization":"bad","resets_at":"bad"}}
        """))
        XCTAssertNil(result.metrics[0].percent)
        XCTAssertEqual(result.metrics[1].percent, 21)
        XCTAssertNil(result.metrics[2].resetsAt)
        XCTAssertEqual(UsageMetric(id: "x", title: "x", percent: 130, resetsAt: nil).fraction, 1)
        XCTAssertEqual(UsageMetric(id: "x", title: "x", percent: -10, resetsAt: nil).fraction, 0)
    }

    func testCodexWeeklyPrimaryIsNotLabelledFiveHours() throws {
        let result = try UsageParser.codex(data("""
        {"rate_limit":{"primary_window":{"used_percent":40,"limit_window_seconds":604800,
         "reset_at":1788749023},"secondary_window":null},
         "additional_rate_limits":[{"limit_name":"Other", "rate_limit":{
          "primary_window":{"used_percent":99,"limit_window_seconds":18000}}}]}
        """))
        XCTAssertEqual(result.metrics.count, 1)
        XCTAssertEqual(result.metrics[0].title, "Weekly")
        XCTAssertEqual(result.metrics[0].percent, 40)
        XCTAssertEqual(result.metrics[0].resetsAt, Date(timeIntervalSince1970: 1788749023))
    }

    func testCodexTwoWindowsAndNullPercent() throws {
        let result = try UsageParser.codex(data("""
        {"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000},
         "secondary_window":{"used_percent":null,"limit_window_seconds":604800}}}
        """))
        XCTAssertEqual(result.metrics.map(\.title), ["5h Session", "Weekly"])
        XCTAssertEqual(result.metrics.map(\.percentageText), ["0%", "—"])
        XCTAssertThrowsError(try UsageParser.codex(data("{\"rate_limit\":null}")))
        XCTAssertThrowsError(try UsageParser.codex(data("[]")))
    }

    func testOldConfigMigrationPreservesUnknownFieldsAndSecuresFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try data("{\"sessionKey\":\"old\",\"futureField\":42}").write(to: url)
        var config = try WidgetConfig.load(from: url)
        XCTAssertEqual(config.sessionKey, "old")
        XCTAssertNil(config.codexEnabled)
        config.sessionKey = nil
        config.codexEnabled = false
        try config.save(to: url)
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        XCTAssertNil(saved["sessionKey"])
        XCTAssertEqual(saved["futureField"] as? Int, 42)
        XCTAssertEqual(try WidgetConfig.load(from: url).codexEnabled, false)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testUpcomingResetsAreFutureDedupedAndSorted() {
        let now = Date()
        let past = now.addingTimeInterval(-10)
        let soon = now.addingTimeInterval(100)
        let later = now.addingTimeInterval(200)
        let claude = ProviderUsage(name: "Claude", metrics: [
            UsageMetric(id: "a", title: "A", percent: 10, resetsAt: past),
            UsageMetric(id: "b", title: "B", percent: 20, resetsAt: later)
        ])
        let codex = ProviderUsage(name: "Codex", metrics: [
            UsageMetric(id: "c", title: "C", percent: 30, resetsAt: soon),
            UsageMetric(id: "d", title: "D", percent: 40, resetsAt: later) // duplicate of claude's
        ])
        let snapshot = UsageSnapshot(date: now, claude: claude, codex: codex)
        XCTAssertEqual(snapshot.upcomingResets, [soon, later])

        let disabledCodex = UsageSnapshot(date: now, claude: claude, codex: ProviderUsage(name: "Codex", isEnabled: false))
        XCTAssertEqual(disabledCodex.upcomingResets, [later])
    }

    func testClearingResetsPastBoundaryLeavesLaterResetsAndPercentagesIntact() {
        let now = Date()
        let justPassed = now.addingTimeInterval(5)
        let stillFuture = now.addingTimeInterval(1000)
        let claude = ProviderUsage(name: "Claude", metrics: [
            UsageMetric(id: "five_hour", title: "5h Session", percent: 42, resetsAt: justPassed),
            UsageMetric(id: "seven_day", title: "Weekly", percent: 10, resetsAt: stillFuture),
            UsageMetric(id: "fable", title: "Fable · Weekly", percent: nil, resetsAt: nil)
        ], error: nil)
        let snapshot = UsageSnapshot(date: now, claude: claude, codex: ProviderUsage(name: "Codex", isEnabled: false))
        let boundary = justPassed.addingTimeInterval(5)
        let cleared = snapshot.clearingResetsPast(boundary)

        XCTAssertEqual(cleared.date, boundary)
        XCTAssertNil(cleared.claude.metrics[0].resetsAt, "Passed reset should be cleared")
        XCTAssertEqual(cleared.claude.metrics[0].percent, 42, "Percent is left as-is, not fabricated to 0")
        XCTAssertEqual(cleared.claude.metrics[1].resetsAt, stillFuture, "Future reset must not be touched")
        XCTAssertNil(cleared.claude.metrics[2].resetsAt, "Already-nil reset stays nil")
        XCTAssertFalse(cleared.codex.isEnabled, "Other provider fields are preserved untouched")
    }

    func testInvalidConfigIsNotSilentlyOverwritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try data("invalid json").write(to: url)
        XCTAssertThrowsError(try WidgetConfig.load(from: url))
        XCTAssertThrowsError(try WidgetConfig().save(to: url))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "invalid json")
    }
}

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, json) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(json.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class UsageClientTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() { session.invalidateAndCancel(); StubProtocol.handler = nil }

    func testClaudeFailureDoesNotHideCodexAndAuthGoesToCorrectHost() async {
        StubProtocol.handler = { request in
            if request.url?.host == "api.anthropic.com" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer claude-test")
                XCTAssertNil(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"))
                return (401, "{}")
            }
            XCTAssertEqual(request.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer codex-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "ChatGPT-Account-Id"), "account-test")
            return (200, "{\"rate_limit\":{\"primary_window\":{\"used_percent\":10,\"limit_window_seconds\":18000}}}")
        }
        let result = await UsageClient(session: session).fetch(config: WidgetConfig(
            oauthToken: "claude-test", codexAccessToken: "codex-test", codexAccountId: "account-test"))
        XCTAssertNotNil(result.claude.error)
        XCTAssertNil(result.codex.error)
        XCTAssertEqual(result.codex.metrics.first?.percent, 10)
    }

    func testOAuthFallsBackToSessionAndDisabledCodexDoesNotFetch() async {
        StubProtocol.handler = { request in
            if request.url?.host == "api.anthropic.com" { return (401, "{}") }
            XCTAssertEqual(request.url?.host, "claude.ai")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "sessionKey=session-test")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, "{\"five_hour\":{\"utilization\":22.2}}")
        }
        let result = await UsageClient(session: session).fetch(config: WidgetConfig(
            sessionKey: "session-test", organizationId: "11111111-1111-1111-1111-111111111111",
            oauthToken: "expired-test", codexEnabled: false))
        XCTAssertNil(result.claude.error)
        XCTAssertEqual(result.claude.metrics.first?.percent, 22.2)
        XCTAssertFalse(result.codex.isEnabled)
    }

    func testCodexRereadsRotatedLocalAuthAndRejectsAPIKeyOnly() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let client = UsageClient(session: session, codexAuthURL: url)
        for token in ["first-token", "rotated-token"] {
            try Data("{\"tokens\":{\"access_token\":\"\(token)\",\"account_id\":\"test\"}}".utf8).write(to: url)
            StubProtocol.handler = { request in
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
                return (200, "{\"rate_limit\":{\"primary_window\":{\"used_percent\":0}}}")
            }
            let result = await client.fetchCodex(WidgetConfig())
            XCTAssertNil(result.error)
        }
        try Data("{\"OPENAI_API_KEY\":\"test\"}".utf8).write(to: url)
        StubProtocol.handler = { _ in XCTFail("Must not send API key to subscription endpoint"); return (500, "{}") }
        let result = await client.fetchCodex(WidgetConfig())
        XCTAssertNotNil(result.error)
    }

    func testRateLimitErrorAndInvalidOrganization() async {
        StubProtocol.handler = { _ in (429, "{}") }
        let client = UsageClient(session: session)
        let result = await client.fetchCodex(WidgetConfig(codexAccessToken: "test"))
        XCTAssertEqual(result.error, UsageError.http(429).localizedDescription)
        let invalid = await client.fetchClaude(WidgetConfig(sessionKey: "test", organizationId: "../wrong?query"))
        XCTAssertEqual(invalid.error, "Organization ID must be a UUID.")
    }
}
