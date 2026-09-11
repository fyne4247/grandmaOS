# GrandmaOS provisioning bundle

Reproduces the GrandmaOS build (see `/etc/grandmaos/CHANGELOG.md` and
`HANDOFF.md` on the original machine) on a fresh Linux Mint 22.3 (XFCE, X11)
laptop.

## Use on a new machine

1. Do normal Mint setup first: create the admin account, connect to Wi-Fi,
   let it boot to a working desktop.
2. Copy this whole `provisioning/` directory onto the new machine (USB
   stick, scp, whatever).
3. `cd provisioning && sudo ./provision.sh`
   - Add `--dry-run` first to preview every change with no side effects.
   - Add `--wifi-connection="Your SSID"` if you want DNS blocking applied to
     a connection other than whichever one is currently active.
4. Reboot. Grandma's account should autologin straight into the launcher,
   locked down, no lock screen, no admin authority.
5. Do the manual steps below.

The script is idempotent -- re-running it on an already-provisioned machine
only touches what's missing or different; it won't recreate the grandma
account, re-add the Brave repo, etc. if they're already there.

## What it automates

- `grandma` system account (no sudo/admin group), lingering enabled so root
  can reach her session non-interactively (needed for the next item)
- LightDM autologin as `grandma`
- All `grandma-*` maintenance/diagnostic scripts to `/usr/local/sbin`
- XFCE accessibility baseline (large text/cursor, high-contrast theme) and
  full lock-screen elimination (3 mechanisms: LockCommand, power-manager
  suspend-lock, light-locker/xscreensaver autostart disabled) for grandma
  only -- never touches the admin's own session/theme
- The big-button launcher (Facebook / YouTube / Internet / Banking
  placeholder), auto-relaunching if closed
- Brave browser + an enterprise policy (extensions blocked, password
  manager forced ON since she doesn't reliably remember passwords,
  notifications off, no guest/second-profile, Shields locked on for the
  launcher's known sites)
- Automatic updates via `unattended-upgrades`, covering both the Mint/Ubuntu
  archives and Brave's own repo, with a scheduled 4:30am reboot so patches
  actually take effect
- Self-healing systemd timers: the accessibility/lock-screen baseline
  reasserts every 15 minutes (catches mid-session drift, not just login),
  browser profile backs up hourly (SQLite-safe, 14 generations kept)
- DNS-level ad/scam/malware blocking (AdGuard Family Protection) on the
  active Wi-Fi connection
- GRUB never shows its menu, including after a crash/unclean shutdown

## What it deliberately does NOT automate

- **OpenClaw** (remote control via Telegram). This needs a bot token from
  @BotFather and pairing your own Telegram account -- inherently
  interactive and tied to your personal credentials, not something to bake
  into a script. On the new machine: install per openclaw.ai's own
  installer, `openclaw channels add --channel telegram --token <token>`,
  pair yourself, then `openclaw daemon install` + `loginctl enable-linger
  <admin-user>` for persistence. (On the original machine, `openclaw daemon
  install` refused to run because `~/.config/systemd/user` was
  group-writable -- fix with `chmod go-w` on exactly that directory if you
  hit the same thing; don't sudo/recursive-chmod around it.)
- **The Banking launcher button.** Ships disabled/greyed out. Once you have
  the real bank login URL, edit the `bank_btn` line in
  `/usr/local/sbin/grandma-launcher` (see the other `SITES` entries for the
  pattern) and re-run `grandma-launcher-supervisor` or just wait for
  grandma's next login.
- **Audio.** On the original hardware (Intel Raptor Lake-U + ALC256, PipeWire
  stack) everything worked out of the box, so there was nothing to
  provision. On new hardware, run `grandma-audio-status` after first boot
  and only chase it if something's actually wrong -- don't assume the same
  fix path applies to different audio hardware.
- **The admin's own account/sudo/SSH access.** Assumed to already exist.
- **Package removal of any kind, ever, unattended.** `Remove-Unused-
  Dependencies` is deliberately never enabled in the unattended-upgrades
  config -- see the comment in `phase_updates()` in `provision.sh` for why
  (it would have silently removed OpenClaw's Node.js runtime on the
  original machine, since apt's dependency graph has no idea a live process
  depends on it at runtime).

## Files

- `provision.sh` -- the orchestrator, one function per phase.
- `files/sbin/` -- all `grandma-*` scripts, installed verbatim to
  `/usr/local/sbin`.
- `files/autostart/` -- root-owned XDG autostart entries (baseline
  reassertion, the launcher, and Hidden=true overrides that disable
  light-locker/xscreensaver for grandma only).
- `files/systemd/` -- the two timer/service pairs (baseline reassertion,
  browser backup).
- `files/brave-policy.json` -- installed to
  `/etc/brave/policies/managed/policy.json`.

Icons for the launcher (Facebook/Messenger/YouTube favicons) are fetched
fresh from Google's public favicon proxy at provision time rather than
bundled, to keep this directory small and avoid shipping stale logos.
