# GrandmaOS installation instructions for coding agents

This repository configures a normal Linux Mint 22.3 XFCE installation as the
GrandmaOS appliance. It is not an operating-system image or distribution.

The primary target is the 2026 Dell XPS 13 touchscreen laptop described in
`hardware/dell-xps-13-2026/README.md`. Do not copy Chromebook, Samsung 750GX,
Apollo Lake, SOF, ALSA, PipeWire, firmware, kernel-parameter, or device-specific
workarounds onto the Dell unless diagnostics from the real Dell demonstrate a
need.

## Goal

Starting from a working, fully updated Mint XFCE desktop, install and verify
GrandmaOS, then guide the owner through the credential-dependent OpenClaw
setup. Work incrementally and report which checks are confirmed, failed, or
still unverified.

## Safety boundaries

- Do not partition disks, erase another operating system, alter UEFI settings,
  disable Secure Boot, or change TPM/Pluton settings from this repository.
- Do not invent hardware identifiers or apply speculative driver fixes.
- Do not place bot tokens, API keys, passwords, recovery keys, or pairing data
  in this repository, shell history, logs, or command output.
- Never run OpenClaw as root. Install, configure, and run it as the human
  administrator account.
- Do not expose the OpenClaw gateway to the LAN or internet by default. Keep it
  loopback-only unless the owner explicitly requests and authorizes otherwise.
- Do not remove packages, browsers, profiles, or user data merely because they
  are not used by GrandmaOS.
- Preserve unrelated working-tree changes. Show the user any unexpected local
  changes before proceeding.

## Installation sequence

1. Confirm this is Linux Mint XFCE on x86-64 and record the kernel:

   ```sh
   . /etc/os-release
   printf 'OS: %s\n' "$PRETTY_NAME"
   uname -m
   uname -r
   ```

   Stop if this is not the intended installed system. For this very new Dell,
   confirm the built-in keyboard, trackpad, and touchscreen work before
   provisioning. If they do not, collect diagnostics; do not guess kernel
   parameters.

2. Update the installed operating system using Mint's supported update path,
   reboot if the kernel or firmware changed, and retest the built-in input,
   Wi-Fi, audio, suspend/resume, display, and touch behavior.

3. From the repository root, inspect local changes and run the safe preview:

   ```sh
   git status --short --branch
   sudo ./provision.sh --dry-run
   ```

   Review warnings and resolve actual failures before running the real pass.

4. Run the provisioner:

   ```sh
   sudo ./provision.sh
   ```

   A specific NetworkManager connection can be selected with
   `--wifi-connection="CONNECTION NAME"`. Do not guess it; obtain it with
   `nmcli connection show --active`.

5. Reboot and verify both accounts: the administrator remains usable with
   sudo, while `grandma` autologs in without administrative privileges and the
   large-button launcher starts. Verify Chrome policies at `chrome://policy`,
   including the disabled AI surfaces, and test keyboard, trackpad, touch,
   scaling, audio, Wi-Fi, suspend/resume, lid behavior, and browser pinch zoom.

6. As the administrator, create a read-only hardware report:

   ```sh
   grandma-hardware-report
   grandma-audio-status
   ```

   Keep the report available for follow-up Dell-specific work. Do not add a
   hardware workaround merely because a device name looks unfamiliar.

## OpenClaw handoff

OpenClaw itself is deliberately not installed by `provision.sh`: its current
installer must be checked at installation time, and Telegram/provider setup
requires the owner's credentials and interactive pairing.

As the non-root administrator:

1. Consult the current official OpenClaw installation documentation and install
   it using the supported Linux method. Do not pipe an unverified third-party
   script into a shell and do not use `sudo openclaw`.
2. Run OpenClaw's onboarding/configuration interactively. Ask the owner to enter
   secrets directly when prompted; never ask them to paste secrets into a chat.
3. Configure the desired remote channel and approve only the owner's expected
   pairing request.
4. Keep the gateway bound to loopback unless the owner explicitly chooses a
   different exposure model.
5. Install/start the gateway using the current OpenClaw command, then verify
   both local gateway health and the selected channel. A running process alone
   is not proof that remote messaging works.
6. Once the local gateway is healthy, enable GrandmaOS's recovery timer:

   ```sh
   grandma-install-openclaw-watchdog
   sudo loginctl enable-linger "$(id -un)"
   systemctl --user status grandmaos-openclaw-watchdog.timer --no-pager
   ```

7. Confirm the watchdog result and logs without exposing secrets:

   ```sh
   cat ~/.local/state/grandmaos/openclaw-watchdog-last-result
   journalctl --user -u grandmaos-openclaw-watchdog.service --no-pager -n 50
   ```

The watchdog checks only the local gateway. Separately test the configured
remote channel end to end before declaring remote administration complete.

## Completion report

Report the installed Mint version and kernel; whether built-in input, touch,
display scaling, audio, Wi-Fi, Bluetooth, suspend/resume, and lid behavior were
tested; whether GrandmaOS provisioning and Chrome policy verification passed;
whether OpenClaw gateway and remote-channel checks passed; and every remaining
TODO that needs the physical Dell or owner interaction.
