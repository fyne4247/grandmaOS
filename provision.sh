#!/usr/bin/env bash
# GrandmaOS provisioning script -- reproduces the full build documented in
# /etc/grandmaos/CHANGELOG.md and HANDOFF.md on a fresh Linux Mint 22.3
# (XFCE/X11) machine. Idempotent: safe to re-run on a partially- or
# fully-provisioned box -- every phase checks current state before acting.
#
# Usage: sudo ./provision.sh [--dry-run] [--wifi-connection "NAME"]
#
# What this does NOT do (see README.md): install/configure OpenClaw (token +
# Telegram pairing are inherently interactive and personal), or set up the
# admin's own account (assumed to already exist and have sudo).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILES="$SCRIPT_DIR/files"
GRANDMA_USER="grandma"
DRY_RUN=0
WIFI_CONNECTION=""

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --wifi-connection=*) WIFI_CONNECTION="${arg#*=}" ;;
    --help|-h)
      cat <<EOF
Usage: sudo $0 [--dry-run] [--wifi-connection=NAME]

--dry-run              Print what would change without changing anything.
--wifi-connection=NAME NetworkManager connection to apply DNS blocking to.
                       If omitted, auto-detects the currently active Wi-Fi
                       connection.
EOF
      exit 0
      ;;
    *) echo "error: unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ "$EUID" -ne 0 ]; then
  echo "error: must run as root (sudo $0)" >&2
  exit 1
fi

log()   { echo "==> $*"; }
note()  { echo "    $*"; }
run()   { if [ "$DRY_RUN" -eq 1 ]; then echo "    [dry-run] $*"; else "$@"; fi; }

# ---------------------------------------------------------------------------
phase_grandma_account() {
  log "Phase: grandma account"
  if id "$GRANDMA_USER" >/dev/null 2>&1; then
    note "user '$GRANDMA_USER' already exists, skipping creation"
  else
    run useradd -m -s /bin/bash "$GRANDMA_USER"
    note "created user '$GRANDMA_USER'"
  fi

  if id "$GRANDMA_USER" 2>/dev/null | grep -qE '\b(sudo|admin)\b'; then
    echo "    !! WARNING: '$GRANDMA_USER' is in sudo/admin group -- this contradicts the whole design. Fix manually: gpasswd -d $GRANDMA_USER sudo" >&2
  else
    note "confirmed: '$GRANDMA_USER' has no sudo/admin group membership"
  fi

  # Mint's LightDM PAM policy allows passwordless/autologin sessions only for
  # members of nopasswdlogin. Without this, LightDM ignores the configured
  # autologin path and presents a password prompt for the intentionally locked
  # grandma account.
  if ! getent group nopasswdlogin >/dev/null 2>&1; then
    echo "    !! ERROR: required LightDM group 'nopasswdlogin' does not exist" >&2
    exit 1
  fi
  if id -nG "$GRANDMA_USER" 2>/dev/null | tr ' ' '\n' | grep -qx nopasswdlogin; then
    note "'$GRANDMA_USER' is already allowed to autologin"
  else
    run usermod -aG nopasswdlogin "$GRANDMA_USER"
    note "enabled passwordless LightDM autologin for '$GRANDMA_USER'"
  fi

  run loginctl enable-linger "$GRANDMA_USER"
  note "lingering enabled for '$GRANDMA_USER' (needed so root can reach her xfconf/D-Bus session via runuser without a live GUI login -- see phase_accessibility)"
}

# ---------------------------------------------------------------------------
phase_autologin() {
  log "Phase: LightDM autologin"
  local conf=/etc/lightdm/lightdm.conf
  if grep -q "^autologin-user=$GRANDMA_USER$" "$conf" 2>/dev/null; then
    note "autologin already set to '$GRANDMA_USER', skipping"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would set autologin-user=$GRANDMA_USER in $conf"
    return
  fi
  cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
  if grep -q '^autologin-user=' "$conf"; then
    sed -i "s/^autologin-user=.*/autologin-user=$GRANDMA_USER/" "$conf"
  else
    printf '\n[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\nautologin-guest=false\n' "$GRANDMA_USER" >> "$conf"
  fi
  note "set autologin-user=$GRANDMA_USER in $conf"
  note "NOTE: verify with 'lightdm --show-config' -- on some Mint installs /etc/lightdm/lightdm.conf.d/*.conf can override this depending on load order."
}

