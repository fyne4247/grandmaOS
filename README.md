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
4. Reboot. Grandma's account should autologin straight into the launcher,
   locked down, no lock screen, no admin authority.
5. Do the manual steps below.

The script is idempotent -- re-running it on an already-provisioned machine
only touches what's missing or different; it won't recreate the grandma
account, re-add the Chrome repo, etc. if they're already there.

## What it automates

- `grandma` system account (no sudo/admin group), lingering enabled so root
  can reach her session non-interactively (needed for the next item)
- LightDM autologin as `grandma`
- All `grandma-*` maintenance/diagnostic scripts to `/usr/local/sbin`
- XFCE accessibility baseline (high-DPI text, large cursor/panel/icons,
  high-contrast theme) and
  full lock-screen elimination (3 mechanisms: LockCommand, power-manager
  suspend-lock, light-locker/xscreensaver autostart disabled) for grandma
  only -- never touches the admin's own session/theme
- The big-button launcher (Facebook / YouTube / Internet / Banking
  placeholder), auto-relaunching if closed
- Google Chrome + a root-owned enterprise policy: extensions, notifications,
  browser sign-in/sync, guest mode, and extra profiles are blocked; the
  password manager remains ON since she doesn't reliably remember passwords.
  Pages default to 125% zoom while pinch zoom remains available.
  Gemini and Chrome's other generative-AI surfaces, built-in AI APIs, webpage
  content sharing, and local AI-model download are explicitly disabled.
  DuckDuckGo replaces Google on startup, new tabs, Home, and address-bar search
  so Google-hosted AI promotions are not the default browsing surface.
- Automatic updates via `unattended-upgrades`, covering both the Mint/Ubuntu
  archives and Chrome's own repo, with a scheduled 4:30am reboot so patches
  actually take effect
- Self-healing systemd timers: the accessibility/lock-screen baseline
  reasserts every 15 minutes (catches mid-session drift, not just login),
  browser profile backs up hourly (SQLite-safe, 14 generations kept)
- DNS-level ad/scam/malware blocking (AdGuard Family Protection) on the
  active Wi-Fi connection
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
- **The Banking launcher button.** Ships disabled/greyed out. Once you have
  the real bank login URL, edit the `bank_btn` line in
  `/usr/local/sbin/grandma-launcher` (see the other `SITES` entries for the
  pattern) and re-run `grandma-launcher-supervisor` or just wait for
  grandma's next login.
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

Icons for the launcher (Facebook/Messenger/YouTube favicons) are fetched
fresh from Google's public favicon proxy at provision time rather than
bundled, to keep this directory small and avoid shipping stale logos.

## OpenClaw watchdog

The optional watchdog runs every five minutes in the OpenClaw owner's user
systemd manager. It is local/offline in scope: it checks the loopback gateway,
not Telegram or general internet availability. This prevents a router or
provider outage from triggering destructive-looking repair activity.

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
systemctl --user status grandmaos-openclaw-watchdog.timer
cat ~/.local/state/grandmaos/openclaw-watchdog-last-result
journalctl --user -u grandmaos-openclaw-watchdog.service
```

The watcher is deliberately installed only after OpenClaw setup because the
gateway's owning admin account and executable path cannot safely be guessed by
the root provisioning pass.
