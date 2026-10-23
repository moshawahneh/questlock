#!/bin/sh
# Compiles the eval tool with the app's own PhotoChecks.swift and runs it on eval/.
set -e
cd "$(dirname "$0")/../.."
mkdir -p build
swiftc -O tools/eval-photos/main.swift ios/App/Services/CheckIn/PhotoChecks.swift -o build/eval-photos
build/eval-photos "${1:-eval}"
