#!/usr/bin/env bash
# GrandmaOS provisioning script -- reproduces the full build documented in
# /etc/grandmaos/CHANGELOG.md and HANDOFF.md on a fresh Linux Mint 22.3
# (XFCE/X11) machine. Idempotent: safe to re-run on a partially- or
# fully-provisioned box -- every phase checks current state before acting.
#
# Usage: sudo ./provision.sh [--dry-run] [--wifi-connection "NAME"]
#
# What this does NOT do (see README.md): install/configure OpenClaw (token +
# Telegram pairing are inherently interactive and personal), set a real
# Banking launcher URL (edit files/sbin/grandma-launcher's SITES-adjacent
# bank_btn line yourself first, or re-run with BANK_URL set), or set up the
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

  local icon_dir=/usr/local/share/grandmaos/icons
  run install -d -m 0755 -o root -g root "$icon_dir"
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would fetch facebook/messenger/youtube favicons into $icon_dir"
  else
    for pair in "facebook.com:facebook" "messenger.com:messenger" "youtube.com:youtube"; do
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
  for f in grandmaos-baseline.desktop grandmaos-launcher.desktop light-locker.desktop xscreensaver.desktop; do
    run install -m 0644 -o root -g root "$FILES/autostart/$f" "$auto_dir/$f"
  done
  note "installed root-owned autostart overrides (grandma can read/run but not edit/delete)"

  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would run grandma-apply-baseline as $GRANDMA_USER via runuser"
    return
  fi
  local uid
  uid=$(id -u "$GRANDMA_USER")
  if [ ! -d "/run/user/$uid" ]; then
    note "waiting for /run/user/$uid (lingering session) to appear..."
    for _ in $(seq 1 10); do sleep 1; [ -d "/run/user/$uid" ] && break; done
  fi
  if [ -d "/run/user/$uid" ]; then
    runuser -u "$GRANDMA_USER" -- env XDG_RUNTIME_DIR="/run/user/$uid" /usr/local/sbin/grandma-apply-baseline
    note "applied baseline xfconf settings for $GRANDMA_USER"
  else
    echo "    !! /run/user/$uid never appeared -- baseline not applied yet. It will self-apply on grandma's first login (autostart entry) and every 15min after (systemd timer, installed in phase_timers)." >&2
  fi
}

# ---------------------------------------------------------------------------
phase_brave() {
  log "Phase: Brave browser + policy"
  if ! command -v brave-browser >/dev/null 2>&1; then
    run curl -fsSL https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
      -o /usr/share/keyrings/brave-browser-archive-keyring.gpg
    if [ "$DRY_RUN" -eq 0 ]; then
      echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
        > /etc/apt/sources.list.d/brave-browser-release.list
    fi
    run apt-get update
    run apt-get install -y brave-browser
  else
    note "brave-browser already installed, skipping"
  fi

  run install -d -m 0755 -o root -g root /etc/brave/policies/managed
  run install -m 0644 -o root -g root "$FILES/brave-policy.json" /etc/brave/policies/managed/policy.json
  note "Brave policy installed (extensions blocked, notifications off, password manager forced ON, guest/add-person off, Shields locked on for facebook/messenger/youtube)"
  note "REMINDER: launcher's Banking button is a disabled placeholder until you edit /usr/local/sbin/grandma-launcher with a real bank URL."
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
  if [ "$DRY_RUN" -eq 1 ]; then
    note "[dry-run] would extend Allowed-Origins with \${distro_id}:\${distro_codename}-updates and Brave Software:stable, and set Automatic-Reboot true/WithUsers true/Time 04:30"
  else
    cp "$conf" "${conf}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    if ! grep -q 'Brave Software:stable' "$conf"; then
      sed -i '/"\${distro_id}ESM:\${distro_codename}-infra-security";/a\\t"${distro_id}:${distro_codename}-updates";\n\t"Brave Software:stable";' "$conf"
    fi
    if ! grep -q 'GrandmaOS additions' "$conf"; then
      cat >> "$conf" <<'EOF'

// --- GrandmaOS additions ---
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "04:30";
EOF
    fi
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
phase_brave
phase_updates
phase_timers
phase_dns
phase_grub

log "Done."
note "NOT automated (see README.md): OpenClaw setup, real Banking URL, audio (worked out of the box on the original hardware -- re-check on new hardware with grandma-audio-status), a reboot to activate autologin."
