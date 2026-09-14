# Dell XPS 13 (2026) target profile

This is GrandmaOS's primary hardware target. The known retail configuration
is an x86-64 Intel Core 5 Series 3 platform with 8 GB RAM, a 512 GB NVMe SSD,
Intel integrated graphics, and a 13.4-inch 2.5K-class touchscreen.

Exact component models, device IDs, display modes, and controllers are not
known yet. GrandmaOS therefore uses normal Linux Mint/Ubuntu drivers and
hardware discovery. This directory must not acquire guessed kernel parameters,
ALSA topology overrides, Xorg snippets, or firmware workarounds.

## First-boot validation

After a normal Linux Mint XFCE x86-64 UEFI installation and all offered Mint
updates, run:

```sh
sudo grandma-hardware-report /tmp/grandmaos-dell-hardware.txt
grandma-audio-status
grandma-network-status
grandma-status
```

Send back `grandmaos-dell-hardware.txt`. The report is read-only. It records
the exact CPU, firmware, Secure Boot state, PCI/USB devices and bound drivers,
storage, graphics, display modes, input devices, audio, networking, Bluetooth,
battery, suspend modes, and relevant kernel warnings. Some desktop-session
details (notably `xrandr`, PipeWire, and `wpctl`) are most complete when the
report is also run once from a terminal in Grandma's logged-in session without
`sudo`.

## TODO after the real laptop is available

- Record the exact XPS model/product name, native display mode, physical size,
  and observed logical desktop size.
- Verify that 192 DPI with GTK window scale 1 produces readable dialogs without
  double-scaling. Adjust from observed results, not the “2.5K” sales label.
- Verify touchscreen tap, drag, Google Chrome scrolling, pinch zoom, and the
  trackpad/keyboard path. Do not add device-specific libinput/Xorg rules unless
  the report and testing show a need.
- Test Onboard or another on-screen keyboard with browser text fields before
  enabling automatic presentation. A permanently intrusive keyboard is worse
  than leaving this manual until tested.
- Determine whether an accelerometer is exposed through iio-sensor-proxy. Only
  then decide whether automatic rotation is useful; do not assume this laptop
  is convertible.
- Test speakers, microphone, headphone switching, Wi-Fi, Bluetooth, lid close,
  suspend, resume, wake, brightness controls, and battery reporting.
- Test every physical function-row key in Grandma's session. Volume down,
  volume up, and speaker mute should work; other media actions should be
  swallowed. Record any key handled directly by firmware or reported under an
  unexpected name instead of guessing a Dell-specific mapping.
- Review LightDM greeter sizing on the native panel. Autologin is the normal
  path, so greeter changes should be based on the actual fallback screen.
- Open `chrome://policy`, reload policies, and confirm the AI exclusions in
  `files/chrome-policy.json` are recognized with no policy errors. Confirm there
  is no Gemini/AI button, AI prompt, or downloaded on-device model.
- Check `fwupdmgr get-devices` and Dell firmware updates. Do not disable Secure
  Boot, alter UEFI settings, repartition the NVMe drive, or add kernel arguments
  unless a demonstrated problem requires it.

## Explicitly excluded previous-machine assumptions

The old Chromebook/ThinkPad 100e audio path (Apollo Lake, SOF, DA7219,
MAX98357A, ALSA/PipeWire overrides), Chromebook firmware/board behavior,
tiny-disk assumptions, and 4 GB low-memory tuning are not part of this target.
The currently checked-in Samsung 750GX-era assumptions—including a fixed Wi-Fi
interface name and the observation that its Intel/ALC256 audio worked normally—
also provide no Dell device guarantee. No Chromebook audio or firmware override
is currently shipped in this repository.
