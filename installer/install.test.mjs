import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdirSync, writeFileSync } from 'node:fs';
import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { install, parseArgs, validateRelease } from './cli.mjs';

const payload = Buffer.from('test archive');
const release = { version: '0.2.4', repository: 'cypresskir/Liduo', asset: 'Liduo-v0.2.4-macos-arm64-adhoc.zip', sha256: createHash('sha256').update(payload).digest('hex') };

async function fixture(t) {
  const appDir = await mkdtemp(path.join(tmpdir(), 'LiduoInstallerTest-'));
  t.after(() => rm(appDir, { recursive: true, force: true }));
  const calls = [];
  const deps = {
    release, platform: 'darwin', isRunning: () => false,
    download: async (_url, file) => writeFile(file, payload),
    run(file, args) {
      calls.push([file, args]);
      if (file.endsWith('sysctl')) return '1';
      if (file.endsWith('sw_vers')) return '26.0';
      if (file.endsWith('PlistBuddy')) return args[1].endsWith('CFBundleIdentifier') ? 'local.laplapaw.Liduo' : release.version;
      if (file.endsWith('ditto')) {
        const app = path.join(args.at(-1), 'Liduo.app');
        mkdirSync(app);
        writeFileSync(path.join(app, 'contents'), 'new app');
      }
      return '';
    },
  };
  return { appDir, calls, deps, options: parseArgs(['--app-dir', appDir]) };
}

test('arguments require explicit permission to clear quarantine and replace', () => {
  const options = parseArgs([]);
  assert.equal(options.allowUnnotarized, false);
  assert.equal(options.replace, false);
  assert.throws(() => parseArgs(['--app-dir']), /параметр/);
  assert.throws(() => parseArgs(['--force']), /параметр/);
  assert.equal(parseArgs(['--allow-unnotarized']).allowUnnotarized, true);
});

test('release metadata rejects arbitrary URLs, traversal and missing hashes', () => {
  assert.equal(validateRelease(release), 'https://github.com/cypresskir/Liduo/releases/download/v0.2.4/Liduo-v0.2.4-macos-arm64-adhoc.zip');
  for (const change of [{ repository: 'https://other.test/app' }, { asset: '../app.zip' }, { sha256: '' }]) {
    assert.throws(() => validateRelease({ ...release, ...change }));
  }
});

test('Homebrew and npx reference the same version, URL and checksum', async () => {
  const manifest = JSON.parse(await readFile(new URL('./release.json', import.meta.url), 'utf8'));
  const pkg = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
  const cask = await readFile(new URL('../Casks/liduo.rb', import.meta.url), 'utf8');
  assert.equal(pkg.version, manifest.version);
  assert.ok(cask.includes(`version "${manifest.version}"`));
  assert.ok(cask.includes(`sha256 "${manifest.sha256}"`));
  const url = cask.match(/url "([^"]+)"/)[1].replaceAll('#{version}', manifest.version);
  assert.equal(url, validateRelease(manifest));
});

test('self-signed releases use an exact versioned asset name', () => {
  const signed = { ...release, asset: 'Liduo-v0.2.4-macos-arm64-selfsigned.zip' };
  assert.equal(validateRelease(signed), 'https://github.com/cypresskir/Liduo/releases/download/v0.2.4/Liduo-v0.2.4-macos-arm64-selfsigned.zip');
  for (const asset of ['Liduo-v0.2.5-macos-arm64-selfsigned.zip', 'Liduo-v0.2.4-local-arm64.zip', '../Liduo-v0.2.4-macos-arm64-selfsigned.zip']) {
    assert.throws(() => validateRelease({ ...signed, asset }));
  }
});

test('unsupported platform is rejected before network or file operations', async t => {
  const f = await fixture(t);
  await assert.rejects(install(f.options, { ...f.deps, platform: 'linux' }), /macOS/);
  assert.deepEqual(f.calls, []);
  assert.deepEqual(await readdir(f.appDir), []);
});

