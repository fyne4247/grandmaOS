# GrandmaOS provisioning bundle

Reproduces the GrandmaOS build (see `/etc/grandmaos/CHANGELOG.md` and
`HANDOFF.md` on the original machine) on a fresh Linux Mint 22.3 (XFCE, X11)
laptop. The primary target is now the 2026 Dell XPS 13 touchscreen configuration
documented in [`hardware/dell-xps-13-2026/`](hardware/dell-xps-13-2026/README.md).
The checked-in bundle was built for a Samsung 750GX-era installation; an even
earlier prototype ran on a ThinkPad 100e Chromebook. Neither machine is a
supported configuration source for the Dell: do not copy the Chromebook's
firmware/audio workarounds or infer Dell support from hardware that happened to
work normally on the Samsung.

## Use on a new machine

If Codex or another coding agent will perform the installation, open this
repository on the new machine and ask it to follow [`AGENTS.md`](AGENTS.md).
That file provides the complete guarded handoff from a working Mint desktop
through GrandmaOS provisioning, hardware verification, and the interactive
OpenClaw setup. OpenClaw cannot perform this initial handoff before OpenClaw
itself has been installed; Codex can.

Codex command approvals are separate from Linux `sudo`. To avoid approving each
command, deliberately start the local Codex task with its session/full-access
permission option, then give it the prompt above. The repository does not add a
passwordless unrestricted sudo rule; the provisioner already performs its
system changes through one auditable `sudo ./provision.sh` invocation.

For the lowest-interaction complete bootstrap, run this yourself from the
repository root:

```sh
sudo ./bootstrap-grandmaos
```

That one command previews and applies GrandmaOS, saves a read-only hardware
report, installs OpenClaw with its official rootless local-prefix installer,
runs interactive onboarding as the administrator, installs the user gateway,
enables lingering, and enables the GrandmaOS watchdog. It pauses for real
credentials and pairing but does not require an agent to issue a long sequence
of separately approved root commands. Use `--skip-openclaw` to provision only
GrandmaOS or `--wifi-connection="NAME"` to select a specific connection.

1. Do normal Mint setup first: create the admin account, connect to Wi-Fi,
   let it boot to a working desktop.
2. Copy this whole `provisioning/` directory onto the new machine (USB
   stick, scp, whatever).
3. `cd provisioning && sudo ./provision.sh`
   - Add `--dry-run` first to preview every change with no side effects.
   - Add `--wifi-connection="Your SSID"` if you want DNS blocking applied to
     a connection other than whichever one is currently active.
4. Reboot. Grandma's account should autologin with the permanent bottom dock
   visible and Facebook already open in Chrome, with no lock screen or admin
   authority.
5. Do the manual steps below.

The script is idempotent -- re-running it on an already-provisioned machine
only touches what's missing or different; it won't recreate the grandma
account, re-add the Chrome repo, etc. if they're already there.

## What it automates

- `grandma` system account (no sudo/admin group), lingering enabled so root
  can reach her session non-interactively (needed for the next item)
- LightDM autologin as `grandma`
- All `grandma-*` maintenance/diagnostic scripts to `/usr/local/sbin`
- XFCE accessibility baseline (20-point high-DPI text, large cursor/panel/icons,
  high-contrast theme) and
  full lock-screen elimination (3 mechanisms: LockCommand, power-manager
  suspend-lock, light-locker/xscreensaver autostart disabled) for grandma
  only -- never touches the admin's own session/theme
- Grandma's standard non-volume media/function-row hotkeys are swallowed to
  prevent accidental brightness, radio, display, touchpad, microphone-mute,
  sleep, and launcher actions. Volume down, volume up, and speaker mute remain
  enabled, and ordinary F1-F12 behavior is unchanged. Firmware-handled keys
  still require a physical first-boot test on the Dell.
- A permanent bottom dock that replaces both the fullscreen Apps screen and
  XFCE's window switcher. Its large Facebook / Amazon / YouTube / Internet /
  Truist Banking / AOL Mail buttons open or raise stable Chrome windows, and its
  Volume Up and Volume Down buttons pair their speaker icons with oversized
  directional arrows and use the same clamped sound control as the keyboard,
  with Volume Down to the left of Volume Up. Amazon sits between Facebook and
  YouTube. All dock-launched
  sites share the main Chrome profile and Better Text
  View's single global, enable-everywhere configuration instead of maintaining
  separate per-profile settings.
  Before opening anything, each app button scans all Chrome windows and tabs
  for that site and activates an existing match; rapid repeat taps are ignored
  while a new window is starting, preventing duplicate-window pileups.
  The dock measures the active logical display at login, never uses more than
  one eighth of its height, has a blank touch buffer at each end, reserves that
  space so Chrome cannot cover it, and relaunches automatically if closed.
  Facebook opens automatically once per login. Amazon, YouTube, AOL Mail,
  and Banking stay closed until their button is tapped.
