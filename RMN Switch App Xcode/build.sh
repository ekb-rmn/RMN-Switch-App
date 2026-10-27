#!/bin/zsh
set -eu
cd "${0:A:h}"
target="${1:-$PWD/../RMN Switch App.app}"
build_dir=$(mktemp -d "${TMPDIR:-/tmp}/rmn-switch-build.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT
for architecture in arm64 x86_64; do
    xcrun swiftc -parse-as-library -O -target "${architecture}-apple-macosx12.0" SwitchApp.swift -o "$build_dir/$architecture"
done
xcrun lipo -create "$build_dir/arm64" "$build_dir/x86_64" -output "$build_dir/RMN Switch App"
xcrun lipo "$build_dir/RMN Switch App" -verify_arch arm64
xcrun lipo "$build_dir/RMN Switch App" -verify_arch x86_64
mkdir -p "$target/Contents/MacOS" "$target/Contents/Resources"
cp AppIcon.icns "$target/Contents/Resources/AppIcon.icns"
cp "$build_dir/RMN Switch App" "$target/Contents/MacOS/RMN Switch App"
cp Info.plist "$target/Contents/Info.plist"
xattr -d com.apple.FinderInfo "$target" 2>/dev/null || true
rm -f "$target/"$'Icon\r'
codesign --force --sign - --identifier ru.rmn.LangSwitch --requirements '=designated => identifier "ru.rmn.LangSwitch"' "$target"
"$target/Contents/MacOS/RMN Switch App" --self-test
