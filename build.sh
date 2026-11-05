#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BINS=()
for TRIPLE in arm64-apple-macosx14.0 x86_64-apple-macosx14.0; do
    swift build -c release --triple "$TRIPLE"
    BIN_DIR=$(swift build -c release --triple "$TRIPLE" --show-bin-path)
    cp "$BIN_DIR/NotchBar" ".build/NotchBar-${TRIPLE%%-*}"
    BINS+=(".build/NotchBar-${TRIPLE%%-*}")
done

APP="build/NotchBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${BINS[@]}" -output "$APP/Contents/MacOS/NotchBar"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "✅ Listo: $APP"
echo "   Ejecuta: open $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x NotchBar 2>/dev/null || true
    rm -rf /Applications/NotchBar.app
    cp -R "$APP" /Applications/
    open /Applications/NotchBar.app
    echo "📦 Instalada en /Applications/NotchBar.app"
fi
