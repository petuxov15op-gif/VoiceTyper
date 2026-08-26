#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
info_plist="$project_dir/Resources/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
app_path="$project_dir/dist/VoiceTyper.app"
archive_path="$project_dir/dist/VoiceTyper-${version}-unsigned.zip"

"$project_dir/scripts/package-app.sh" release
rm -f "$archive_path"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive_path"

echo "$archive_path"
