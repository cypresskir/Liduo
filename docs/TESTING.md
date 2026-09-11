# Testing and compatibility

## Automated checks

`./scripts/test.sh unit` runs 25 tests for effect parameters, lid interpolation,
sensor-jitter handling, capture safety conditions, the sound cycle, preference
validation, cursor hide/show ownership, and update trust/default settings. These use test inputs and injected
cursor callbacks; they do not validate a physical sensor or the OS cursor hook.
Sensor tests cover trying every candidate, failed opens, invalid reports,
closing rejected devices, and keeping unrelated SPU interfaces out of angle readings.

`./scripts/test.sh all` additionally exercises GPU blur and edge fading, opaque
rendering, preview thumbnails, rendering sleep/wake behavior, and presentation
cadence on the built-in display. The full suite currently contains 39 tests.

The GitHub Actions workflow uses the macOS 26 arm64 runner. It compiles the app
and runs only the hardware-independent tests. It does not sign or publish an
application. Metal and physical-display checks remain a separate local step.

## Release smoke test on a physical MacBook

For the self-signed download, follow [INSTALLING.md](INSTALLING.md) for its explicit
app-only launch exception. No global Gatekeeper change is required.

- Start a clean installation, grant screen permission, and restart if requested.
- Confirm the permission, sensor angle, sample preview, and three styles.
- Run the five-second desktop demonstration; confirm capture and pointer state recover.
- Move the lid slowly, then reverse direction. Inspect the beginning and end of the effect.
- Check soft edges, menu-bar coverage, pointer hiding, and pointer restoration after pause.
- Check opening past the cutoff, screen lock, sleep/wake, and quitting during the effect.
- With an external display attached, verify it stays unaffected and the pointer is visible there.
- Leave the app idle, close its window, and inspect CPU and Energy Impact after settling.
- Verify screen permission persists across an update with the same signing identity.

## Stable permission identity — 0.2.7

On macOS 26.5.1 / MacBook Pro M4 Pro, an isolated app was granted ScreenCapture
permission and then replaced with a different executable signed by the same
self-signed certificate. The native UI and `CGPreflightScreenCaptureAccess()`
reported access granted after relaunch, without another grant. TCC's system log
attributed that permission to the test bundle, not the automation tool.

A full copy of Liduo with its own test bundle ID then updated through Sparkle
from test version 0.2.7 to 0.2.8 using a signed localhost feed. It relaunched with
screen access still granted and its selected style and paused state retained.
These test version numbers are not additional public releases. Re-signing that
test app ad-hoc reproduced the denied-access state, confirming that the retained
permission depended on the certificate. The recovery guide and its link to the
macOS screen-recording pane were verified in the final app's native UI.

The Release app, ZIP, and DMG passed signature and payload checks. The release
guard accepted the committed certificate and rejected a different valid
certificate with the same bundle ID, an ad-hoc signature, and a modified resource.
All 25 hardware-independent Swift tests and 17 installer/update-signature tests
passed. The final archive verified against the signed feed with the unchanged
Sparkle public key. No rendering or sensor code changed in this release.

The old public ad-hoc identity cannot silently transfer permission to the new
certificate: the first transition may require one new grant. Other Mac models
and macOS versions remain unverified. See [SIGNING.md](SIGNING.md).

## DMG installer — 0.2.6

The Release archive built successfully. All 25 hardware-independent Swift tests
and 16 installer/update-signature tests passed. The prepared feed and ZIP verified
with the app's existing update public key; no release or feed was published.
Before publication, the complete suite also passed on the physical MacBook:
39 tests, zero failures, including Metal and built-in-display checks.
The experimental 0.2.6 release was then published to GitHub. Both archives and
their checksum files downloaded without authentication; SHA-256 matched, and the
downloaded ZIP verified against the prepared feed's Ed25519 signature.

The final compressed DMG passed `hdiutil verify`. Its app passed deep strict
code-signature verification and a checksum-based comparison of files and symbolic
links against the original ZIP. A separate copy from the mounted image into a
temporary folder also retained a valid signature and reported version 0.2.6, build 17.
The Applications shortcut, offline guide, Finder window settings, icon positions,
and embedded background were checked directly in the mounted image.

The background image was visually inspected; duplicate Retina scaling was fixed.
Native Finder inspection could not be completed reliably: the disk image disappeared
after attempts to open it through Finder, and the UI tool later returned an invalid
ScreenCaptureKit parameter error. The delivered image was rebuilt and verified
without opening the system disk-image handler. The complete drag-and-first-launch
flow on a second Mac remains unverified.

