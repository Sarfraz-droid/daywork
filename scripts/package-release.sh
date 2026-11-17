#!/bin/sh
# Build and package the Apple silicon release. Additional arguments go to SwiftPM.
set -eu
cd "$(dirname "$0")/.."
./build-app.sh --arch arm64 "$@"
mkdir -p release docs/downloads
ditto -c -k --sequesterRsrc --keepParent Daymark.app release/Daymark-macOS-arm64.zip
cp release/Daymark-macOS-arm64.zip docs/downloads/Daymark-macOS-arm64.zip
(cd docs/downloads && shasum -a 256 Daymark-macOS-arm64.zip > SHA256SUMS.txt)
printf 'Packaged release/Daymark-macOS-arm64.zip and refreshed the website download.\n'
