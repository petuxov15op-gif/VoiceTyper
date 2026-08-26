#!/bin/zsh
set -euo pipefail

app_path="/Applications/VoiceTyper.app"
diagnostic_dir=$(mktemp -d /private/tmp/voicetyper-e2e-XXXXXX)
diagnostic_name="$(basename "$diagnostic_dir").txt"
diagnostic_path="$diagnostic_dir/$diagnostic_name"
touch "$diagnostic_path"

cleanup() {
  osascript \
    -e 'tell application "TextEdit"' \
    -e "if exists document \"$diagnostic_name\" then close document \"$diagnostic_name\" saving no" \
    -e 'end tell' >/dev/null 2>&1 || true
  rm -rf "$diagnostic_dir"
}
trap cleanup EXIT

if ! pgrep -f "$app_path/Contents/MacOS/VoiceTyper" >/dev/null; then
  open -n "$app_path"
  sleep 2
fi

open -a TextEdit "$diagnostic_path"
sleep 1

document_length() {
  osascript \
    -e 'tell application "TextEdit"' \
    -e "set docText to text of document \"$diagnostic_name\" as string" \
    -e 'return length of docText' \
    -e 'end tell'
}

wait_for_length_greater_than() {
  integer previous_count="$1"
  local attempt
  for attempt in {1..60}; do
    integer observed_count
    observed_count=$(document_length)
    if (( observed_count > previous_count )); then
      print -r -- "$observed_count"
      return 0
    fi
    sleep 1
  done
  return 1
}

document_text() {
  osascript \
    -e 'tell application "TextEdit"' \
    -e "return text of document \"$diagnostic_name\" as string" \
    -e 'end tell'
}

run_dictation() {
  local phrase="$1"
  osascript -e 'tell application "TextEdit" to activate' -e 'delay 0.3'
  osascript -e 'tell application "System Events" to key code 49 using option down'
  sleep 1
  say -v Milena "$phrase"
  osascript -e 'tell application "System Events" to key code 49 using option down'
}

initial_length=$(document_length)
run_dictation 'Проверка связи, привет.'
first_length=$(wait_for_length_greater_than "$initial_length") || {
  print -u2 -- "FAIL: первая запись распознана в буфер, но не вставлена: $(pbpaste)"
  exit 1
}
first_text=$(document_text)
first_text_lower="${(L)first_text}"
if [[ "$first_text_lower" != *"проверка"* || "$first_text_lower" != *"связи"* || "$first_text_lower" != *"привет"* ]]; then
  print -u2 -- "FAIL: неверно распознана первая фраза: $first_text"
  exit 1
fi

run_dictation 'Вторая проверка локальной диктовки.'
second_length=$(wait_for_length_greater_than "$first_length") || {
  print -u2 -- "FAIL: вторая запись распознана в буфер, но не вставлена: $(pbpaste)"
  exit 1
}

if ! pgrep -f "$app_path/Contents/MacOS/VoiceTyper" >/dev/null; then
  print -u2 -- "FAIL: VoiceTyper завершился во время двух последовательных диктовок"
  exit 1
fi

print -r -- "PASS: first_text='$first_text' first_length=$first_length second_length=$second_length"
