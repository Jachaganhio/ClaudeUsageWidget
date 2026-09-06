# ClaudeUsageWidget

A macOS desktop widget (WidgetKit) that monitors Claude, Claude Fable, and Codex subscription usage together.

![macOS](https://img.shields.io/badge/macOS-15.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.0-orange)
![License](https://img.shields.io/badge/License-MIT-green)

[中文文档](README_CN.md)

<img src="ClaudeUsageWidget/Assets.xcassets/AppIcon.appiconset/icon_256.png" width="96" alt="App icon">

## Screenshots

![ClaudeUsageWidget Preview](screenshots/widget-preview-v1.1.png)

*Preview uses sample data.*

## Features

- **5-hour session usage** with progress bar
- **Weekly usage** with progress bar
- **Separate Fable weekly usage** with reset time
- **Codex usage** from your local ChatGPT login, labelled by actual window duration
- **In-app dashboard** with manual refresh and independent provider switches
- **Reset countdown** for both windows
- **Color-coded** green → yellow → orange → red
- **Three widget sizes** — small, medium, large
- **Dual auth** — OAuth token or session key
- **Auto-refresh** requested every 5 minutes; macOS controls actual scheduling
- **Original app icon** included under MIT, with no third-party icon assets

---

## Quick Install with Claude Code

Paste this into your Claude Code session:

```
Clone https://github.com/dependentsign/ClaudeUsageWidget and build it for me.

Steps:
1. git clone https://github.com/dependentsign/ClaudeUsageWidget.git ~/Documents/ClaudeUsageWidget
2. Build and package: cd ~/Documents/ClaudeUsageWidget && ./scripts/build-local.sh
3. Extract build/ClaudeUsageWidget-1.1.zip, quit the old app, and copy ClaudeUsageWidget.app to /Applications
4. Open the app and enter my Claude OAuth token, or session key and organization UUID; keep existing settings if present
5. For Codex, sign in with a ChatGPT account in Codex CLI; the app reads ~/.codex/auth.json automatically
6. Click Save & Refresh
7. Tell me to right-click desktop → Edit Widgets → search "Claude" or "Codex" to add it
```

---

## Manual Setup

You can also download the app archive from [Releases](https://github.com/dependentsign/ClaudeUsageWidget/releases/latest). Quit the old app, extract the archive, and replace `/Applications/ClaudeUsageWidget.app`. Release builds support Apple Silicon and Intel, use ad-hoc signing and are not notarized by Apple.

### 1. Build

```bash
git clone https://github.com/dependentsign/ClaudeUsageWidget.git
cd ClaudeUsageWidget
open ClaudeUsageWidget.xcodeproj
```

In Xcode:
- Select your **Development Team** in both targets (ClaudeUsageWidget + ClaudeUsageWidgetExtension)
- Update **Bundle Identifier** if needed
- Build & Run (⌘R)

Alternatively, run `./scripts/build-local.sh` to produce `build/ClaudeUsageWidget-1.1.zip`. It builds in a temporary directory to avoid Documents/iCloud metadata breaking code signing.

### 2. Configure Credentials

Enter and save credentials in the app, or create `~/.claude/claude-usage-widget.json`. Fable uses the same Claude credentials:

**Option A: OAuth Token (recommended)**
```json
{
  "oauthToken": "your-oauth-bearer-token"
}
```

**Option B: Session Key**
```json
{
  "sessionKey": "sk-ant-sid01-...",
  "organizationId": "your-org-uuid"
}
```

<details>
<summary>How to get session key</summary>

1. Open [claude.ai](https://claude.ai) and log in
2. DevTools (F12) → Application → Cookies → copy `sessionKey`
3. Get org ID:
```bash
curl -s https://claude.ai/api/organizations \
  -H "Cookie: sessionKey=YOUR_KEY" | python3 -m json.tool
```
Select the subscription organization you use and copy its **`uuid`**, not the numeric `id` or `parent_organization_uuid`.

</details>

**Codex (automatic by default)**

Sign in to Codex CLI with a ChatGPT account. Each refresh reads `~/.codex/auth.json`, following token rotation. API keys do not expose subscription limits.

For Keychain-only credentials, a custom `CODEX_HOME`, or another location, enter an access token and optional ChatGPT account ID under **Manual token** in the app. A manual token overrides automatic loading and must be replaced when expired; clear it to resume automatic loading. The app does not refresh or modify Codex's login file. Renew expired automatic credentials in Codex.

```json
{
  "codexEnabled": true,
  "codexAccessToken": "your-codex-access-token",
  "codexAccountId": "your-chatgpt-account-id"
}
```

Existing configuration remains compatible. `claudeEnabled` / `codexEnabled` toggle each provider. Saves preserve unknown fields, replace the file atomically, and set owner-only permissions (`0600`).

### 3. Add Widget

1. Right-click desktop → **Edit Widgets...**
2. Search **"Claude"** or **"Codex"**
3. Choose size and add

---

## How It Works

The widget calls each provider's usage endpoint:

| Method | Endpoint |
|--------|----------|
| OAuth | `GET https://api.anthropic.com/api/oauth/usage` |
| Session Key | `GET https://claude.ai/api/organizations/{orgId}/usage` |
| Codex | `GET https://chatgpt.com/backend-api/wham/usage` |

Returns:
- `five_hour.utilization` — 5-hour window usage %
- `five_hour.resets_at` — reset timestamp
- `seven_day.utilization` — weekly usage %
- `seven_day.resets_at` — weekly reset timestamp
- Fable: prefers Fable model entries with `weekly_scoped` in `limits[]`; supports `seven_day_overage_included` / `seven_day_fable` fallback
- Codex: `used_percent`, `limit_window_seconds`, and `reset_at` from `rate_limit.primary_window` / `secondary_window`

Percentages represent **usage consumed**. Missing data shows `—`, not 0%; Fable percentages are not rescaled by an inferred 50% allowance. Codex shows the general subscription pool, not additional pools such as Spark or API billing.

Requests run concurrently with independent errors. HTTP 401 prompts credential renewal, 403 prompts checking login and access, and 429 prompts waiting until the next refresh. Medium and large widgets include reset times; large includes the update timestamp. Subscription usage endpoints may change.

---

## Development

### Project Structure

```
ClaudeUsageWidget/
├── ClaudeUsageWidget/                    # Host app (dashboard + configuration)
├── ClaudeUsageWidgetExtension/           # WidgetKit timeline and entry point
├── Shared/                              # Shared models, requests, and views
├── Tests/UsageCoreTests/                 # Regression tests
├── scripts/                             # Build, previews, icon generation, live checks
├── artwork/                             # Original icon SVG and license notes
└── screenshots/
```

> **Note:** Widget extensions run in App Sandbox. We use `getpwuid(getuid())` to resolve the real home directory instead of `FileManager.default.homeDirectoryForCurrentUser` (which returns the sandbox container path).

### Validation

```bash
swift test
./scripts/build-local.sh

# 18 SwiftUI previews: three sizes × light/dark × normal/error/missing data
mkdir -p build
swiftc Shared/UsageModels.swift Shared/UsageViews.swift scripts/RenderPreviews.swift -o build/render-previews
build/render-previews
```

`CheckLiveUsage.swift` optionally performs a read-only check using local credentials, printing only usage and errors. The icon is generated by `GenerateAppIcon.swift`; see [artwork](artwork/README.md) for provenance and licensing.

## Requirements

- macOS 15.0+
- Xcode 16.0+
- For Claude: a Claude subscription with usage limits
- For Codex: a ChatGPT account signed in to Codex

## License

MIT — see [LICENSE](LICENSE)
