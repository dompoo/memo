#!/bin/sh
set -e
cd "$(dirname "$0")"
mkdir -p Memo.app/Contents/MacOS Memo.app/Contents/Resources
cat Memo.icns > Memo.app/Contents/Resources/Memo.icns  # cp는 내려받은 파일의 격리 표시까지 앱에 옮긴다
swiftc -O -parse-as-library Memo.swift -o Memo.app/Contents/MacOS/Memo
cat > Memo.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Memo</string>
<key>CFBundleIconFile</key><string>Memo</string>
<key>CFBundleIdentifier</key><string>local.memo</string>
<key>CFBundleName</key><string>Memo</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
</dict></plist>
EOF
# 이름만 같은 다른 앱은 지우지 않는다
if [ -d /Applications/Memo.app ] && [ "$(defaults read /Applications/Memo.app/Contents/Info CFBundleIdentifier 2>/dev/null)" != local.memo ]; then
    echo "/Applications에 다른 Memo.app이 있어서 설치를 멈췄어요" >&2
    exit 1
fi
pkill -x Memo || true
rm -rf /Applications/Memo.app
cp -R Memo.app /Applications/
open /Applications/Memo.app
echo "installed: /Applications/Memo.app"
