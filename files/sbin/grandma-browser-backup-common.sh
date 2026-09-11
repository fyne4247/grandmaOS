#!/usr/bin/env bash
# Shared configuration + helper functions for grandma-browser-backup,
# grandma-browser-backups and grandma-browser-restore.
#
# ADAPTED FOR BRAVE (Chromium-family), not Firefox -- see NOTES.md for why
# the browser choice changed. The original Firefox-oriented draft's design
# (SQLite-safe .backup, atomic mv, root-owned 0700 store, strict generation
# validation) is preserved; only profile-location and SQLite-detection logic
# changed, since Chromium's on-disk layout differs from Firefox's in two
# important ways:
#   1. Chromium's SQLite databases have NO ".sqlite" extension (they're
#      named "Cookies", "History", "Login Data", "Web Data", "Favicons",
#      etc.), so we can't glob by extension -- we detect real SQLite files
#      by magic-byte signature instead. This is also more version-proof:
#      Chromium has moved "Cookies" into a "Network/" subdirectory in some
#      releases, and magic-byte detection doesn't care where a file lives.
#   2. Chromium's active profile is found via the top-level "Local State"
#      JSON file (key: profile.last_used), not an INI like Firefox's
#      profiles.ini.
#
# This file is *sourced*, never executed directly, so all three tools agree
# on where backups live, what a generation directory name looks like, and
# how logging/status works.

# --- fixed configuration ---
GRANDMA_USER="${GRANDMA_USER:-grandma}"

# Root-owned, mode 0700, outside grandma's home. grandma has no sudo and no
# write access here at all -- see NOTES.md "Backup location & permissions".
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/grandmaos/brave}"

# Small piece of shared GrandmaOS state: just a timestamp file that other
# grandma-* tools (grandma-status) already expect at this exact path:
#   BACKUP_TIMESTAMP_FILE="/var/lib/grandmaos/last-browser-backup"
#   last=$(stat -c %Y "$BACKUP_TIMESTAMP_FILE")
# i.e. it reads the file's *mtime*, not its contents, and runs unprivileged.
# So this file must stay world-readable even though the backups themselves
# must not be.
STATE_DIR="/var/lib/grandmaos"
STATUS_FILE="$STATE_DIR/last-browser-backup"

LOG_DIR="/var/log/grandmaos"
LOG_FILE="$LOG_DIR/browser-backup.log"

# Keep the last 14 daily generations (~2 weeks).
KEEP_N="${KEEP_N:-14}"

# How many "pre-restore" safety snapshots (taken automatically by
# grandma-browser-restore before it overwrites the live profile) to keep.
PRERESTORE_KEEP_N="${PRERESTORE_KEEP_N:-3}"

# Generation directory names are exactly "YYYYMMDD-HHMMSS". Every path built
# from user-supplied input is checked against this pattern -- and then
# re-derived only from a name confirmed to actually exist directly under
# BACKUP_ROOT -- before it is ever used in an rm/cp/path construction.
GEN_NAME_RE='^[0-9]{8}-[0-9]{6}$'
PRERESTORE_NAME_RE='^pre-restore-[0-9]{8}-[0-9]{6}$'

# Directories inside a Chromium/Brave profile that are pure, regenerable
# cache data -- never logins, cookies, bookmarks or history. Excluding them
# keeps backups small and fast.
PROFILE_EXCLUDE_DIRS=(Cache "Code Cache" GPUCache "Service Worker"
  "Session Storage" blob_storage "GrShaderCache" "ShaderCache"
  component_crx_cache extensions_crx_cache CrashpadMetrics)

# ---------------------------------------------------------------------------
# logging
# ---------------------------------------------------------------------------
gbb_log() {
  local level="$1"; shift
  local msg="$*"
  local line
  line="$(date '+%Y-%m-%d %H:%M:%S%z') [$level] $msg"
  mkdir -p "$LOG_DIR" 2>/dev/null
  chmod 750 "$LOG_DIR" 2>/dev/null
  chown root:root "$LOG_DIR" 2>/dev/null
  echo "$line" >>"$LOG_FILE" 2>/dev/null
  chmod 640 "$LOG_FILE" 2>/dev/null
  if command -v logger >/dev/null 2>&1; then
    logger -t grandma-browser-backup -p "user.${level}" -- "$msg" 2>/dev/null \
      || logger -t grandma-browser-backup -- "$msg" 2>/dev/null || true
  fi
}

gbb_die() {
  gbb_log "err" "$*"
  echo "error: $*" >&2
  exit 1
}

require_root() {
  local prog="$1" reason="$2"
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "error: $prog requires root ($reason)" >&2
    exit 1
  fi
}

