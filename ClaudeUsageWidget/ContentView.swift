import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var sessionKey = ""
    @State private var organizationId = ""
    @State private var oauthToken = ""
    @State private var claudeEnabled = true
    @State private var codexEnabled = true
    @State private var codexAccessToken = ""
    @State private var codexAccountId = ""
    @State private var statusMessage = ""
    @State private var isSuccess = false
    @State private var isRefreshing = false
    @State private var snapshot: UsageSnapshot?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "chart.bar.fill").font(.title).foregroundStyle(.teal)
                    VStack(alignment: .leading) {
                        Text("Claude & Codex Usage").font(.title2.bold())
                        Text("Subscription usage · Claude, Fable and Codex")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(action: { Task { await refresh() } }) {
                        Label(isRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }

                if let snapshot {
                    HStack(alignment: .top, spacing: 20) {
                        ProviderUsageView(usage: snapshot.claude)
                        Divider()
                        ProviderUsageView(usage: snapshot.codex)
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    Text("Used percentage · Updated \(snapshot.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show Claude and Fable", isOn: $claudeEnabled)
                        Text("Fable's weekly limit is read with your Claude usage; no extra token is needed.")
                            .font(.caption).foregroundStyle(.secondary)
                        SecureField("Claude OAuth Bearer Token (preferred)", text: $oauthToken)
                        Text("Or use a browser session key:").font(.caption).foregroundStyle(.secondary)
                        SecureField("Session Key (sk-ant-sid01-…)", text: $sessionKey)
                        TextField("Organization ID (UUID)", text: $organizationId)
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                } label: { Text("Claude").fontWeight(.semibold) }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("Show Codex", isOn: $codexEnabled)
                        Text("Automatically reads the current ChatGPT login from ~/.codex/auth.json. Sign in with Codex CLI first. API keys do not provide subscription usage.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Manual token (overrides automatic login)") {
                            VStack(alignment: .leading, spacing: 8) {
                                SecureField("Codex access token", text: $codexAccessToken)
                                TextField("ChatGPT account ID (optional)", text: $codexAccountId)
                                Text("Manual tokens expire. Clear the token to use the local Codex login again.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.top, 8)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .padding(8)
                } label: { Text("Codex").fontWeight(.semibold) }

                if !statusMessage.isEmpty {
                    Text(statusMessage).font(.caption).foregroundStyle(isSuccess ? .green : .red)
                }
                HStack {
                    Button("Save & Refresh") { saveConfig() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRefreshing)
                    Button("Load Existing") { loadConfig() }
                        .disabled(isRefreshing)
                    Spacer()
                }
                Text("Config: ~/.claude/claude-usage-widget.json\nAdd the widget: right-click desktop → Edit Widgets → search Claude or Codex.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .frame(minWidth: 620, minHeight: 680)
        .task {
            if loadConfig() { await refresh() }
        }
    }

    private var config: WidgetConfig {
        WidgetConfig(sessionKey: sessionKey.nonempty, organizationId: organizationId.nonempty,
                     oauthToken: oauthToken.nonempty, claudeEnabled: claudeEnabled,
                     codexEnabled: codexEnabled, codexAccessToken: codexAccessToken.nonempty,
                     codexAccountId: codexAccountId.nonempty)
    }

    private func saveConfig() {
        if claudeEnabled, sessionKey.nonempty != nil,
           UUID(uuidString: organizationId.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            statusMessage = "Enter a valid Claude organization UUID for the session key."
            isSuccess = false
            return
        }
        do {
            try config.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "ClaudeUsageWidget")
            statusMessage = "Configuration saved. Widget refresh requested."
            isSuccess = true
            Task { await refresh() }
        } catch {
            statusMessage = "Failed to save: \(error.localizedDescription)"
            isSuccess = false
        }
    }

    @discardableResult
    private func loadConfig() -> Bool {
        do {
            let config = try WidgetConfig.load()
            sessionKey = config.sessionKey ?? ""
            organizationId = config.organizationId ?? ""
            oauthToken = config.oauthToken ?? ""
            claudeEnabled = config.claudeEnabled != false
            codexEnabled = config.codexEnabled != false
            codexAccessToken = config.codexAccessToken ?? ""
            codexAccountId = config.codexAccountId ?? ""
            statusMessage = ""
            return true
        } catch {
            statusMessage = "Cannot load configuration: \(error.localizedDescription)"
            isSuccess = false
            return false
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        snapshot = await UsageClient().fetch(config: config)
    }
}

#Preview { ContentView() }
