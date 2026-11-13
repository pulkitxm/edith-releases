#!/usr/bin/env bash
set -euo pipefail

readonly bundle_identifier="com.pulkit.edith"
readonly expected_team="PUWDA36B2R"
readonly release_prefix="https://github.com/pulkitxm/edith-releases/releases/"
readonly appcast_url="${release_prefix}latest/download/appcast.xml"
readonly download_api_prefix="https://edith.pulkit.page/api/v1/download/"
readonly release_download_pattern='^https://github\.com/pulkitxm/edith-releases/releases/download/[A-Za-z0-9._-]+/Edith\.dmg$'
readonly support_root="$HOME/Library/Application Support/Edith"
readonly backups_dir="$support_root/backups"
readonly extensions_dir="$support_root/Extensions"
readonly health_file="$support_root/update-health.json"
readonly sandbox_dir="${EDITH_UPDATE_APP_DIR:-}"
readonly launch_disabled="${EDITH_UPDATE_NO_LAUNCH:-0}"
readonly health_timeout="${EDITH_UPDATE_HEALTH_TIMEOUT:-180}"
readonly supervised_key="EDITH_UPDATE_SUPERVISED"

dry_run=0
assume_yes=0
rollback=0
health_problem=""
work_dir=""
mount_point=""
use_sudo=0

as_owner() {
  if [[ "$use_sudo" == 1 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

say() { printf '%s\n' "$*"; }
note() { printf '  %s\n' "$*"; }
fail() {
  printf '\n%s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'USAGE'
Update Edith to the latest version.

Usage:
  curl -fsSL https://edith.pulkit.page/update_app_to_latest.sh | bash
  curl -fsSL https://edith.pulkit.page/update_app_to_latest.sh | bash -s -- --yes
  bash update.sh [--dry-run] [--yes] [--rollback]

Options:
  --dry-run   Show what would happen without changing anything.
  --yes       Answer yes to every question, for unattended runs.
  --rollback  Go back to the most recent version that worked on this Mac.
  --help      Show this help.

Your settings, data and extensions stay where they are. A copy of the
previous app is kept in ~/Library/Application Support/Edith/backups.
After updating, Edith is opened and checked. If it doesn't start
correctly, the previous version is put back automatically.
USAGE
}

cleanup() {
  if [[ -n "$mount_point" ]] && [[ -d "$mount_point" ]]; then
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 ||
      hdiutil detach "$mount_point" -force -quiet >/dev/null 2>&1 || true
  fi
  if [[ -n "$work_dir" ]] && [[ -d "$work_dir" ]]; then
    rm -rf "$work_dir"
  fi
}

parse_arguments() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --yes | -y) assume_yes=1 ;;
      --rollback) rollback=1 ;;
      --help | -h)
        usage
        exit 0
        ;;
      *)
        usage >&2
        fail "Unknown option: $1"
        ;;
    esac
    shift
  done
}

confirm() {
  local question="$1"
  local reply=""
  if [[ "$assume_yes" == 1 ]]; then
    return 0
  fi
  if ! { exec 3</dev/tty; } 2>/dev/null; then
    fail "This needs your answer, but no terminal is available. Run it again with --yes to continue without questions."
  fi
  printf '%s [y/N] ' "$question" >/dev/tty
  IFS= read -r reply <&3 || reply=""
  exec 3<&-
  [[ "$reply" == [yY] || "$reply" == [yY][eE][sS] ]]
}

check_system() {
  local architecture system_version
  architecture="$(uname -m)"
  [[ "$architecture" == arm64 ]] || fail "Edith needs a Mac with Apple silicon."
  system_version="$(sw_vers -productVersion)"
  version_at_least "$system_version" 14 || fail "Edith needs macOS 14 or later. This Mac has macOS $system_version."
}

