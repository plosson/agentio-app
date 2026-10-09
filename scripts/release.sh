#!/usr/bin/env bash
# Builds, signs, notarizes and publishes AgentIO Companion to GitHub Releases (pkg, zip and Sparkle appcast), then
# updates its Homebrew cask. The steps live in the houlahop-mac-release submodule: see scripts/mac-release/lib.sh
# for what they need.
# Usage: DEVELOPMENT_TEAM=XXXXXXXXXX scripts/release.sh 0.1.0
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[[ -f scripts/mac-release/lib.sh ]] || git submodule update --init scripts/mac-release
source scripts/mac-release/lib.sh

release_version "${1:-}"
: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to your Apple team ID}"
TEAM="$DEVELOPMENT_TEAM"
MACOS="$ROOT/apps/macos"
NAME="AgentIO Companion"
FILE_NAME="AgentIO-Companion-$VERSION"
REPO="plosson/agentio-app"
BUNDLE_ID="com.plosson.agentio-companion"
PROJECT="$MACOS/AgentioCompanion.xcodeproj"
SCHEME="AgentioCompanion"
BUILD="$MACOS/build/release"
SPARKLE_ACCOUNT="agentio-companion"
CASK="agentio-companion"
CASK_DESC="Desktop companion for AgentIO vaults"
MIN_MACOS="sonoma"

release_check_clean
release_clean_build

cd "$MACOS"
xcodegen generate
xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -derivedDataPath "$MACOS/build"

release_archive
release_export
release_notarize_app
release_pkg
release_appcast
release_publish
release_cask