# ---------------------------------------------------------------------------
# locate the grandma user's active Brave profile
# ---------------------------------------------------------------------------
# Chromium/Brave's "Local State" JSON (one level above the profile
# directories) records which profile directory name is the currently active
# one under profile.last_used, e.g. "Default" or "Profile 1". We parse that
# rather than assuming "Default", though on this single-user appliance it
# will always be "Default" in practice (profile creation is locked out via
# Brave policy -- see firefox-policy sibling directory's BrowserAddPerson
# equivalent for Brave in the policy draft).
#
# Prints the resolved absolute profile directory path on stdout and returns
# 0 on success. On failure, prints a machine-readable "REASON:detail" token
# and returns 1 -- callers turn that into a human message.
find_grandma_profile_dir() {
  local home userdatadir localstate lastused

  if ! id "$GRANDMA_USER" >/dev/null 2>&1; then
    echo "NO_SUCH_USER:$GRANDMA_USER"
    return 1
  fi

  home=$(getent passwd "$GRANDMA_USER" | cut -d: -f6)
  [ -z "$home" ] && home="/home/$GRANDMA_USER"
  userdatadir="$home/.config/BraveSoftware/Brave-Browser"
  localstate="$userdatadir/Local State"

  if [ ! -f "$localstate" ]; then
    echo "LOCAL_STATE_MISSING:$localstate"
    return 1
  fi

  # Minimal JSON field extraction (no jq dependency, matching the plain
  # grep/sed style used elsewhere in this toolset). profile.last_used is a
  # flat string value in Local State.
  lastused="$(grep -oE '"last_used"[[:space:]]*:[[:space:]]*"[^"]*"' "$localstate" 2>/dev/null \
    | head -1 | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/')"

  if [ -z "$lastused" ]; then
    # Fall back to "Default" if Local State exists but doesn't (yet) record
    # last_used -- this is normal on a brand new, never-actually-opened
    # profile created only by a first-run/headless initialization.
    lastused="Default"
  fi

  local dir="$userdatadir/$lastused"
  if [ ! -d "$dir" ]; then
    echo "PROFILE_DIR_MISSING:$dir"
    return 1
  fi

  echo "$dir"
  return 0
}

# ---------------------------------------------------------------------------
# strict validation / resolution of user-supplied generation identifiers
# ---------------------------------------------------------------------------
validate_generation_name() {
  [[ "$1" =~ $GEN_NAME_RE ]]
}

validate_prerestore_name() {
  [[ "$1" =~ $PRERESTORE_NAME_RE ]]
}

list_generations_sorted() {
  [ -d "$BACKUP_ROOT" ] || return 0
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E "$GEN_NAME_RE" | sort -r
}

list_prerestore_sorted() {
  [ -d "$BACKUP_ROOT" ] || return 0
  find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
    | grep -E "$PRERESTORE_NAME_RE" | sort -r
}

# Resolve a user-supplied argument to a real, existing directory name under
# BACKUP_ROOT. Accepts either:
#   - a 1-based index into `list_generations_sorted` (1 = newest), or
#   - an exact "YYYYMMDD-HHMMSS" generation name, or
#   - an exact "pre-restore-YYYYMMDD-HHMMSS" safety-snapshot name.
# Never does string concatenation of the raw argument into a path -- only
# ever returns a name that was independently discovered on disk and matched
# a strict pattern.
resolve_generation_arg() {
  local arg="$1"
  local -a gens=()
  while IFS= read -r d; do gens+=("$d"); done < <(list_generations_sorted)

  if [[ "$arg" =~ ^[0-9]+$ ]]; then
    local idx=$((10#$arg))
    if [ "$idx" -ge 1 ] && [ "$idx" -le "${#gens[@]}" ]; then
      echo "${gens[$((idx - 1))]}"
      return 0
    fi
    return 1
  fi

  if validate_generation_name "$arg"; then
    local d
    for d in "${gens[@]}"; do
      [ "$d" = "$arg" ] && { echo "$d"; return 0; }
    done
    return 1
  fi

  if validate_prerestore_name "$arg"; then
    local -a pre=()
    while IFS= read -r d; do pre+=("$d"); done < <(list_prerestore_sorted)
    local d
    for d in "${pre[@]}"; do
      [ "$d" = "$arg" ] && { echo "$d"; return 0; }
    done
    return 1
  fi

  return 1
}

manifest_field() {
  local file="$1" field="$2"
  [ -f "$file" ] || return 1
  grep -m1 -oE "\"$field\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null \
    | sed -E 's/.*:[[:space:]]*"([^"]*)"/\1/'
}

# Is a Brave process currently running for the grandma user? The installed
# package provides /usr/bin/brave-browser (a wrapper) which execs the real
# binary; checked candidate names cover both the wrapper and the real
# binary name across Brave package versions.
grandma_brave_pids() {
  local candidates="brave brave-browser brave-browser-stable"
  local c found
  for c in $candidates; do
    found=$(pgrep -u "$GRANDMA_USER" -x "$c" 2>/dev/null || true)
    if [ -n "$found" ]; then
      echo "$found"
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# magic-byte SQLite detection
# ---------------------------------------------------------------------------
# Chromium SQLite databases (Cookies, History, "Login Data", "Web Data",
# Favicons, "Top Sites", Shortcuts, ...) have no distinguishing file
# extension, and their exact sub-path within the profile has moved between
# Chromium releases (e.g. Cookies -> Network/Cookies). Rather than hardcode
# a filename/path list that will silently go stale, we identify real SQLite
# files by their standard 16-byte magic header ("SQLite format 3\0"), which
# is stable across all SQLite versions and applies safely to ANY file in the
# profile, regardless of name or location.
is_sqlite_file() {
  local f="$1" magic
  [ -f "$f" ] && [ -s "$f" ] || return 1
  magic="$(head -c 16 "$f" 2>/dev/null | tr -d '\0')"
  [[ "$magic" == "SQLite format 3" ]]
}
