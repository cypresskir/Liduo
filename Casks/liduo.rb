cask "liduo" do
  version "0.2.5"
  sha256 "0fdb76af88983f82e090d4aba90a64c64b4f555b7b791942e7822dd0bb5f0450"

  url "https://github.com/cypresskir/Liduo/releases/download/v#{version}/Liduo-v#{version}-macos-arm64-adhoc.zip"
  name "Liduo"
  desc "Lid-driven desktop bend, blur, and shading for MacBook"
  homepage "https://github.com/cypresskir/Liduo"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Liduo.app"

  caveats <<~EOS
    This build is ad-hoc signed and has not been notarized by Apple.
    If you trust it, allow this app only:
      xattr -dr com.apple.quarantine "#{appdir}/Liduo.app"
    Then open Liduo and grant screen-recording access in macOS settings.
  EOS
end