# ---------------------------------------------------------------------------
phase_install_scripts() {
  log "Phase: grandma-* maintenance scripts + launcher"
  install -d -m 0755 -o root -g root /usr/local/sbin
  for f in "$FILES"/sbin/*; do
    run install -m 0755 -o root -g root "$f" "/usr/local/sbin/$(basename "$f")"
  done
  note "installed $(ls "$FILES"/sbin | wc -l) scripts to /usr/local/sbin"

  local user_unit_share=/usr/local/share/grandmaos/systemd-user
  run install -d -m 0755 -o root -g root "$user_unit_share"
  for f in "$FILES"/systemd-user/*; do
    run install -m 0644 -o root -g root "$f" "$user_unit_share/$(basename "$f")"
  done
  note "installed optional OpenClaw user-watchdog unit templates"

  local icon_dir=/usr/local/share/grandmaos/icons
  run install -d -m 0755 -o root -g root "$icon_dir"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would fetch facebook/messenger/youtube/truist/aol favicons into $icon_dir"
  else
    for pair in "facebook.com:facebook" "messenger.com:messenger" "youtube.com:youtube" "truist.com:truist" "aol.com:aol"; do
      local domain="${pair%%:*}" name="${pair##*:}"
      if [ ! -s "$icon_dir/$name.png" ]; then
        curl -fsSL "https://www.google.com/s2/favicons?domain=${domain}&sz=128" -o "$icon_dir/$name.png" \
          && chmod 0644 "$icon_dir/$name.png" \
          || echo "    warning: failed to fetch $name.png -- launcher will fall back to a generic icon" >&2
      fi
    done
    note "icons present in $icon_dir"
  fi
}

# ---------------------------------------------------------------------------
phase_accessibility() {
  log "Phase: XFCE accessibility baseline + lock-screen elimination"
  local auto_dir="/home/$GRANDMA_USER/.config/autostart"
  run install -d -m 0755 -o root -g root "$auto_dir"
  for f in grandmaos-baseline.desktop grandmaos-launcher.desktop light-locker.desktop mintupdate.desktop xscreensaver.desktop; do
    run install -m 0644 -o root -g root "$FILES/autostart/$f" "$auto_dir/$f"
  done
  note "installed root-owned autostart overrides (grandma can read/run but not edit/delete)"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would apply and refresh the baseline in $GRANDMA_USER's live XFCE session"
    return
  fi
  local uid
  uid=$(id -u "$GRANDMA_USER")
  if [ ! -d "/run/user/$uid" ]; then
    note "waiting for /run/user/$uid (lingering session) to appear..."
    for _ in $(seq 1 10); do sleep 1; [ -d "/run/user/$uid" ] && break; done
  fi
  if [ -d "/run/user/$uid" ]; then
    GRANDMA_USER="$GRANDMA_USER" /usr/local/sbin/grandma-apply-baseline-system
    note "applied and refreshed baseline settings in $GRANDMA_USER's live session"
  else
    echo "    !! /run/user/$uid never appeared -- baseline not applied yet. It will self-apply on grandma's first login (autostart entry) and every 15min after (systemd timer, installed in phase_timers)." >&2
  fi
}

# ---------------------------------------------------------------------------
phase_chrome() {
  log "Phase: Google Chrome + locked-down, AI-disabled policy"
  local arch
  arch=$(dpkg --print-architecture)
  if [ "$arch" != "amd64" ]; then
    echo "error: the Dell Chrome target requires amd64; detected $arch" >&2
    exit 1
  fi
  # The permanent bottom dock uses wmctrl to raise existing site windows and
  # xprop to reserve desktop space. Install them even when Chrome is already
  # present on an incrementally provisioned machine.
  run apt-get install -y curl gnupg wmctrl x11-utils python3-pyatspi
  if ! command -v google-chrome-stable >/dev/null 2>&1; then
    if [ "$DRY_RUN" -eq 1 ]; then
      note "[dry-run] would install Google's signing key and Chrome apt repository"
    else
      curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
        | gpg --dearmor --yes -o /usr/share/keyrings/google-chrome.gpg
      echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
        > /etc/apt/sources.list.d/google-chrome.list
    fi
    run apt-get update
    run apt-get install -y google-chrome-stable
  else
    note "google-chrome-stable already installed, skipping"
  fi

  run install -d -m 0755 -o root -g root /etc/opt/chrome/policies/managed
  run install -m 0644 -o root -g root "$FILES/chrome-policy.json" /etc/opt/chrome/policies/managed/grandmaos.json
  note "Chrome policy installed (AI/model downloads disabled, AI surfaces hidden, only approved extensions allowed, notifications/sign-in/sync blocked, DuckDuckGo default, password manager ON)"
  note "Verify every policy after first launch at chrome://policy; unsupported future/retired keys are reported there rather than silently assumed."
  note "The launcher's Banking button opens Truist's official website."
}

# ---------------------------------------------------------------------------
phase_chrome_font_size() {
  log "Phase: Chrome accessibility font size"
  local home="/home/$GRANDMA_USER"
  local profile_dir="$home/.config/google-chrome/Default"
  local preferences="$profile_dir/Preferences"
  local default_font_size=24
  local minimum_font_size=20

  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would set Chrome's default font to ${default_font_size}px and minimum font to ${minimum_font_size}px for $GRANDMA_USER"
    note "[dry-run] would restart Grandma's Chrome only if those preferences need to change"
    return
  fi

  local needs_update
  needs_update=$(python3 - "$preferences" "$default_font_size" "$minimum_font_size" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
default_size = int(sys.argv[2])
minimum_size = int(sys.argv[3])
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except (OSError, json.JSONDecodeError):
    print("yes")
    raise SystemExit

prefs = data.get("webkit", {}).get("webprefs", {})
wanted = {
    "default_font_size": default_size,
    "default_fixed_font_size": minimum_size,
    "minimum_font_size": minimum_size,
    "minimum_logical_font_size": minimum_size,
}
print("no" if all(prefs.get(key) == value for key, value in wanted.items()) else "yes")
PY
)
  if [ "$needs_update" = no ]; then
    note "Chrome font preferences already set, skipping"
    return
  fi

  local chrome_was_running=0
  if pgrep -u "$GRANDMA_USER" -f '/opt/google/chrome/chrome' >/dev/null 2>&1; then
    chrome_was_running=1
    /usr/local/sbin/grandma-browser-restart
  fi

  install -d -m 0700 -o "$GRANDMA_USER" -g "$GRANDMA_USER" "$profile_dir"
  python3 - "$preferences" "$default_font_size" "$minimum_font_size" "$GRANDMA_USER" <<'PY'
import json
import os
import pwd
import sys
from pathlib import Path

path = Path(sys.argv[1])
default_size = int(sys.argv[2])
minimum_size = int(sys.argv[3])
username = sys.argv[4]
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"error: refusing to overwrite invalid Chrome Preferences JSON: {exc}")

webprefs = data.setdefault("webkit", {}).setdefault("webprefs", {})
webprefs.update({
    "default_font_size": default_size,
    "default_fixed_font_size": minimum_size,
    "minimum_font_size": minimum_size,
    "minimum_logical_font_size": minimum_size,
})

temporary = path.with_name(path.name + ".grandmaos-new")
temporary.write_text(json.dumps(data, separators=(",", ":")))
account = pwd.getpwnam(username)
os.chown(temporary, account.pw_uid, account.pw_gid)
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
  note "set Chrome default font to ${default_font_size}px and minimum font to ${minimum_font_size}px"

  if [ "$chrome_was_running" -eq 1 ]; then
    local uid
    uid=$(id -u "$GRANDMA_USER")
    runuser -u "$GRANDMA_USER" -- env \
      HOME="$home" \
      DISPLAY=:0 \
      XAUTHORITY="$home/.Xauthority" \
      XDG_RUNTIME_DIR="/run/user/$uid" \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" \
      setsid google-chrome-stable --no-first-run --force-renderer-accessibility \
        --start-maximized \
        --class=GrandmaOS-Facebook --app=https://www.facebook.com/ \
        >/dev/null 2>&1 &
    note "reopened Facebook after applying Chrome font preferences"
  fi
}

# ---------------------------------------------------------------------------
phase_messenger_zoom() {
  log "Phase: Messenger site-specific Chrome zoom"
  local home="/home/$GRANDMA_USER"
  local profile_dir="$home/.config/google-chrome/Default"
  local preferences="$profile_dir/Preferences"
  local zoom_level=1.2239010857415449 # Chrome's internal value for 125%.

  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would set messenger.com to 125% zoom in Grandma's main Chrome profile"
    return
  fi

  # Chrome owns Preferences while it is running. Do not interrupt an active
  # browser session or overwrite the owner's current per-site zoom experiment;
  # this setting can be initialized during a later stopped-browser provision.
  if pgrep -u "$GRANDMA_USER" -f '/opt/google/chrome/chrome' >/dev/null 2>&1; then
    note "Chrome is running; preserving its current Messenger zoom setting"
    return
  fi

  local needs_update
  needs_update=$(python3 - "$preferences" "$zoom_level" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
zoom_level = float(sys.argv[2])
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except (OSError, json.JSONDecodeError):
    print("yes")
    raise SystemExit

hosts = data.get("partition", {}).get("per_host_zoom_levels", {}).get("x", {})
zoom_matches = all(
    hosts.get(hostname, {}).get("zoom_level") == zoom_level
    for hostname in ("messenger.com", "www.messenger.com")
)
print("no" if zoom_matches else "yes")
PY
)
  if [ "$needs_update" = no ]; then
    note "Messenger site zoom already set, skipping"
    return
  fi

  install -d -m 0700 -o "$GRANDMA_USER" -g "$GRANDMA_USER" "$profile_dir"
  python3 - "$preferences" "$zoom_level" "$GRANDMA_USER" <<'PY'
import json
import os
import pwd
import sys
from pathlib import Path

path = Path(sys.argv[1])
zoom_level = float(sys.argv[2])
username = sys.argv[3]
try:
    data = json.loads(path.read_text()) if path.exists() else {}
except json.JSONDecodeError as exc:
    raise SystemExit(f"error: refusing to overwrite invalid Messenger Preferences JSON: {exc}")

hosts = (
    data.setdefault("partition", {})
        .setdefault("per_host_zoom_levels", {})
        .setdefault("x", {})
)
for hostname in ("messenger.com", "www.messenger.com"):
    hosts.setdefault(hostname, {})["zoom_level"] = zoom_level

temporary = path.with_name(path.name + ".grandmaos-new")
temporary.write_text(json.dumps(data, separators=(",", ":")))
account = pwd.getpwnam(username)
os.chown(temporary, account.pw_uid, account.pw_gid)
os.chmod(temporary, 0o600)
os.replace(temporary, path)
PY
  note "Messenger set to 125% zoom in Grandma's main Chrome profile"

}

# ---------------------------------------------------------------------------
phase_updates() {
  log "Phase: automatic updates"
  if ! dpkg -l unattended-upgrades >/dev/null 2>&1; then
    run apt-get install -y unattended-upgrades
  else
    note "unattended-upgrades already installed"
  fi

  local conf=/etc/apt/apt.conf.d/50unattended-upgrades
  local needs_update=0
  if ! grep -q 'Google LLC:stable' "$conf" || ! grep -q 'GrandmaOS additions' "$conf"; then
    needs_update=1
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$needs_update" -eq 1 ]; then
      note "[dry-run] would extend Allowed-Origins with \${distro_id}:\${distro_codename}-updates and Google LLC:stable, and set Automatic-Reboot true/WithUsers true/Time 04:30"
    else
      note "[dry-run] unattended-upgrades configuration already current"
    fi
  elif [ "$needs_update" -eq 1 ]; then
    local backup_dir=/var/backups/grandmaos/apt-config
    install -d -m 0700 -o root -g root "$backup_dir"
    cp -a "$conf" "$backup_dir/50unattended-upgrades.$(date +%Y%m%d%H%M%S)"
    if ! grep -q 'Google LLC:stable' "$conf"; then
      sed -i '/"\${distro_id}ESM:\${distro_codename}-infra-security";/a\\t"${distro_id}:${distro_codename}-updates";\n\t"Google LLC:stable";' "$conf"
    fi
    if ! grep -q 'GrandmaOS additions' "$conf"; then
      cat >> "$conf" <<'EOF'

// --- GrandmaOS additions ---
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF
    fi
    note "updated unattended-upgrades configuration (previous version saved under $backup_dir)"
  else
    note "unattended-upgrades configuration already current, skipping"
  fi
  note "Deliberately NOT enabling Remove-Unused-Dependencies / Remove-New-Unused-Dependencies:"
  note "on the original machine this would have silently auto-removed nodejs (apt saw it as"
  note "an unused auto-installed dep, but OpenClaw's live process depends on it at runtime --"
  note "invisible to apt's dependency graph). Unattended package REMOVAL is a human decision."
  if command -v node >/dev/null 2>&1 && dpkg -l nodejs >/dev/null 2>&1; then
    run apt-mark manual nodejs
    note "apt-marked nodejs manual (belt-and-suspenders against future manual autoremove)"
  fi
}

# ---------------------------------------------------------------------------
phase_timers() {
  log "Phase: systemd self-healing + backup timers"
  for u in grandmaos-baseline.service grandmaos-baseline.timer grandmaos-browser-backup.service grandmaos-browser-backup.timer; do
    run install -m 0644 -o root -g root "$FILES/systemd/$u" "/etc/systemd/system/$u"
  done
  run systemctl daemon-reload
  run systemctl enable --now grandmaos-baseline.timer
  run systemctl enable --now grandmaos-browser-backup.timer
  note "baseline reasserts every 15min; browser backup runs hourly, keeps 14 generations"
}

# ---------------------------------------------------------------------------
phase_dns() {
  log "Phase: DNS-level ad/scam blocking (AdGuard Family Protection)"
  local conn="$WIFI_CONNECTION"
  if [ -z "$conn" ]; then
    conn=$(nmcli -t -f NAME,TYPE connection show --active 2>/dev/null | awk -F: '$2=="802-11-wireless"{print $1; exit}')
  fi
  if [ -z "$conn" ]; then
    echo "    !! no active Wi-Fi connection found/specified -- skipping DNS blocking. Re-run with --wifi-connection=\"NAME\" once connected." >&2
    return
  fi
  note "target connection: $conn"
  run nmcli connection modify "$conn" ipv4.dns "94.140.14.15 94.140.15.16"
  run nmcli connection modify "$conn" ipv4.ignore-auto-dns yes
  run nmcli connection modify "$conn" ipv6.dns "2a10:50c0::bad1:ff 2a10:50c0::bad2:ff"
  run nmcli connection modify "$conn" ipv6.ignore-auto-dns yes
  run nmcli connection up "$conn"
  note "NOTE: this also enforces Google SafeSearch machine-wide -- affects every account, not just grandma's."
}

# ---------------------------------------------------------------------------
phase_grub() {
  log "Phase: GRUB -- never show menu, including after unclean shutdown"
  local conf=/etc/default/grub
  if grep -q '^GRUB_RECORDFAIL_TIMEOUT=' "$conf" 2>/dev/null; then
    note "GRUB_RECORDFAIL_TIMEOUT already set, skipping"
  elif [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would add GRUB_RECORDFAIL_TIMEOUT=0 to $conf and run update-grub"
  else
    cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)"
    if grep -q '^GRUB_TIMEOUT_STYLE=' "$conf"; then
      : # fine as-is
    else
      echo 'GRUB_TIMEOUT_STYLE=hidden' >> "$conf"
    fi
    if grep -q '^GRUB_TIMEOUT=' "$conf"; then
      sed -i '/^GRUB_TIMEOUT=/a GRUB_RECORDFAIL_TIMEOUT=0' "$conf"
    else
      echo 'GRUB_RECORDFAIL_TIMEOUT=0' >> "$conf"
    fi
    run update-grub
  fi
  note "clean boots: hidden by GRUB_TIMEOUT_STYLE=hidden. Unclean-shutdown boots: hidden by GRUB_RECORDFAIL_TIMEOUT=0."
  note "Admin emergency access: hold Shift / tap Esc from power-on -- unaffected by this."
}

# ---------------------------------------------------------------------------
log "GrandmaOS provisioning starting$( [ "$DRY_RUN" -eq 1 ] && echo ' (DRY RUN -- no changes will be made)' )"
phase_grandma_account
phase_autologin
phase_install_scripts
phase_accessibility
phase_chrome
phase_chrome_font_size
phase_messenger_zoom
phase_updates
phase_timers
phase_dns
phase_grub

log "Done."
note "NOT automated (see README.md): OpenClaw setup, audio (worked out of the box on the original hardware -- re-check on new hardware with grandma-audio-status), a reboot to activate autologin."
