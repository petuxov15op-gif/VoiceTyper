#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
configuration="${1:-debug}"
app_dir="$project_dir/dist/VoiceTyper.app"
contents_dir="$app_dir/Contents"
binary_path="$project_dir/.build/$configuration/VoiceTyper"

cd "$project_dir"
swift build -c "$configuration"

mkdir -p "$contents_dir/MacOS" "$contents_dir/Resources"
cp "$binary_path" "$contents_dir/MacOS/VoiceTyper"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
xcrun actool "$project_dir/Resources/Assets.xcassets" \
  --compile "$contents_dir/Resources" \
  --platform macosx \
  --minimum-deployment-target 14.0 \
  --app-icon AppIcon \
  --output-partial-info-plist "$contents_dir/Resources/assetcatalog-info.plist" \
  --output-format human-readable-text
# A stable designated requirement lets macOS keep Accessibility permission
# across rebuilds. An ad-hoc signature without it is identified by a changing hash.
codesign --force --deep --sign - \
  --identifier local.voicetyper.app \
  --requirements '=designated => identifier "local.voicetyper.app"' \
  "$app_dir"

echo "$app_dir"