- Mint Update Manager hidden for Grandma's account while remaining available
  to the administrator
- Google Chrome + a root-owned enterprise policy: notifications, browser
  sign-in/sync, guest mode, extra profiles, and unapproved extension installs
  are blocked; the password manager remains ON since she doesn't reliably
  remember passwords. Better Text View is force-installed and pinned, but
  cannot read or modify pages on `truist.com`. uBlock Origin Lite is also
  force-installed and starts off the toolbar to block ads without adding
  another button or presenting donation, subscription, or upgrade prompts.
  Better Text View is enabled everywhere with a 25% font increase, a 25-pixel
  threshold, 115% contrast, maximum text opacity, gradient processing, and
  colorblind color adjustment; all dock sites share that configuration.
  Pages default to 200% zoom with a 24-pixel default font and 20-pixel minimum
  font, while pinch zoom remains available.
  Gemini and Chrome's other generative-AI surfaces, built-in AI APIs, webpage
  content sharing, and local AI-model download are explicitly disabled.
  DuckDuckGo replaces Google on startup, new tabs, Home, and address-bar search
  so Google-hosted AI promotions are not the default browsing surface.
  Chrome Memory Saver is enabled by policy (`HighEfficiencyModeEnabled`, balanced
  savings) so idle background tabs are discarded and reloaded on demand. The
  `grandma-browser-hygiene` helper covers what that policy leaves alone --
  app-mode windows and runaway/unresponsive ones -- by closing an unresponsive
  *background* window or reloading a background RAM hog only after grandma has
  been idle. A local 30-minute systemd timer runs it without an LLM; it never
  touches the active window. Healthy checks and ordinary cleanup do not contact
  OpenClaw or spend model tokens. Monitor failures and corrective actions on
  exceptionally large background windows (at least 2500 MB) trigger a targeted, event-driven
  OpenClaw wake; large-window alerts are limited to one every 12 hours.
- Automatic updates via `unattended-upgrades`, covering both the Mint/Ubuntu
  archives and Chrome's own repo, with a scheduled 4:30am reboot so patches
  actually take effect
- Self-healing systemd timers: the accessibility/lock-screen baseline
  reasserts every 15 minutes (catches mid-session drift, not just login),
  browser profile backs up hourly (SQLite-safe, 14 generations kept)
- DNS-level ad/scam/malware blocking (AdGuard Family Protection) on the
  active Wi-Fi connection. NetworkManager's local dnsmasq plugin conditionally
  resolves only `openrouter.ai` through Cloudflare Families, avoiding AdGuard's
  current DNSSEC `SERVFAIL` for that domain without bypassing filtering for
  Grandma's browsing.
- GRUB never shows its menu, including after a crash/unclean shutdown

## What it deliberately does NOT automate

