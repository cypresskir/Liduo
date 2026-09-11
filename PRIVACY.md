# Privacy

Liduo runs locally. It has no account system, analytics, crash uploader, update
service, or application code that sends data over the network.

## Screen access

The full-screen effect uses ScreenCaptureKit to obtain frames from the built-in
display. Frames are processed in memory by Metal and are not written to image
or video files. Liduo excludes its own windows from capture to prevent visual
feedback. Audio and microphone capture are disabled, and the cursor is excluded
from captured frames. Capture stops when the effect is disabled, when the Mac
sleeps or locks, or shortly after the lid opens past the configured range.

The settings preview uses a bundled static image and needs no screen permission.

## Settings and diagnostics

Effect preferences are saved in macOS UserDefaults. Login-item registration is
managed by macOS through SMAppService. The lid angle is read locally through HID.

An optional developer argument, `--diagnostics /absolute/path/status.json`,
writes a local status file containing the lid angle, state flags, frame counters,
and error messages. It does not contain screen frames or audio. This file is
not created on normal launch and is never uploaded by Liduo. Review error text
before sharing it in an issue.

macOS may independently perform its normal Gatekeeper, certificate, and
notarization checks when an application is downloaded or opened.
