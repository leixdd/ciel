#!/bin/sh -e
cd "$(dirname "$0")"
swift build -c release
APP="C.I.E.L.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS"
cp .build/release/CIEL "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign "CielAI" "$APP"   # self-signed cert: stable identity, TCC grants survive rebuilds
echo "open $PWD/$APP"