- **OpenClaw itself** (remote control via Telegram). This needs a bot token from
  @BotFather and pairing your own Telegram account -- inherently
  interactive and tied to your personal credentials, not something to bake
  into a script. On the new machine: install per openclaw.ai's own
  installer, `openclaw channels add --channel telegram --token <token>`,
  pair yourself, then `openclaw gateway install` + `loginctl enable-linger
  <admin-user>` for persistence. (On the original machine, `openclaw daemon
  install` refused to run because `~/.config/systemd/user` was
  group-writable -- fix with `chmod go-w` on exactly that directory if you
  hit the same thing; don't sudo/recursive-chmod around it.)
  After the gateway is installed and healthy, run
  `grandma-install-openclaw-watchdog` as that same non-root admin user, then
  run the printed one-time `sudo loginctl enable-linger <admin-user>` command.
- **Hardware-specific fixes.** No Chromebook audio, firmware, kernel, display,
  input, or power workaround is installed. On the Dell, run
  `grandma-hardware-report` and `grandma-audio-status` after first boot and
  only add a fix for a demonstrated problem.
- **Automatic screen rotation and on-screen-keyboard presentation.** Support
  depends on the real sensors and touch workflow. The required first-boot tests
  are listed in the Dell target profile rather than guessed here.
- **The admin's own account/sudo/SSH access.** Assumed to already exist.
- **Package removal of any kind, ever, unattended.** `Remove-Unused-
  Dependencies` is deliberately never enabled in the unattended-upgrades
  config -- see the comment in `phase_updates()` in `provision.sh` for why
  (it would have silently removed OpenClaw's Node.js runtime on the
  original machine, since apt's dependency graph has no idea a live process
  depends on it at runtime).

## Files

- `provision.sh` -- the orchestrator, one function per phase.
- `bootstrap-grandmaos` -- one-command GrandmaOS plus interactive OpenClaw
  bootstrap, designed to require only one initial sudo invocation.
- `AGENTS.md` -- guarded end-to-end instructions for Codex or another coding
  agent setting up the freshly installed Dell.
- `files/sbin/` -- all `grandma-*` scripts, installed verbatim to
  `/usr/local/sbin`.
- `hardware/dell-xps-13-2026/` -- known target facts, validation procedure,
  and hardware-dependent TODOs.
- `MIGRATION-DELL-XPS-13-2026.md` -- repository assessment and migration record.
- `files/autostart/` -- root-owned XDG autostart entries (baseline
  reassertion, the launcher, and Hidden=true overrides that disable
  light-locker/xscreensaver for grandma only).
- `files/systemd/` -- the two timer/service pairs (baseline reassertion,
  browser backup).
- `files/systemd-user/` -- optional OpenClaw watchdog user-unit templates.
- `files/chrome-policy.json` -- installed to
  `/etc/opt/chrome/policies/managed/grandmaos.json`. Verify the active and
  recognized policy set at `chrome://policy` after Chrome's first launch.

## Chrome AI exclusion

The managed policy prevents Chrome from downloading its on-device generative-AI
model and disables the currently policy-controlled Gemini/AI features and their
browser UI. It cannot remove dormant code compiled into Chrome, or control AI
content on arbitrary websites Grandma deliberately visits. Google may add new
features and policy names later, so `chrome://policy` and Chrome's current
enterprise policy documentation are part of the first-boot and update audit.
Chrome's umbrella `GenAiDefaultSettings` is Admin-console-only, so this local
Linux installation explicitly sets each applicable AI policy instead.

The installer does not uninstall an existing Brave installation or delete its
profile, in keeping with GrandmaOS's no-unattended-removal rule. On the new Dell,
Chrome is the only browser GrandmaOS installs and launches.

Icons for the launcher (Facebook/Amazon/YouTube/Truist/AOL favicons) are fetched
fresh from Google's public favicon proxy at provision time rather than
bundled, to keep this directory small and avoid shipping stale logos.

## OpenClaw watchdog

The optional timers run in the OpenClaw owner's user systemd manager. The
five-minute watchdog is local/offline in scope: it checks the loopback gateway,
not Telegram or general internet availability. This prevents a router or
provider outage from triggering destructive-looking repair activity. The
30-minute Chrome-hygiene timer also runs locally. Normal checks and ordinary
cleanup use no model tokens; only a real monitor failure or corrective action
on a background window using at least 2500 MB wakes OpenClaw. Large-window alerts have a 12-hour
cooldown. The installer sets that agent's recurring
heartbeat cadence to `0m`; targeted event wakes remain available.

After two failed local probes ten seconds apart, it runs
`openclaw doctor --fix --non-interactive`, performs one graceful
`openclaw gateway restart`, and makes three bounded recovery probes. Concurrent
runs are locked out, systemd does not restart failed watchdog executions, and a
failed recovery waits for the next five-minute timer rather than spinning.
OpenClaw is never run as root.

```sh
# Run as the non-root admin/OpenClaw owner after `openclaw gateway install`:
grandma-install-openclaw-watchdog

# One-time persistence while that user is logged out:
sudo loginctl enable-linger ADMIN_USERNAME

# Inspect timer, last run, and logs:
systemctl --user status grandmaos-openclaw-watchdog.timer grandmaos-browser-hygiene.timer
cat ~/.local/state/grandmaos/openclaw-watchdog-last-result
journalctl --user -u grandmaos-openclaw-watchdog.service
journalctl --user -u grandmaos-browser-hygiene.service
```

The watcher is deliberately installed only after OpenClaw setup because the
gateway's owning admin account and executable path cannot safely be guessed by
the root provisioning pass.
