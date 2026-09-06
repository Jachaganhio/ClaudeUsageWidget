# App icon

The dual-meter icon was created for this repository using original geometric paths. It uses no third-party icon pack, brand logo, font, stock image, or downloaded artwork.

The SVG source, generator, and generated PNG files are distributed under the project's [MIT license](../LICENSE), including commercial use under that license.

- Editable source: `AppIcon.svg`
- Reproducible renderer: `scripts/GenerateAppIcon.swift`
- macOS assets: `ClaudeUsageWidget/Assets.xcassets/AppIcon.appiconset/`

Regenerate from the repository root on macOS:

```bash
mkdir -p build
swiftc scripts/GenerateAppIcon.swift -parse-as-library -o build/generate-app-icon
build/generate-app-icon
```

The app is an independent utility; this artwork does not represent an official Anthropic or OpenAI product logo.
