#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

SDK="$(xcrun --show-sdk-path)"
TARGET="${TARGET:-arm64-apple-macosx14.0}"
CONFIG="${CONFIG:-release}"
APP_NAME="DiscordStatusModifier"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
BIN="$BUILD_DIR/${APP_NAME}_bin"

OPT_FLAGS=(-O)
if [[ "$CONFIG" == "debug" ]]; then
  OPT_FLAGS=(-Onone -g)
fi

SOURCES=()
while IFS= read -r line; do
  SOURCES+=("$line")
done < <(find DiscordStatusModifier -name '*.swift' | sort)

mkdir -p "$BUILD_DIR"
echo "Compiling $APP_NAME ($TARGET)…"
swiftc "${SOURCES[@]}" \
  -sdk "$SDK" \
  -target "$TARGET" \
  "${OPT_FLAGS[@]}" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  -framework Foundation \
  -o "$BIN"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleDisplayName</key>
	<string>Discord Status Modifier</string>
	<key>CFBundleExecutable</key>
	<string>DiscordStatusModifier</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundleIconName</key>
	<string>AppIcon</string>
	<key>CFBundleIdentifier</key>
	<string>com.discordstatus.modifier</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>Discord Status Modifier</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.utilities</string>
	<key>LSMinimumSystemVersion</key>
	<string>14.0</string>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

cp "$BIN" "$APP/Contents/MacOS/DiscordStatusModifier"
chmod +x "$APP/Contents/MacOS/DiscordStatusModifier"

ICON_SRC="DiscordStatusModifier/Assets.xcassets/AppIcon.appiconset"
if [[ -f "$ICON_SRC/icon_1024x1024.png" ]]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"
  mkdir -p "$ICONSET" "$APP/Contents/Resources"
  cp "$ICON_SRC/icon_16x16.png" "$ICONSET/icon_16x16.png"
  cp "$ICON_SRC/icon_32x32.png" "$ICONSET/icon_16x16@2x.png"
  cp "$ICON_SRC/icon_32x32.png" "$ICONSET/icon_32x32.png"
  cp "$ICON_SRC/icon_64x64.png" "$ICONSET/icon_32x32@2x.png"
  cp "$ICON_SRC/icon_128x128.png" "$ICONSET/icon_128x128.png"
  cp "$ICON_SRC/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
  cp "$ICON_SRC/icon_256x256.png" "$ICONSET/icon_256x256.png"
  cp "$ICON_SRC/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
  cp "$ICON_SRC/icon_512x512.png" "$ICONSET/icon_512x512.png"
  cp "$ICON_SRC/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
  if ! iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    echo "Warning: iconutil failed; continuing without AppIcon.icns"
  fi
fi

if xcrun --find actool >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Resources"
  if ! xcrun actool DiscordStatusModifier/Assets.xcassets \
    --compile "$APP/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$BUILD_DIR/assetcatalog_generated_info.plist"; then
    echo "Warning: actool failed; app binary is still built"
  fi
fi

echo "Built: $APP"
echo "Open with: open \"$APP\""
