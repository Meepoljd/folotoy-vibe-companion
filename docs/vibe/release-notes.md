**English** · [简体中文](release-notes.zh_CN.md)

# Vibe Companion v0.8.4

## New in this release

Connect over Bluetooth or Wi-Fi, with dictation, Enter, Agent alerts and radio
available over Bluetooth. When office networks cannot admit the device, connect
directly to your Mac. The computer fetches and decodes Internet radio.

Pairing codes are replaced with computer-initiated discovery and device-button
approval. Keep both links attached and fall back when a route fails. New devices
can start over Bluetooth; Wi-Fi setup adds a ten-second manual-browser fallback.
This release also improves re-pairing, radio buffering/resume and dark-screen
confirmation-button behavior.

A community firmware and macOS companion for FoloToy AI Passport. The version is
identified by the release tag and package filenames.

## Included

- Wireless hold-to-talk input through the device microphone, with a separate
  Enter action. Voice remains available while using Pomodoro or radio.
- Agent notifications for Codex, Claude Code, OpenCode, DeepSeek Harness, ZCode,
  Gemini CLI and Qwen Code, with per-integration event coverage. The first alert
  is immediate; additional callbacks for the same Agent/session within one second
  are suppressed. No conversation content is forwarded.
- A compact notification overlay with screen wake and sound, five-second expiry,
  and dismissal that preserves the original button action.
- A manually started focus/rest cycle, four weather pages, light/dark/scheduled
  themes, and up to 20 selected radio stations with desktop search and ordering.
- Discover nearby devices over BLE or on the same Wi-Fi, with both links merged
  into one device row. Start connecting on the computer and confirm on the
  device. Both links may attach; application traffic selects one working route.
  Switching computers requires device approval and revokes the old controller.
- Radio is decoded on the computer and streamed over UDP or BLE to a bounded
  device cache. The current 16 kHz mono format fits 1.6 seconds of compressed
  audio with a 1.2-second startup prefill; it reduces high-frequency detail.
  The new app also serves the earlier 24 kHz format. Update both packages together.
- Phone setup for up to five remembered Wi-Fi networks, automatic reconnect,
  and device/desktop settings sync. Bluetooth can be selected at first startup.
- When the screen is off, the first press wakes it without activating menu or
  approval actions. Home-screen voice and Enter remain directly available.
- A menu-bar macOS app with one universal Apple Silicon/Intel DMG or ZIP, and
  a verified merged firmware image for the ESP32-C3's 8 MB Flash.

## Install

Use the firmware and app from the same release. See the attached `INSTALL.txt`
or `INSTALL.zh_CN.txt` for Mac installation, BlackHole 2ch, input-method setup,
permissions and pairing. The source tree's `docs/vibe/README.md` covers device
flashing and controls. The merged `FoloToy-AI-Passport-full.bin` is written at
`0x0`; a full install can reset device settings. Check `SHA256SUMS.txt`.

Packages use free ad-hoc signing and are not Apple notarized. A first launch or
update can require per-app approval and refreshed keyboard permission. No paid
Apple account is required and the app does not use Keychain.

## Validation limits

Build and host tests are separate from physical-device acceptance.
The local Intel candidate passed automatic checks and user-assisted voice/Enter,
radio/resume, BLE re-pairing, phone Wi-Fi setup and installed-hook checks. Power
and battery standby were deferred by the user. Clean installation, Apple
Silicon/macOS 13 execution and physical multiple-computer/device tests remain
unverified. The release workflow reports its own build and host-test results.
The current client is macOS-only. A desktop controls one selected device and a
device authorizes one computer at a time; handover replaces that authorization.
Agent coverage depends on version and local entry point; radio availability depends on the stream,
network, format, and available device resources. Third-party notices accompany
both packages. Final release-specific results must be reviewed before publishing.
