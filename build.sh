#!/bin/bash
# Backstage.app 을 만든다 (Apple Silicon + Intel 유니버설).
#   ./build.sh             build/Backstage.app 만들기 (ad-hoc 서명)
#   ./build.sh --install   만든 뒤 ~/Applications 에 설치하고 실행
# SIGN_IDENTITY="Developer ID Application: …" 를 주면 그 인증서로 하드닝 런타임 서명(배포용)
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(cat VERSION)
APP="build/Backstage.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/obj

# 1) 두 아키텍처로 컴파일해서 합친다
for arch in arm64 x86_64; do
  swiftc -parse-as-library -swift-version 5 -O \
    -target "$arch-apple-macosx14.0" \
    Sources/main.swift -o "build/obj/Backstage-$arch"
done
lipo -create build/obj/Backstage-arm64 build/obj/Backstage-x86_64 -output "$APP/Contents/MacOS/Backstage"

# 2) 아이콘 (docs/images/icon-1024.png → AppIcon.icns)
ICONSET=build/AppIcon.iconset; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/images/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) docs/images/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# 3) Info.plist — 메뉴바 전용 앱(LSUIElement)이라 Dock 아이콘이 없다
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>kr.haul.backstage</string>
  <key>CFBundleName</key><string>Backstage</string>
  <key>CFBundleDisplayName</key><string>Backstage</string>
  <key>CFBundleExecutable</key><string>Backstage</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Haul</string>
</dict></plist>
EOF

# 4) 서명
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "만듦: $APP (v$VERSION, $(lipo -archs "$APP/Contents/MacOS/Backstage"))"

if [ "${1:-}" = "--install" ]; then
  pkill -x Backstage 2>/dev/null || true
  rm -rf "$HOME/Applications/Backstage.app"
  mkdir -p "$HOME/Applications"
  cp -R "$APP" "$HOME/Applications/"
  open "$HOME/Applications/Backstage.app"
  echo "설치·실행: $HOME/Applications/Backstage.app"
fi
