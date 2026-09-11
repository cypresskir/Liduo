# Changelog

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