version_at_least() {
  local -a have want
  local index have_part want_part
  IFS=. read -r -a have <<<"$1"
  IFS=. read -r -a want <<<"$2"
  for index in 0 1 2 3; do
    have_part="${have[index]:-0}"
    want_part="${want[index]:-0}"
    [[ "$have_part" =~ ^[0-9]+$ ]] || have_part=0
    [[ "$want_part" =~ ^[0-9]+$ ]] || want_part=0
    if ((10#$have_part > 10#$want_part)); then return 0; fi
    if ((10#$have_part < 10#$want_part)); then return 1; fi
  done
  return 0
}

bundle_value() {
  plutil -extract "$2" raw -o - "$1/Contents/Info.plist" 2>/dev/null || true
}

install_candidates() {
  if [[ -n "$sandbox_dir" ]]; then
    printf '%s\n' "$sandbox_dir"
  else
    printf '%s\n' "/Applications" "$HOME/Applications"
  fi
}

find_install() {
  local directory
  while IFS= read -r directory; do
    if [[ -d "$directory/Edith.app" ]]; then
      printf '%s\n' "$directory/Edith.app"
      return 0
    fi
  done < <(install_candidates)
  return 1
}

fetch() {
  curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    --retry 3 --retry-delay 2 --connect-timeout 20 "$@"
}

read_latest_release() {
  local appcast="$work_dir/appcast.xml"
  fetch --max-time 60 --output "$appcast" "$appcast_url" ||
    fail "Couldn't reach the Edith release server. Check your internet connection and try again."
  latest_version="$(grep -o '<sparkle:shortVersionString>[^<]*' "$appcast" | head -n 1 | sed 's/.*>//' || true)"
  latest_build="$(grep -o '<sparkle:version>[^<]*' "$appcast" | head -n 1 | sed 's/.*>//' || true)"
  latest_dmg_url="$(grep -o '<enclosure [^>]*' "$appcast" | head -n 1 | grep -o 'url="[^"]*"' | sed 's/^url="//; s/"$//' || true)"
  [[ "$latest_version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "The release information looks incomplete. Try again in a few minutes."
  latest_dmg_url="$(resolve_download_url "$latest_dmg_url")" ||
    fail "The release information points somewhere unexpected, so nothing was changed."
}

redirect_target() {
  curl --fail --silent --show-error --head --proto '=https' --tlsv1.2 \
    --retry 3 --retry-delay 2 --connect-timeout 20 --max-time 60 \
    --output /dev/null --write-out '%{redirect_url}' "$1"
}

resolve_download_url() {
  local url="$1"
  if [[ "$url" == "$download_api_prefix"?* ]]; then
    url="$(redirect_target "$url" 2>/dev/null)" || return 1
  fi
  [[ "$url" =~ $release_download_pattern ]] || return 1
  printf '%s\n' "$url"
}

count_extensions() {
  local count=0 entry
  if [[ -d "$extensions_dir" ]]; then
    for entry in "$extensions_dir"/*/; do
      [[ -d "$entry" ]] && count=$((count + 1))
    done
  fi
  printf '%s\n' "$count"
}

describe_extensions() {
  local count="$1"
  case "$count" in
    0) say "No extensions are installed yet." ;;
    1) say "You have 1 extension. It will be brought up to date too." ;;
    *) say "You have $count extensions. They will be brought up to date too." ;;
  esac
}

executable_pattern() {
  printf '^%s( |$)' "$(printf '%s' "$1/Contents/MacOS/Edith" | sed 's/[][\.*^$+?(){}|]/\\&/g')"
}

running_pids() {
  pgrep -f "$(executable_pattern "$1")" 2>/dev/null || true
}

wait_until_stopped() {
  local app="$1" attempts="$2"
  while ((attempts > 0)); do
    [[ -z "$(running_pids "$app")" ]] && return 0
    sleep 1
    attempts=$((attempts - 1))
  done
  [[ -z "$(running_pids "$app")" ]]
}

quit_app() {
  local app="$1" cli="$1/Contents/MacOS/ed"
  [[ -n "$(running_pids "$app")" ]] || return 0
  say "Closing Edith..."
  if [[ -x "$cli" ]] && "$cli" app quit --help 2>/dev/null | grep -- '--completely' >/dev/null; then
    "$cli" app quit --yes --completely >/dev/null 2>&1 || true
  else
    osascript -e "quit app id \"$bundle_identifier\"" >/dev/null 2>&1 || true
  fi
  wait_until_stopped "$app" 30 && return 0
  signal_app TERM "$app"
  wait_until_stopped "$app" 10 && return 0
  signal_app KILL "$app"
  wait_until_stopped "$app" 5 || fail "Edith didn't close. Quit it from the menu bar, then run this again."
}

signal_app() {
  local signal="$1" pid
  for pid in $(running_pids "$2"); do
    kill "-$signal" "$pid" 2>/dev/null || true
  done
}

process_inode() {
  lsof -a -p "$1" -d txt -Fin 2>/dev/null | awk '
    /^i/ { inode = substr($0, 2) }
    /^n.*\/Contents\/MacOS\/Edith$/ { print inode; exit }
  ' || true
}

running_current_binary() {
  local app="$1" expected pid
  expected="$(stat -f %i "$app/Contents/MacOS/Edith")"
  for pid in $(running_pids "$app"); do
    [[ "$(process_inode "$pid")" == "$expected" ]] && return 0
  done
  return 1
}

launch_app() {
  local app="$1" attempts=3 waited
  while ((attempts > 0)); do
    attempts=$((attempts - 1))
    if [[ -n "$(running_pids "$app")" ]] && ! running_current_binary "$app"; then
      quit_app "$app"
    fi
    if [[ -z "$(running_pids "$app")" ]]; then
      open --env "$supervised_key=1" "$app" >/dev/null 2>&1 || true
    fi
    waited=0
    while ((waited < 15)); do
      if running_current_binary "$app"; then
        sleep 2
        running_current_binary "$app" && return 0
      fi
      sleep 1
      waited=$((waited + 1))
    done
  done
  return 1
}

restart_app() {
  quit_app "$1"
  launch_app "$1"
}

wait_for_cli() {
  local cli="$1/Contents/MacOS/ed" attempts=60
  while ((attempts > 0)); do
    "$cli" extensions ls --json >/dev/null 2>&1 && return 0
    sleep 1
    attempts=$((attempts - 1))
  done
  return 1
}

json_count() {
  local value
  value="$(plutil -extract "$2" raw -o - "$1" 2>/dev/null || true)"
  [[ "$value" =~ ^[0-9]+$ ]] && printf '%s\n' "$value" || printf '0\n'
}

run_bounded() {
  local limit="$1" pid ticks=0
  shift
  "$@" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if ((ticks >= limit * 10)); then
      kill -TERM "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 124
    fi
    sleep 0.1
    ticks=$((ticks + 1))
  done
  wait "$pid"
}

json_strings() {
  local value list=""
  for value in "$@"; do
    [[ "$value" =~ ^[0-9A-Za-z._-]+$ ]] || continue
    list="${list:+$list,}\"$value\""
  done
  printf '[%s]\n' "$list"
}

health_record() {
  mkdir -p "$support_root"
  plutil -extract failedBuilds json -o - "$health_file" >/dev/null 2>&1 ||
    printf '{"failedBuilds":[]}\n' >"$health_file"
}

health_value() {
  plutil -extract "$1" raw -o - "$health_file" 2>/dev/null || true
}

failed_builds() {
  local index=0 build
  while build="$(plutil -extract "failedBuilds.$index" raw -o - "$health_file" 2>/dev/null)"; do
    printf '%s\n' "$build"
    index=$((index + 1))
  done
}

build_failed() {
  [[ -n "$1" ]] && failed_builds | grep -x -- "$1" >/dev/null
}

set_failed_builds() {
  health_record
  plutil -replace failedBuilds -json "$(json_strings "$@")" "$health_file" 2>/dev/null || true
}

other_failed_builds() {
  local entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && [[ "$entry" != "$1" ]] && printf '%s\n' "$entry"
  done < <(failed_builds)
}

forget_failure() {
  local kept=() entry
  build_failed "$1" || return 0
  while IFS= read -r entry; do kept+=("$entry"); done < <(other_failed_builds "$1")
  set_failed_builds ${kept[@]+"${kept[@]}"}
}

mark_failed() {
  local build="$1" kept=() entry skipped
  [[ -n "$build" ]] || return 0
  while IFS= read -r entry; do kept+=("$entry"); done < <(other_failed_builds "$build")
  set_failed_builds ${kept[@]+"${kept[@]}"} "$build"
  [[ "$(health_value healthyBuild)" == "$build" ]] && plutil -remove healthyBuild "$health_file" 2>/dev/null
  skipped="$(defaults read "$bundle_identifier" SUSkippedVersion 2>/dev/null || true)"
  if [[ -z "$skipped" ]] || ! version_at_least "$skipped" "$build"; then
    defaults write "$bundle_identifier" SUSkippedVersion -string "$build" >/dev/null 2>&1 || true
  fi
}

remember_usable_extensions() {
  local app="$1" cli="$1/Contents/MacOS/ed" listing="$work_dir/before.json" index=0 id state usable=()
  [[ -n "$(running_pids "$app")" ]] || return 0
  run_bounded 20 "$cli" extensions ls --json >"$listing" 2>/dev/null || return 0
  while id="$(plutil -extract "$index.id" raw -o - "$listing" 2>/dev/null)"; do
    state="$(plutil -extract "$index.state" raw -o - "$listing" 2>/dev/null || true)"
    if [[ "$(plutil -extract "$index.enabled" raw -o - "$listing" 2>/dev/null || true)" == true ]] &&
      { [[ "$state" == active ]] || [[ "$state" == idle ]]; }; then
      usable+=("$id")
    fi
    index=$((index + 1))
  done
  health_record
  plutil -replace usableExtensions -json "$(json_strings ${usable[@]+"${usable[@]}"})" "$health_file" 2>/dev/null || true
}

failure_reason() {
  local cli="$1/Contents/MacOS/ed" info="$work_dir/info.json" build="$2"
  if run_bounded 10 "$cli" app info --json >"$info" 2>/dev/null &&
    [[ "$(plutil -extract updateHealth.build raw -o - "$info" 2>/dev/null || true)" == "$build" ]]; then
    plutil -extract updateHealth.reason raw -o - "$info" 2>/dev/null || true
  fi
}

verify_health() {
  local app="$1" build="$2" ticks=0 gone=0 reason
  say "Checking that Edith and your extensions start..."
  health_problem=""
  while ((ticks < health_timeout)); do
    if [[ "$(bundle_value "$app" CFBundleVersion)" != "$build" ]]; then
      health_problem="Another version of Edith was put in its place while it was being checked"
      return 1
    fi
    if build_failed "$build"; then
      reason="$(failure_reason "$app" "$build")"
      health_problem="${reason:-Edith stopped responding}"
      return 1
    fi
    if running_current_binary "$app"; then
      gone=0
      [[ "$(health_value healthyBuild)" == "$build" ]] && return 0
    else
      gone=$((gone + 1))
      health_problem="It closed right after opening"
      ((gone < 10)) || return 1
    fi
    sleep 1
    ticks=$((ticks + 1))
  done
  [[ -n "$health_problem" ]] || health_problem="Edith didn't finish starting"
  return 1
}

good_backup() {
  local exclude="$1" entry build best="" best_build=""
  for entry in "$backups_dir"/Edith-*.app; do
    [[ -d "$entry" ]] || continue
    [[ "$(bundle_value "$entry" CFBundleIdentifier)" == "$bundle_identifier" ]] || continue
    build="$(bundle_value "$entry" CFBundleVersion)"
    [[ "$build" =~ ^[0-9]+$ ]] || continue
    [[ "$build" == "$exclude" ]] && continue
    build_failed "$build" && continue
    if [[ -z "$best" ]] || ((10#$build > 10#$best_build)); then
      best="$entry"
      best_build="$build"
    fi
  done
  [[ -n "$best" ]] && printf '%s\n' "$best"
}

json_keys() {
  plutil -extract "$2" raw -o - "$1" 2>/dev/null | paste -s -d ',' - | sed 's/,/, /g' || true
}

update_extensions() {
  local app="$1" cli="$1/Contents/MacOS/ed" result="$work_dir/extensions.json"
  local attempt updated current restart failed
  say "Updating extensions. This can take a few minutes..."
  if ! wait_for_cli "$app"; then
    note "Edith is still starting, so your extensions will update on their own shortly."
    return 0
  fi
  for attempt in 1 2 3; do
    if ! "$cli" extensions update --all --json >"$result" 2>"$work_dir/extensions.log"; then
      note "Extensions couldn't be checked right now. Edith will update them on its own."
      return 0
    fi
    failed="$(json_keys "$result" failed)"
    [[ -z "$failed" ]] && break
    [[ "$attempt" == 3 ]] || sleep 10
  done
  updated="$(json_count "$result" updated)"
  current="$(json_count "$result" upToDate)"
  restart="$(json_count "$result" restartRequired)"
  note "Updated: $((updated + restart)). Already current: $current."
  if [[ -n "$failed" ]]; then
    note "Not updated yet, Edith will keep trying: $failed."
  fi
  if ((restart > 0)); then
    say "Restarting Edith to finish the extension updates..."
    restart_app "$app" || note "Open Edith once more to finish the extension updates."
  fi
}

find_brew() {
  if [[ -n "$sandbox_dir" ]]; then
    printf '%s\n' "${EDITH_UPDATE_BREW:-}"
    return 0
  fi
  local candidate
  for candidate in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -n "$candidate" ]] && [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  printf '\n'
}

brew_manages_edith() {
  [[ -n "$brew" ]] && "$brew" list --cask edith >/dev/null 2>&1
}

installed_version_is_latest() {
  local version
  [[ -d "$1" ]] || return 1
  version="$(bundle_value "$1" CFBundleShortVersionString)"
  [[ -n "$version" ]] && version_at_least "$version" "$latest_version"
}

update_with_brew() {
  local app="$1"
  say "Updating through Homebrew..."
  HOMEBREW_NO_ENV_HINTS=1 "$brew" update >/dev/null 2>&1 || true
  if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "$brew" upgrade --cask --greedy edith >"$work_dir/brew.log" 2>&1 &&
    installed_version_is_latest "$app"; then
    return 0
  fi
  if HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_ENV_HINTS=1 "$brew" reinstall --cask edith >>"$work_dir/brew.log" 2>&1 &&
    installed_version_is_latest "$app"; then
    return 0
  fi
  note "Homebrew couldn't finish, so the update will be installed directly."
  return 1
}

download_release() {
  local dmg="$work_dir/Edith.dmg" proof="$work_dir/release.json"
  local proof_url="${latest_dmg_url%/Edith.dmg}/host-release-proof.json"
  local expected_sum="" proof_version actual_sum
  say "Downloading Edith $latest_version..."
  fetch --max-time 900 --output "$dmg" "$latest_dmg_url" ||
    fail "The download didn't finish. Check your internet connection and try again."
  if fetch --max-time 60 --output "$proof" "$proof_url" 2>/dev/null; then
    proof_version="$(plutil -extract version raw -o - "$proof" 2>/dev/null || true)"
    if [[ "$proof_version" == "$latest_version" ]]; then
      expected_sum="$(plutil -extract dmgSHA256 raw -o - "$proof" 2>/dev/null || true)"
    fi
  fi
  say "Checking the download..."
  if [[ -n "$expected_sum" ]]; then
    actual_sum="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
    [[ "$actual_sum" == "$expected_sum" ]] ||
      fail "The download doesn't match the published release, so nothing was changed. Try again later."
  fi
  mount_image "$dmg"
  verify_app "$mount_point/Edith.app"
  ditto "$mount_point/Edith.app" "$work_dir/Edith.app" ||
    fail "Couldn't prepare the new version, so nothing was changed."
  hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 ||
    hdiutil detach "$mount_point" -force -quiet >/dev/null 2>&1 || true
  mount_point=""
  verify_app "$work_dir/Edith.app"
}

mount_image() {
  local attached="$work_dir/attach.plist" index=0 count entry
  hdiutil attach "$1" -nobrowse -readonly -noautoopen -plist >"$attached" 2>/dev/null ||
    fail "The downloaded disk image couldn't be opened, so nothing was changed. Try again later."
  count="$(json_count "$attached" system-entities)"
  while ((index < count)); do
    entry="$(plutil -extract "system-entities.$index.mount-point" raw -o - "$attached" 2>/dev/null || true)"
    if [[ -n "$entry" ]]; then
      mount_point="$entry"
      return 0
    fi
    index=$((index + 1))
  done
  fail "The downloaded disk image couldn't be opened, so nothing was changed. Try again later."
}

verify_app() {
  local app="$1" details assessment
  local rejected="The downloaded app didn't pass its safety checks, so nothing was changed."
  [[ -d "$app" ]] || fail "$rejected"
  [[ "$(bundle_value "$app" CFBundleIdentifier)" == "$bundle_identifier" ]] || fail "$rejected"
  [[ "$(bundle_value "$app" CFBundleShortVersionString)" == "$latest_version" ]] || fail "$rejected"
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 || fail "$rejected"
  details="$(codesign -dv --verbose=2 "$app" 2>&1 || true)"
  grep -qx "TeamIdentifier=$expected_team" <<<"$details" || fail "$rejected"
  assessment="$(spctl -a -vv -t exec "$app" 2>&1 || true)"
  grep -q ': accepted' <<<"$assessment" || fail "$rejected"
  grep -q 'source=Notarized Developer ID' <<<"$assessment" || fail "$rejected"
}

owns_bundle() {
  [[ -w "$1" ]] && [[ -z "$(find "$1" ! -user "$(id -u)" -print 2>/dev/null | head -n 1)" ]]
}

ensure_writable() {
  local install_dir="$1" app="$2"
  if [[ -w "$install_dir" ]] && { [[ ! -e "$app" ]] || owns_bundle "$app"; }; then
    return 0
  fi
  say ""
  say "Your account can't change apps in $install_dir."
  if [[ "$dry_run" == 1 ]]; then
    say "The update would ask to use sudo just for copying the app."
    return 0
  fi
  if confirm "Use sudo just for copying the app? You may be asked for your password."; then
    use_sudo=1
    sudo -v || fail "sudo wasn't available, so nothing was changed."
    return 0
  fi
  fail "Nothing was changed. Ask an administrator to update Edith, or run this again and allow sudo."
}

backup_app() {
  local app="$1" version="$2" backup
  backup="$backups_dir/Edith-$version.app"
  say "Saving a copy of Edith $version in ~/Library/Application Support/Edith/backups..."
  mkdir -p "$backups_dir"
  rm -rf "$backup.partial"
  ditto "$app" "$backup.partial" || fail "Couldn't save a copy of the current version, so nothing was changed."
  rm -rf "$backup"
  mv "$backup.partial" "$backup"
  backup_path="$backup"
}

replace_app() {
  install_bundle "$1" "$work_dir/Edith.app" "$latest_version"
  installed_version_is_latest "$1" || fail "The new version didn't install correctly. A copy of the previous version is in $backups_dir."
}

install_bundle() {
  local app="$1" source="$2" version="$3" install_dir staged retired
  install_dir="$(dirname "$app")"
  staged="$install_dir/.Edith.app.updating"
  retired="$install_dir/.Edith.app.previous"
  say "Installing Edith $version..."
  as_owner rm -rf "$staged" "$retired"
  as_owner ditto "$source" "$staged" || {
    as_owner rm -rf "$staged"
    fail "Couldn't copy the new version into $install_dir, so nothing was changed."
  }
  if [[ -e "$app" ]]; then
    as_owner mv "$app" "$retired" || {
      as_owner rm -rf "$staged"
      fail "Couldn't replace the current version, so nothing was changed."
    }
  fi
  if ! as_owner mv "$staged" "$app"; then
    [[ -e "$retired" ]] && as_owner mv "$retired" "$app"
    as_owner rm -rf "$staged"
    fail "Couldn't finish installing the new version. Your previous version is still in place."
  fi
  as_owner rm -rf "$retired"
}

finish_running() {
  local app="$1" extension_count="$2" build
  if [[ "$launch_disabled" == 1 ]]; then
    ((extension_count == 0)) || say "Your extensions will update the next time Edith opens."
    return 0
  fi
  build="$(bundle_value "$app" CFBundleVersion)"
  forget_failure "$build"
  say "Opening Edith..."
  if ! launch_app "$app"; then
    health_problem="It didn't open"
    restore_after_failure "$app" "$build"
  fi
  if ((extension_count > 0)); then
    update_extensions "$app"
  fi
  verify_health "$app" "$build" || restore_after_failure "$app" "$build"
}

restore_after_failure() {
  local app="$1" build="$2" backup previous
  say ""
  say "Edith $latest_version didn't start correctly. $health_problem."
  mark_failed "$build"
  backup="$(good_backup "$build" || true)"
  if [[ -z "$backup" ]]; then
    fail "There's no earlier version on this Mac to go back to. Quit Edith and open it again, or run this again later when a newer version is out."
  fi
  previous="$(bundle_value "$backup" CFBundleShortVersionString)"
  say "Going back to Edith $previous, the version that worked before..."
  verify_backup "$backup" || fail "The saved copy of Edith $previous didn't pass its safety checks, so Edith $latest_version was left in place."
  quit_app "$app"
  install_bundle "$app" "$backup" "$previous"
  launch_app "$app" || fail "Edith $previous is back in place, but it didn't open. Open it from your Applications folder."
  say ""
  say "Edith is back on $previous. Your settings, data and extensions are unchanged."
  say "Edith won't install $latest_version again on its own. You'll get the next version when it's out."
  exit 1
}

verify_backup() {
  local app="$1" details assessment
  [[ "$(bundle_value "$app" CFBundleIdentifier)" == "$bundle_identifier" ]] || return 1
  codesign --verify --deep --strict "$app" >/dev/null 2>&1 || return 1
  details="$(codesign -dv --verbose=2 "$app" 2>&1 || true)"
  grep -qx "TeamIdentifier=$expected_team" <<<"$details" || return 1
  assessment="$(spctl -a -vv -t exec "$app" 2>&1 || true)"
  grep -q ': accepted' <<<"$assessment" || return 1
  grep -q 'source=Notarized Developer ID' <<<"$assessment"
}

roll_back() {
  local app="" current_version current_build backup previous install_dir
  app="$(find_install)" || fail "Edith isn't installed on this Mac, so there's nothing to go back from."
  [[ "$(bundle_value "$app" CFBundleIdentifier)" == "$bundle_identifier" ]] ||
    fail "The app at $app isn't Edith, so it was left alone."
  current_version="$(bundle_value "$app" CFBundleShortVersionString)"
  current_build="$(bundle_value "$app" CFBundleVersion)"
  backup="$(good_backup "$current_build" || true)"
  [[ -n "$backup" ]] || fail "There's no earlier version of Edith saved on this Mac to go back to."
  previous="$(bundle_value "$backup" CFBundleShortVersionString)"
  say "Found Edith $current_version in $(dirname "$app")."
  say "The most recent version that worked here is $previous."
  install_dir="$(dirname "$app")"
  ensure_writable "$install_dir" "$app"
  if [[ "$dry_run" == 1 ]]; then
    say ""
    say "Here's what would happen:"
    [[ "$launch_disabled" == 1 ]] || note "Close Edith."
    note "Replace $app with Edith $previous from ~/Library/Application Support/Edith/backups."
    note "Stop Edith $current_version from installing again on its own."
    [[ "$launch_disabled" == 1 ]] || note "Open Edith."
    say ""
    say "This was a dry run, so nothing was changed."
    exit 0
  fi
  say ""
  confirm "Go back from Edith $current_version to $previous now?" || fail "Nothing was changed."
  verify_backup "$backup" || fail "The saved copy of Edith $previous didn't pass its safety checks, so nothing was changed."
  [[ "$launch_disabled" == 1 ]] || quit_app "$app"
  install_bundle "$app" "$backup" "$previous"
  mark_failed "$current_build"
  if [[ "$launch_disabled" != 1 ]]; then
    say "Opening Edith..."
    launch_app "$app" || fail "Edith $previous is back in place, but it didn't open. Open it from your Applications folder."
  fi
  say ""
  say "Edith is back on $previous. Your settings, data and extensions are unchanged."
  say "Edith won't install $current_version again on its own. You'll get the next version when it's out."
  exit 0
}

print_plan() {
  local app="$1" old_version="$2" extension_count="$3" via_brew="$4"
  say ""
  say "Here's what would happen:"
  if [[ -n "$old_version" ]]; then
    if [[ "$via_brew" == 1 ]]; then
      note "Update Edith $old_version to $latest_version with Homebrew, and install the download directly if Homebrew can't."
    else
      note "Download Edith $latest_version and check it."
    fi
    [[ "$launch_disabled" == 1 ]] || note "Close Edith."
    note "Save a copy of Edith $old_version in ~/Library/Application Support/Edith/backups."
    note "Replace $app with Edith $latest_version."
  else
    note "Download Edith $latest_version, check it and install it to $app."
  fi
  if [[ "$launch_disabled" != 1 ]]; then
    note "Open Edith."
    ((extension_count > 0)) && note "Update your $extension_count extensions to their latest versions."
    note "Check that Edith and your extensions start, and put the previous version back if they don't."
  fi
  note "Your settings, data and extensions stay where they are."
  say ""
  say "This was a dry run, so nothing was changed."
}

main() {
  parse_arguments "$@"
  check_system
  work_dir="$(mktemp -d "${TMPDIR:-/tmp}/edith-update.XXXXXX")"
  trap cleanup EXIT
  trap 'exit 130' INT TERM

  if [[ "$rollback" == 1 ]]; then
    roll_back
  fi

  say "Checking for the latest version of Edith..."
  read_latest_release

  local app="" old_version="" old_build="" extension_count via_brew=0 install_dir
  if app="$(find_install)"; then
    [[ "$(bundle_value "$app" CFBundleIdentifier)" == "$bundle_identifier" ]] ||
      fail "The app at $app isn't Edith, so it was left alone."
    old_version="$(bundle_value "$app" CFBundleShortVersionString)"
    old_build="$(bundle_value "$app" CFBundleVersion)"
    say "Found Edith $old_version${old_build:+ ($old_build)} in $(dirname "$app")."
  else
    install_dir="$(install_candidates | head -n 1)"
    app="$install_dir/Edith.app"
    say "Edith isn't installed on this Mac."
  fi
  say "The latest version is $latest_version${latest_build:+ ($latest_build)}."
  extension_count="$(count_extensions)"

  if [[ -n "$old_version" ]] && version_at_least "$old_version" "$latest_version"; then
    say ""
    say "Edith $old_version is already the latest version. You're all set."
    if [[ "$dry_run" != 1 ]] && [[ "$launch_disabled" != 1 ]] && ((extension_count > 0)) &&
      [[ -n "$(running_pids "$app")" ]]; then
      update_extensions "$app"
    fi
    exit 0
  fi

  [[ -n "$old_version" ]] && describe_extensions "$extension_count"
  install_dir="$(dirname "$app")"
  [[ -d "$install_dir" ]] || fail "The folder $install_dir doesn't exist."

  brew="$(find_brew)"
  [[ -n "$old_version" ]] && brew_manages_edith && via_brew=1

  [[ "$via_brew" == 1 ]] || ensure_writable "$install_dir" "$app"
  if [[ "$dry_run" == 1 ]]; then
    print_plan "$app" "$old_version" "$extension_count" "$via_brew"
    exit 0
  fi

  say ""
  if [[ -n "$old_version" ]]; then
    confirm "Update Edith $old_version to $latest_version now?" || fail "Nothing was changed."
  else
    confirm "Install Edith $latest_version in $install_dir now?" || fail "Nothing was changed."
  fi

  backup_path=""
  [[ -n "$old_version" ]] && [[ "$launch_disabled" != 1 ]] && remember_usable_extensions "$app"
  if [[ "$via_brew" == 1 ]]; then
    [[ "$launch_disabled" == 1 ]] || quit_app "$app"
    backup_app "$app" "$old_version"
    if update_with_brew "$app"; then
      finish_running "$app" "$extension_count"
      print_summary "$old_version"
      exit 0
    fi
  fi

  [[ "$via_brew" == 1 ]] && ensure_writable "$install_dir" "$app"
  download_release
  if [[ -n "$old_version" ]]; then
    [[ "$launch_disabled" == 1 ]] || quit_app "$app"
    [[ -n "$backup_path" ]] || backup_app "$app" "$old_version"
  fi
  replace_app "$app"
  finish_running "$app" "$extension_count"
  print_summary "$old_version"
}

print_summary() {
  local old_version="$1"
  say ""
  if [[ -n "$old_version" ]]; then
    say "Edith is updated from $old_version to $latest_version."
  else
    say "Edith $latest_version is installed."
  fi
  say "Automatic updates work from now on, so you won't need to run this again."
}

latest_version=""
latest_build=""
latest_dmg_url=""
brew=""
backup_path=""

main "$@"
