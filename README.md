# Liduo

**A lid-driven desktop effect for your MacBook.**

[Русский](README.ru.md) · [Build from source](docs/BUILDING.md) · [Privacy](PRIVACY.md) · [Changelog](CHANGELOG.md)

Liduo bends, blurs, and darkens the desktop as you close your MacBook's lid.
It lives in the menu bar and runs locally, with no account or network service.

![Liduo settings window with the bundled sample desktop](docs/images/settings.jpg)

*Actual settings window. The preview uses a bundled sample image; the full-screen
 effect uses the contents of the built-in display. The interface is currently in Russian.*

## What it does

- Three styles: **Пластика** (soft bend), **Тень** (deeper shading), and **Иней** (frosted glass).
- Adjustable bend, blur, darkness, and the angle at which the effect disappears.
- Manual preview, lid-controlled preview, and a five-second desktop demonstration.
- **⌘⌥B** to toggle the effect or stop a demonstration.
- Optional opening sound and launch at login.
- Capture and rendering stop when no longer needed; identical frames reuse prepared blur.

## Status and requirements

**Experimental source release, version 0.2.3.** A notarized public application
archive is not included. Development-signed local builds are not public installers.

- macOS **26 or later** and an **Apple silicon MacBook with a compatible lid-angle sensor**.
- Tested on a **MacBook Pro with M4 Pro**. Compatibility with other models is not established.
- The full-screen effect needs macOS screen-recording permission. The sample preview does not.
- Only the built-in display is affected; external displays remain unchanged.

## Build and try it

Install **Xcode 26.4 or later** and **XcodeGen** (`brew install xcodegen`).
A compile check requires no signing certificate:

```sh
./build.sh check
./scripts/test.sh unit
```

For a usable local application with a stable signing identity, follow
[the development build instructions](docs/BUILDING.md#local-development-build).
Keep its bundle identifier and signing identity stable across updates so macOS
can recognize the screen permission.

After building:

1. Move `Liduo.app` to Applications and open it.
2. Choose **Разрешить доступ…** and enable Liduo in macOS screen-recording settings.
3. Restart Liduo if macOS asks. Use **Показать эффект** to try the desktop demonstration.
4. Choose a style and gently move the lid. Use **⌘⌥B** to turn the effect off.

## How it works

SwiftUI and AppKit provide the interface. A background IOKit HID reader supplies
lid angles. ScreenCaptureKit captures the built-in display while excluding Liduo's
own windows. Metal and Metal Performance Shaders render the fold, blur, and shading.
The shader is compiled at runtime from the bundled source; no separate Metal
Toolchain download is needed for the project build.

Screen frames stay in memory. Liduo does not record audio, save desktop images,
or send captured content anywhere. See [Privacy](PRIVACY.md).

## Current limitations

- This is an image overlay: application windows and their click coordinates do not move.
- The frosted appearance is a custom shader, not the native Liquid Glass material.
- The lid sensor format is hardware-dependent and is not a public Apple compatibility contract.
- Hiding the pointer over another application's window uses an optional, undocumented
  WindowServer connection property. If unavailable, background cursor hiding may not work.
- Capture is SDR, at most 2560 pixels wide and 60 fps. Rendering can target up to
  120 fps on ProMotion; that is not a guaranteed frame rate on every Mac.
- Protected content may be absent from capture. Sleep and display behavior remain controlled by macOS.
- Long-term battery use and the full range of MacBook models have not been validated.

See [testing and known verification limits](docs/TESTING.md) before relying on performance claims.

## Contributing and license

Bug reports and focused improvements are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md).
Source code and documentation text are under the [MIT license](LICENSE).
The bundled preview image has [separate asset terms](ASSETS.md).

Inspired by [Bendy](https://trybendy.app/). Liduo is an independent implementation
and includes no Bendy source code or assets.
