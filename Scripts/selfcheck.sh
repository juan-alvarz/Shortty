#!/bin/bash
# Compiles the app sources (minus the @main entry) together with Scripts/SelfCheck/main.swift and runs the checks.
# Usage: Scripts/selfcheck.sh [snapshot-dir]   (snapshot-dir: optional, saves PNGs of the editor for a visual check)
set -euo pipefail
cd "$(dirname "$0")/.."

BIN_DIR=$(mktemp -d)
trap 'rm -rf "$BIN_DIR"' EXIT

SOURCES=()
while IFS= read -r file; do SOURCES+=("$file"); done < <(find Shortty -name '*.swift' ! -name 'ShorttyApp.swift')

swiftc -swift-version 5 -parse-as-library -suppress-warnings -target "$(uname -m)-apple-macos14.0" \
  "${SOURCES[@]}" Scripts/SelfCheck/main.swift -o "$BIN_DIR/selfcheck"
"$BIN_DIR/selfcheck" "$PWD" "${1:-}"
