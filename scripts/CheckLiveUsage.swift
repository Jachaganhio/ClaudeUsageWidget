import Foundation

// Read-only smoke check. Prints normalized usage only, never credentials or account identifiers.
@main
struct CheckLiveUsage {
    static func main() async throws {
        let snapshot = await UsageClient().fetch(config: try WidgetConfig.load())
        for provider in [snapshot.claude, snapshot.codex] {
            if let error = provider.error { print("\(provider.name): \(error)") }
            else if !provider.isEnabled { print("\(provider.name): disabled") }
            else {
                for metric in provider.metrics { print("\(provider.name) / \(metric.title): \(metric.percentageText)") }
            }
        }
    }
}
