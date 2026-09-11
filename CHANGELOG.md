# Changelog

## 0.2.8 — 2026-09-11

- Drive rendering with CAMetalDisplayLink and two-frame latency to avoid main-thread drawable waits.
- Smooth slow, quantized lid readings and preserve continuous blur-radius changes.
- Keep visible Liduo settings windows in desktop capture, safely filter window IDs, and narrow the bottom blur band.
- Clarify update notices when a local build is newer than the public release.
- Add bounded, opt-in measurements of actual frame presentation to local diagnostics.
- Keep the existing app certificate and Sparkle update key.

## 0.2.7 — 2026-09-11

- Switched public builds to a permanent self-signed certificate so changing the executable no longer changes its permission identity.
- Reject release packaging with an ad-hoc signature or a different certificate.
- Added a screen-access recovery guide for stale permissions from older builds, with a link to macOS settings.
- Kept the existing Sparkle update key and documented the one-time permission transition from 0.2.6 or earlier.

## 0.2.6 — 2026-09-11

- Added a drag-and-drop DMG with an Applications shortcut and an offline Russian first-launch guide.
- Added repeatable DMG packaging with payload, signature, layout, and checksum verification.
- Tried every matching lid sensor and validated its angle report before reporting a connection.
- Added IORegistry discovery, model-aware diagnostics, and a hardware compatibility guide.

## 0.2.5 — 2026-09-11

- Added built-in updates through Sparkle 2.9.6, with manual checks in the menus and General Settings.
- Added optional daily checks, disabled by default. Installation always requires consent.
- Required signed feeds and archive verification before extraction, with the private key kept in Keychain.
- Updated Homebrew, npx, and release preparation to use the same signed update archive.

## 0.2.4 — 2026-09-11

- Prepared Homebrew and GitHub-based npx installers with pinned archive checksums.
- Added an ad-hoc build mode and app-specific launch instructions without a Developer ID certificate.

- Fixed preview updates being discarded when macOS temporarily reports an ordered
  settings window as occluded. Hidden windows still stop rendering, and unchanged
  frames still put the renderer to sleep.
- Explained why the manual preview has no effect when its angle is at or above the cutoff.
- Added a regression test through the complete SwiftUI settings window, including
  changes after idle and hide/show cycles. Test preferences use a separate store.

## 0.2.3 — 2026-09-11

- Replaced the drawn sample desktop with a bundled desktop image in the preview
  and all three style thumbnails. The image is decoded once and cached.
- Prepared public source documentation, a portable build workflow, and CI.

## 0.2.2 — 2026-09-11

- Fixed capture shutdown after a demonstration.
- Paused rendering when the frame is unchanged and resumed it on new input.
- Reused prepared blur results while both the source frame and blur radius remain unchanged.

## 0.2.1

- Hid the pointer before showing the full-screen effect and restored it afterward.
- Kept the pointer visible outside the affected built-in display.

## 0.2.0

- Rebuilt the settings window around a larger preview, style thumbnails, and controls.
- Moved general settings into a separate window and revised Russian interface text.

## 0.1.x

- Added lid-driven folding, shading, and frosted-glass styles.
- Improved sensor interpolation, edge fading, menu-bar coverage, permissions,
  application signing, and the menu-bar icon.