test('Intel and old macOS are rejected', async t => {
  for (const [arm, os] of [['0', '26.0'], ['1', '15.0']]) {
    const f = await fixture(t);
    await assert.rejects(install(f.options, { ...f.deps, run: file => file.endsWith('sysctl') ? arm : os }));
    assert.deepEqual(await readdir(f.appDir), []);
  }
});

test('hash mismatch never extracts or replaces the existing app', async t => {
  const f = await fixture(t);
  await mkdir(path.join(f.appDir, 'Liduo.app'));
  await writeFile(path.join(f.appDir, 'Liduo.app/old'), 'preserved');
  await assert.rejects(install({ ...f.options, replace: true }, { ...f.deps, download: (_url, file) => writeFile(file, 'wrong bytes') }), /SHA-256/);
  assert.equal(await readFile(path.join(f.appDir, 'Liduo.app/old'), 'utf8'), 'preserved');
  assert.equal(f.calls.some(([file]) => file.endsWith('ditto')), false);
  assert.deepEqual(await readdir(f.appDir), ['Liduo.app']);
});

test('default install preserves Gatekeeper quarantine', async t => {
  const f = await fixture(t);
  const result = await install(f.options, f.deps);
  assert.equal(await readFile(path.join(result.destination, 'contents'), 'utf8'), 'new app');
  const attrs = f.calls.filter(([file]) => file.endsWith('xattr'));
  assert.equal(attrs.length, 1);
  assert.equal(attrs[0][1][0], '-w');
  assert.equal(attrs[0][1][1], 'com.apple.quarantine');
});

test('opt-in clears only quarantine on the staged Liduo bundle', async t => {
  const f = await fixture(t);
  await install({ ...f.options, allowUnnotarized: true }, f.deps);
  const args = f.calls.filter(([file]) => file.endsWith('xattr')).at(-1)[1];
  assert.deepEqual(args.slice(0, 2), ['-dr', 'com.apple.quarantine']);
  assert.ok(args[2].startsWith(f.appDir + '/.liduo-install-'));
  assert.ok(args[2].endsWith('/Liduo.app'));
  assert.equal(f.calls.some(([file]) => file.includes('spctl') || file.includes('sudo')), false);
});

test('existing app needs --replace and an inactive process', async t => {
  const f = await fixture(t);
  await mkdir(path.join(f.appDir, 'Liduo.app'));
  await assert.rejects(install(f.options, f.deps), /--replace/);
  await assert.rejects(install({ ...f.options, replace: true }, { ...f.deps, isRunning: () => true }), /Закройте/);
  assert.equal(f.calls.some(([file]) => file.endsWith('ditto')), false);
});

test('a symlink is never replaced', async t => {
  const f = await fixture(t);
  await mkdir(path.join(f.appDir, 'elsewhere'));
  await symlink(path.join(f.appDir, 'elsewhere'), path.join(f.appDir, 'Liduo.app'));
  await assert.rejects(install({ ...f.options, replace: true }, f.deps), /ссылкой/);
});

test('replacement keeps the previous app as a recoverable backup', async t => {
  const f = await fixture(t);
  await mkdir(path.join(f.appDir, 'Liduo.app'));
  await writeFile(path.join(f.appDir, 'Liduo.app/old'), 'old app');
  const result = await install({ ...f.options, replace: true }, f.deps);
  assert.equal(await readFile(path.join(result.backup, 'old'), 'utf8'), 'old app');
  assert.equal(await readFile(path.join(result.destination, 'contents'), 'utf8'), 'new app');
});

test('signature failure leaves the previous app intact', async t => {
  const f = await fixture(t);
  await mkdir(path.join(f.appDir, 'Liduo.app'));
  await writeFile(path.join(f.appDir, 'Liduo.app/old'), 'old app');
  await assert.rejects(install({ ...f.options, replace: true }, { ...f.deps, run(file, args) {
    if (file.endsWith('codesign')) throw new Error('invalid signature');
    return f.deps.run(file, args);
  } }), /invalid signature/);
  assert.equal(await readFile(path.join(f.appDir, 'Liduo.app/old'), 'utf8'), 'old app');
  assert.deepEqual(await readdir(f.appDir), ['Liduo.app']);
});
