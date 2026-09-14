# Migration plan: Dell XPS 13 (2026)

## Repository assessment

The checked-in bundle appears to represent the Samsung 750GX-era GrandmaOS
installation (the repository has only one initial commit). The ThinkPad 100e
Chromebook was an earlier prototype stage described outside this checkout.

The project is a single idempotent `provision.sh` orchestrator plus files copied
into `/usr/local/sbin`, per-user XFCE autostart entries, root systemd timers, and
a managed browser policy. Its hardware-independent behavior is the unprivileged
`grandma` account, LightDM autologin, fullscreen launcher, browser policy and
profile recovery, accessibility/lock-screen baseline, updates, DNS filtering,
and read-only maintenance status.

No Chromebook firmware, Apollo Lake/SOF, DA7219/MAX98357A, ALSA topology,
PipeWire override, Xorg device rule, custom kernel argument, fixed resolution,
zram, swap, or small-disk configuration exists in the checked-in bundle.

Prototype assumptions found in code were narrower but real:

- `grandma-network-status` required the old interface name `wlo1`.
- The baseline systemd service assumed Grandma's numeric UID was `1001`.
- Status text asserted there was no touchscreen.
- The launcher used fixed 420-pixel buttons, independent of logical screen size.
- The README described the Samsung-era Intel/ALC256 audio as working normally,
  without clearly naming that intermediate target or separating it from the
  earlier Chromebook prototype.
- Scaling was a fixed 192 DPI value without documenting how it interacts with
  GTK scaling or how to validate it on the real panel.

## Implemented safe migration work

- Auto-detect the Wi-Fi interface, with an environment override for diagnosis.
- Resolve Grandma's UID/runtime bus dynamically for timer-based baseline work.
- Report both touchpad and touchscreen presence without requiring an X session.
- Make launcher controls adapt to logical display dimensions.
- Establish an explicit Dell target directory and a read-only first-boot
  hardware report.
- Document the 192-DPI starting point and prevent accidental GTK double-scaling.
- Keep standard Mint drivers and leave rotation, on-screen keyboard automation,
  LightDM greeter tuning, and any device workaround pending real observations.
- Replace Brave with managed Google Chrome for its accessibility features while
  disabling Chrome's local AI-model download, Gemini, AI Mode, AI suggestions,
  generative writing/history/tab/theme tools, built-in AI APIs, and content
  sharing. Use DuckDuckGo rather than a Google new-tab/search surface.
- Add an optional per-user OpenClaw watchdog that detects repeated local gateway
  failure, runs bounded non-interactive Doctor repair, gracefully restarts, and
  verifies recovery without confusing an internet outage with a gateway fault.

## Next gate

Provisioning can be previewed with `sudo ./provision.sh --dry-run`. Before a
production install, boot the real Dell, apply normal Mint updates, collect the
hardware report, and complete the TODO checklist in the target profile. The
report is the gate for any device-specific configuration.
