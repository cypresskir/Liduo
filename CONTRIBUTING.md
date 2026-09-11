# Contributing

For a bug, include your Mac model, macOS version, Liduo version, effect settings,
and steps to reproduce it. Say whether it happens in the manual preview, the
five-second demonstration, or while moving the lid. Do not post private desktop
captures or signing credentials.

For code changes:

1. Read [BUILDING.md](docs/BUILDING.md) and generate the Xcode project with XcodeGen.
2. Keep changes focused. Do not commit generated projects, build results, or keys.
3. Run `./scripts/test.sh unit`. For rendering or lifecycle changes, also run
   `./scripts/test.sh all` on a physical MacBook and follow [TESTING.md](docs/TESTING.md).
4. Describe the user-visible change and what you verified in the pull request.

`project.yml` is the project configuration source of truth. Application UI copy
is currently Russian. Changes to screen access, cursor handling, and lifecycle
must preserve capture cleanup and pointer restoration.

Contributions of code and documentation are made under the project's MIT license.
Assets have separate terms in [ASSETS.md](ASSETS.md).
