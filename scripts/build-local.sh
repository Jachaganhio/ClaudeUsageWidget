#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Build outside Documents/iCloud: file-provider FinderInfo can break code signing.
usage_build_dir=$(mktemp -d "${TMPDIR:-/tmp}/claude-usage-build.XXXXXX")
trap 'rm -rf "$usage_build_dir"' EXIT
xcodebuild -project ClaudeUsageWidget.xcodeproj -scheme ClaudeUsageWidget \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$usage_build_dir" \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
usage_app="$usage_build_dir/Build/Products/Release/ClaudeUsageWidget.app"
codesign --verify --deep --strict "$usage_app"
mkdir -p build
ditto -c -k --norsrc --noextattr --keepParent "$usage_app" build/ClaudeUsageWidget-1.1.zip
printf 'Created %s/build/ClaudeUsageWidget-1.1.zip\n' "$PWD"