The browser environment blocked the local HTML preview. The guide's text and actual
CSS color pairs were checked, including both themes; all text pairs exceed 4.5:1.
The detector's inherited-color/media-query false positives are suppressed only for
the guide file. A browser-rendered visual check remains unverified.

## In-app updates — 0.2.5

The final prepublication run exercised all 32 Swift tests: 31 passed, while the
presentation-rate assertion measured 79.8 fps against its 108 fps threshold.
Its longest frame gap was 16.7 ms. An isolated rerun of that unchanged test passed
at 119.5 fps, with an 8.3 ms p95 gap and a 33.3 ms maximum gap. This variation is
recorded rather than treated as a guaranteed 120 fps result. All 16 Node tests
also passed against the final release archive and feed.

The development and ad-hoc archives built and passed deep code-signature checks.
All 18 hardware-independent Swift tests and all 16 Node tests passed. The latter
include corrupted archives, tampered/unsigned feeds, wrong keys, and verification
of the actual release feed with the public key embedded in Liduo. The final ZIP
also passed SHA-256, length, and Ed25519 verification against that feed.

An isolated app with its own bundle identifier, preferences, and test key updated
from 0.2.5 to 0.2.6 through Sparkle using a localhost feed. It relaunched with its
selected style and paused state intact; a second check reported it was current.
A subsequent 0.2.7 archive was modified after signing. Sparkle downloaded it but
rejected its signature before extraction, as confirmed by its system log. The
installed test copy remained at 0.2.6. Test versions are not public releases.

The final development-signed 0.2.5 was installed in `/Applications`. Its settings,
screen permission, sound, and launch-at-login preference were retained. Automatic
update checks remained off. The settings and update dialogs display in Russian.
The release archive and signed feed were published to GitHub and downloaded
without authentication; their SHA-256 and Ed25519 signatures verified. Homebrew
6.0.22 and npx with npm 12 installed the published archive into separate temporary
folders. npm 12 requires the documented per-command `--allow-git=all` option.
A public ad-hoc update on another Mac remains unverified.
The installed development build accepted the public feed's Ed25519 signature.
GitHub Actions also passed the app build, 18 hardware-independent Swift tests,
and 16 installer/signature tests on its macOS runner.

## Preview regression — 0.2.4

A new test drives the complete SwiftUI settings view through angle and blur
changes, idle, and a hide/show cycle. The original code intermittently discarded
updates when an ordered window reported an occluded state. The fixed scenario
passed five consecutive runs. A separate preferences store keeps the test from
modifying user settings.

Window occlusion notifications can arrive after an edit. An ordered preview can
now wake on an edit or visibility notification; an actually hidden window stops
before submitting a frame. The existing idle timeout and blur cache are retained.
Full-screen capture keeps its existing visibility gate.

The final complete suite passed: 29 tests, zero failures. In the installed 0.2.4
application, changing the sample angle from 59° to 49° updated the bend and glass
effect; changing blur after idle also updated the image. The original appearance
settings were restored. The update retained the existing signing identity and
screen permission.

## Installer checks — 0.2.4

`npm test` runs 12 installer tests, including checksum mismatch, unsupported hosts,
signature failure, explicit replacement, running-app protection, quarantine handling,
backup preservation, and matching Homebrew/npx metadata. All passed locally.

The ad-hoc archive built successfully and its signature verified. The real archive
was installed and updated in a temporary folder using the installer with a local
download substitute. Quarantine was retained by default and removed only with the
explicit flag; the previous app was preserved and the installed signature stayed valid.
The existing application in `/Applications` was not replaced by these checks.

The packed CLI ran through npx offline, and Homebrew loaded the generated cask and
resolved its version, URL, checksum, and caveats. Downloading from the public GitHub
release, a complete `brew install`, and first launch on another Mac remain unverified
until publication. No npm package or GitHub release was published by these checks.

## Preparation check — 0.2.3, 2026-09-11

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

The current compatibility changes passed all 25 hardware-independent tests.
A separate live probe using the production sensor code on `Mac16,8`, macOS
26.5.1, found one angle candidate, read 131 degrees, and read it again after a
stop/start cycle. No callbacks arrived after either stop. The diagnostic script
also found the standard angle interface and three unrelated vendor-specific
SPU interfaces on that Mac. An isolated verification app also displayed
`Mac16,8`, 129 degrees and a connected sensor in its diagnostics UI; screen
capture was not enabled for that copy. This verifies local discovery and reading, not
other models, physical sleep/wake, or lid-motion latency. See
[model compatibility](COMPATIBILITY.md) for the hardware limits and report command.

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
