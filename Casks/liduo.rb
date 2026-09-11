cask "liduo" do
  version "0.2.6"
  sha256 "ef98fc60164d3aa062d7d2a820acd98435c104cf64f657711372280236e114a6"

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
