#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { readFile, writeFile, mkdir, mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateRelease } from '../installer/cli.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
if (process.argv.length !== 3) {
  console.error('Usage: node scripts/prepare-installers.mjs dist/Liduo-vVERSION-macos-arm64-adhoc.zip');
  process.exit(2);
}
const archive = path.resolve(process.argv[2]);
const pkg = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
const project = await readFile(path.join(root, 'project.yml'), 'utf8');
const version = project.match(/MARKETING_VERSION: "([\d.]+)"/)?.[1];
if (version !== pkg.version) throw new Error('Keep package.json and project.yml versions in sync.');
const release = {
  version, repository: 'cypresskir/Liduo', asset: path.basename(archive),
  sha256: createHash('sha256').update(await readFile(archive)).digest('hex'),
};
const url = validateRelease(release);
const stage = await mkdtemp(path.join(tmpdir(), 'LiduoInstallers-'));
try {
  execFileSync('/usr/bin/ditto', ['-x', '-k', archive, stage]);
  const app = path.join(stage, 'Liduo.app');
  const plist = path.join(app, 'Contents/Info.plist');
  const value = key => execFileSync('/usr/libexec/PlistBuddy', ['-c', `Print :${key}`, plist], { encoding: 'utf8' }).trim();
  if (value('CFBundleIdentifier') !== 'local.laplapaw.Liduo' || value('CFBundleShortVersionString') !== version) throw new Error('Unexpected app identity/version.');
  execFileSync('/usr/bin/codesign', ['--verify', '--strict', app]);
  const details = spawnSync('/usr/bin/codesign', ['-d', '--verbose=2', app], { encoding: 'utf8' });
  if (details.status !== 0 || !details.stderr.includes('Signature=adhoc')) throw new Error('Expected an ad-hoc build. Do not distribute an Apple Development build here.');
} finally { await rm(stage, { recursive: true, force: true }); }

await mkdir(path.join(root, 'Casks'), { recursive: true });
await writeFile(path.join(root, 'installer/release.json'), JSON.stringify(release, null, 2) + '\n');
await writeFile(path.join(root, 'Casks/liduo.rb'), `cask "liduo" do
  version "${version}"
  sha256 "${release.sha256}"

  url "${url.replace(version, '#{version}').replace(version, '#{version}')}"
  name "Liduo"
  desc "Lid-driven desktop bend, blur, and shading for MacBook"
  homepage "https://github.com/${release.repository}"

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
`);
await writeFile(archive + '.sha256', `${release.sha256}  ${release.asset}\n`);
console.log(`Prepared Homebrew cask and npx manifest for ${release.asset}.`);
console.log('Upload this exact archive and checksum to the matching GitHub release before advertising installation.');
