# Testing and compatibility

## Automated checks

`./scripts/test.sh unit` runs 15 tests for effect parameters, lid interpolation,
sensor-jitter handling, capture safety conditions, the sound cycle, preference
validation, and cursor hide/show ownership. These use test inputs and injected
cursor callbacks; they do not validate a physical sensor or the OS cursor hook.

`./scripts/test.sh all` additionally exercises GPU blur and edge fading, opaque
rendering, preview thumbnails, rendering sleep/wake behavior, and presentation
cadence on the built-in display. The full suite currently contains 28 tests.

The GitHub Actions workflow uses the macOS 26 arm64 runner. It compiles the app
and runs only the hardware-independent tests. It does not sign or publish an
application. Metal and physical-display checks remain a separate local step.

## Release smoke test on a physical MacBook

- Start a clean installation, grant screen permission, and restart if requested.
- Confirm the permission, sensor angle, sample preview, and three styles.
- Run the five-second desktop demonstration; confirm capture and pointer state recover.
- Move the lid slowly, then reverse direction. Inspect the beginning and end of the effect.
- Check soft edges, menu-bar coverage, pointer hiding, and pointer restoration after pause.
- Check opening past the cutoff, screen lock, sleep/wake, and quitting during the effect.
- With an external display attached, verify it stays unaffected and the pointer is visible there.
- Leave the app idle, close its window, and inspect CPU and Energy Impact after settling.
- Verify screen permission persists across an update with the same signing identity.

## Preparation check — 2026-09-11

On macOS 26.5.1 with Xcode 26.4 and Swift 6.3:

- A clean export of the tracked source files built successfully with `./build.sh check`.
- The development-signing mode produced a verified local application archive.
- The exact CI test command passed locally: 15 tests, zero failures.
- The complete Release suite passed: 28 tests, zero failures.
- The warmed-up synthetic presentation test measured 120 fps with an 8.34 ms
  maximum frame interval; it does not measure live ScreenCaptureKit performance.
- The workflow YAML and shell syntax were checked. The workflow has not yet run
  on GitHub because the repository has not been published.

## Evidence and limits

The application has been tested locally on a MacBook Pro M4 Pro running macOS
26.5.1. Version 0.2.3's installed UI was inspected with both a clear sample image
and a folded, frosted preview. Earlier local rendering measurements reached
120 fps after warm-up on that device. That figure is a synthetic presentation
measurement, not a guarantee for live capture or every MacBook.

The 0.2.2 energy fix was followed by an idle Energy Impact reading of 0.8 in one
local observation. Energy Impact varies with system load and is not a wattage
or battery-life measurement. Long battery-duration testing, a second MacBook
model, and installation of a notarized public build on another Mac remain open.

See [RELEASING.md](RELEASING.md) for checks before attaching a public binary.
