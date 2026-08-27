#!/bin/zsh

# Safely commits and publishes non-sensitive VoiceTyper changes.
set -euo pipefail

project_dir="/Users/makspetuhov/Documents/ChatGPT/голосовой помощник"
lock_dir="/private/tmp/voicetyper-github-sync.lock"

if ! mkdir "$lock_dir" 2>/dev/null; then
  exit 0
fi
trap 'rmdir "$lock_dir"' EXIT

cd -P "$project_dir"

git fetch origin main

ahead_count=$(git rev-list --count origin/main..HEAD)
behind_count=$(git rev-list --count HEAD..origin/main)

if (( behind_count > 0 )); then
  print -u2 'Refusing to publish because origin/main has newer commits.'
  exit 1
fi

if [[ -z "$(git status --porcelain)" ]]; then
  if (( ahead_count > 0 )); then
    git push origin main
  fi
  exit 0
fi

changed_paths=$( { git diff --name-only; git ls-files --others --exclude-standard; } | sort -u )

if print -r -- "$changed_paths" | grep -Eiq '(^|/)(\.env($|\.)|.*\.(pem|key|p12|pfx|crt|cer)$|.*(secret|token|credential|password|vpn|wireguard|openvpn).*)|(^|/)(\.venv|venv|__pycache__)(/|$)|(^|/).+\.(sqlite|sqlite3|db|log)$'; then
  print -u2 'Refusing to publish a sensitive-looking path.'
  exit 1
fi

if print -r -- "$changed_paths" | grep -Eq '^(Sources/|Tests/|Package\.swift$|Package\.resolved$)'; then
  swift test
fi

git add --all

if [[ -z "$(git diff --cached --name-only)" ]]; then
  exit 0
fi

git commit -m "chore: sync local changes"
git push origin main
