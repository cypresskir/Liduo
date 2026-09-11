# Liduo

**A lid-driven desktop effect for your MacBook.**

[Русский](README.md) · [Install](docs/INSTALLING.md) · [Build from source](docs/BUILDING.md) · [Privacy](PRIVACY.md) · [Changelog](CHANGELOG.md)

Liduo bends, blurs, and darkens the desktop as you close your MacBook's lid.
It lives in the menu bar and processes screen content on your Mac.
The effect works offline; checking for and downloading updates needs an internet connection.

![Liduo settings window with the bundled sample desktop](docs/images/settings.jpg)

*Actual settings window. The preview uses a bundled sample image; the full-screen
 effect uses the contents of the built-in display. The interface is currently in Russian.*

## What it does

- Three styles: **Пластика** (soft bend), **Тень** (deeper shading), and **Иней** (frosted glass).
- Adjustable bend, blur, darkness, and the angle at which the effect disappears.
- Manual preview, lid-controlled preview, and a five-second desktop demonstration.
- **⌘⌥B** to toggle the effect or stop a demonstration.
- Optional opening sound and launch at login.
- Built-in signed updates, with optional daily checks and installation by consent.
- Screen capture and rendering stop when the effect is no longer needed.

## Status and requirements

**Experimental version 0.2.8.** [Download the DMG](https://github.com/cypresskir/Liduo/releases/download/v0.2.8/Liduo-v0.2.8-macos-arm64.dmg)
or open the [release page](https://github.com/cypresskir/Liduo/releases/tag/v0.2.8).
The archive uses Liduo's permanent signing certificate; it has no Developer ID certificate or Apple notarization.
Development-signed local builds are separate from this downloadable archive.

- macOS **26 or later** and an **Apple silicon MacBook with a compatible lid-angle sensor**.
- Tested on a **MacBook Pro with M4 Pro**. Compatibility with other models is not established.
- **MacBook Air M1 and 13-inch MacBook Pro M1/M2 lack the required angle sensor.** See [model compatibility and diagnostics (Russian)](docs/COMPATIBILITY.md).
- The full-screen effect needs macOS screen-recording permission. The sample preview does not.
- Only the built-in display is affected; external displays remain unchanged.

## Install

Version 0.2.8 installs without Terminal, Homebrew, Node.js, or Xcode:

1. Open `Liduo-v0.2.8-macos-arm64.dmg` and drag Liduo to **Программы** (Applications).
2. Launch Liduo from Applications. If macOS blocks it and you trust the source,
   go to **System Settings → Privacy & Security → Open Anyway** and confirm.
3. Choose **Разрешить доступ…** in Liduo and grant screen-recording permission.

The DMG includes a Russian guide that works offline. This free build is not
notarized by Apple, so a first-launch exception is still required.

Alternative installers: [Homebrew and npx](docs/INSTALLING.md#homebrew).
See [installation, updates, and a user-folder option](docs/INSTALLING.md).

After installation, use **Проверить обновления…** in Liduo's menu or General Settings.
Optional automatic checking is off by default. Updates are signed independently of
Apple Developer ID. See [UPDATES.md](docs/UPDATES.md) for details and publishing instructions.

Upgrading from 0.2.6 or earlier may require granting screen access once again.
If the macOS toggle is already on but the effect does not work, choose **Доступ
включен, но не работает?** in Liduo's General Settings for recovery instructions.

### First launch

1. Choose **Разрешить доступ…** and enable Liduo in macOS screen-recording settings.
2. Restart Liduo if macOS asks.
3. Choose **Показать эффект** or gently move the lid. **⌘⌥B** turns the effect off.

The bundled sample preview works without permission. Closing the window leaves
Liduo running in the menu bar; choose **Выйти из Liduo** to quit.

## Build and try it

Use **macOS 26+**, **Apple silicon**, the full **Xcode 26.4+**, and **XcodeGen**.
See the [developer instructions](docs/BUILDING.md) for Xcode setup, building, signing, and tests.

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
