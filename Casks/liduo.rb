cask "liduo" do
  version "0.2.7"
  sha256 "547c8c6169da32797d4aaf55f07560834a5f071d7ad9805f00ea17097f7bbf26"

  url "https://github.com/cypresskir/Liduo/releases/download/v#{version}/Liduo-v#{version}-macos-arm64-selfsigned.zip"
  name "Liduo"
  desc "Lid-driven desktop bend, blur, and shading for MacBook"
  homepage "https://github.com/cypresskir/Liduo"

  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Liduo.app"

  caveats <<~EOS
    This build uses Liduo's own signing certificate and is not notarized by Apple.
    If you trust it, allow this app only:
      xattr -dr com.apple.quarantine "#{appdir}/Liduo.app"
    Then open Liduo and grant screen-recording access in macOS settings.
    Upgrading from 0.2.6 or earlier may require granting access once again.
  EOS
end
