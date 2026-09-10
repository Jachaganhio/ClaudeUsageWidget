import AppKit
import SwiftUI

@main
struct RenderPreviews {
    @MainActor static func main() throws {
        let destination = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "build/previews")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let error = UsageSnapshot(date: Date(),
            claude: ProviderUsage(name: "Claude", error: UsageError.http(403).localizedDescription),
            codex: UsageSnapshot.preview.codex)
        let missing = UsageSnapshot(date: Date(), claude: try UsageParser.claude(Data("{\"five_hour\":{\"utilization\":0},\"seven_day\":{\"utilization\":12}}".utf8)),
                                    codex: try UsageParser.codex(Data("{\"rate_limit\":{\"primary_window\":{\"used_percent\":40,\"limit_window_seconds\":604800}}}".utf8)))
        let claudeOnly = UsageSnapshot(date: Date(), claude: UsageSnapshot.preview.claude,
                                       codex: ProviderUsage(name: "Codex", isEnabled: false))
        let codexOnly = UsageSnapshot(date: Date(), claude: ProviderUsage(name: "Claude", isEnabled: false),
                                      codex: UsageSnapshot.preview.codex)
        let states = [("normal", UsageSnapshot.preview), ("error", error), ("missing", missing),
                      ("claude-only", claudeOnly), ("codex-only", codexOnly)]
        for (state, snapshot) in states {
            for (name, width, height) in [("small", 158.0, 158.0), ("medium", 338.0, 158.0), ("large", 338.0, 354.0)] {
                for scheme in [ColorScheme.dark, .light] {
                    let view = UsageDashboardView(snapshot: snapshot, small: name == "small", large: name == "large")
                        .padding(16)
                        .frame(width: width, height: height)
                        .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.96))
                        .environment(\.colorScheme, scheme)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 2
                    guard let image = renderer.cgImage else { fatalError("Cannot render preview") }
                    let bitmap = NSBitmapImageRep(cgImage: image)
                    let png = bitmap.representation(using: .png, properties: [:])!
                    try png.write(to: destination.appendingPathComponent("\(state)-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        print("Rendered \(states.count * 6) layout previews in \(destination.path)")
    }
}
