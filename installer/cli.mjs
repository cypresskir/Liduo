#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { execFileSync, spawnSync } from 'node:child_process';
import { realpathSync } from 'node:fs';
import { lstat, mkdir, mkdtemp, readFile, rename, rm } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const help = `Установка Liduo для macOS 26+ на Apple silicon.

npx github:cypresskir/Liduo [параметры]

  --allow-unnotarized  Снять карантин только с устанавливаемой Liduo.app.
                      Сборка не проверена Apple. Используйте, если доверяете ей.
  --app-dir ПАПКА     Папка установки (по умолчанию /Applications).
  --replace           Обновить Liduo, сохранив предыдущую копию рядом.
  --help              Показать справку.

Приложение запускается вручную. Разрешение на запись экрана выдается в macOS.`;

export function parseArgs(args) {
  const options = { appDir: '/Applications', replace: false, allowUnnotarized: false };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === '--help') options.help = true;
    else if (args[i] === '--replace') options.replace = true;
    else if (args[i] === '--allow-unnotarized') options.allowUnnotarized = true;
    else if (args[i] === '--app-dir' && args[i + 1] && !args[i + 1].startsWith('--')) options.appDir = path.resolve(args[++i]);
    else throw new Error(`Неизвестный или неполный параметр: ${args[i]}. Используйте --help.`);
  }
  return options;
}

export function validateRelease(release) {
  if (!/^\d+\.\d+\.\d+$/.test(release.version) ||
      !/^[a-zA-Z0-9-]+\/[a-zA-Z0-9_.-]+$/.test(release.repository) ||
      release.asset !== `Liduo-v${release.version}-macos-arm64-adhoc.zip` ||
      !/^[a-f0-9]{64}$/.test(release.sha256)) throw new Error('Некорректные данные выпуска Liduo.');
  return `https://github.com/${release.repository}/releases/download/v${release.version}/${release.asset}`;
}

export function verifyChecksum(data, expected) {
  if (createHash('sha256').update(data).digest('hex') !== expected) {
    throw new Error('SHA-256 не совпадает. Установка отменена; существующая Liduo не изменена.');
  }
}

function command(file, args) {
  return execFileSync(file, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
}

function downloadArchive(url, destination) {
  try {
    execFileSync('/usr/bin/curl', ['--fail', '--location', '--proto', '=https', '--proto-redir', '=https',
      '--retry', '2', '--connect-timeout', '15', '--max-time', '300', '--output', destination, url], { stdio: 'inherit' });
  } catch {
    throw new Error('Не удалось скачать выпуск. Проверьте интернет и наличие архива в GitHub Releases.');
  }
}

async function statIfExists(file) {
  try { return await lstat(file); } catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

function isRunning(app) {
  const executable = path.join(app, 'Contents/MacOS/Liduo').replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const result = spawnSync('/usr/bin/pgrep', ['-f', `^${executable}( |$)`]);
  if (result.error || ![0, 1].includes(result.status)) throw new Error('Не удалось проверить, запущена ли Liduo.');
  return result.status === 0;
}

export async function install(options, dependencies = {}) {
  const run = dependencies.run ?? command;
  const platform = dependencies.platform ?? process.platform;
  if (platform !== 'darwin') throw new Error('Liduo работает только на macOS.');
  if (run('/usr/sbin/sysctl', ['-n', 'hw.optional.arm64']) !== '1') throw new Error('Нужен MacBook на Apple silicon.');
  if (Number(run('/usr/bin/sw_vers', ['-productVersion']).split('.')[0]) < 26) throw new Error('Нужна macOS 26 или новее.');
  const release = dependencies.release ?? JSON.parse(await readFile(new URL('./release.json', import.meta.url), 'utf8'));
  const url = validateRelease(release);
  const destination = path.join(path.resolve(options.appDir), 'Liduo.app');
  const existing = await statIfExists(destination);
  if (existing) {
    if (existing.isSymbolicLink() || !existing.isDirectory()) throw new Error('Путь Liduo.app занят ссылкой или файлом. Установите приложение через исходный менеджер пакетов.');
    if (!options.replace) throw new Error('Liduo уже установлена. Для обновления закройте ее и добавьте --replace.');
    if (run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', `${destination}/Contents/Info.plist`]) !== 'local.laplapaw.Liduo') {
      throw new Error('В этой папке находится другое приложение. Замена отменена.');
    }
    if ((dependencies.isRunning ?? isRunning)(destination)) throw new Error('Закройте Liduo через ее меню и повторите установку.');
  }
  await mkdir(options.appDir, { recursive: true });
  const stage = await mkdtemp(path.join(path.resolve(options.appDir), '.liduo-install-'));
  let backup;
  try {
    const archive = path.join(stage, release.asset);
    await (dependencies.download ?? downloadArchive)(url, archive);
    verifyChecksum(await readFile(archive), release.sha256);
    run('/usr/bin/ditto', ['-x', '-k', archive, stage]);
    const app = path.join(stage, 'Liduo.app');
    const plist = path.join(app, 'Contents/Info.plist');
    if (run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleIdentifier', plist]) !== 'local.laplapaw.Liduo' ||
        run('/usr/libexec/PlistBuddy', ['-c', 'Print :CFBundleShortVersionString', plist]) !== release.version) {
      throw new Error('Приложение в архиве не соответствует выпуску.');
    }
    run('/usr/bin/codesign', ['--verify', '--strict', app]);
    run('/usr/bin/xattr', ['-w', 'com.apple.quarantine', `0081;${Math.floor(Date.now() / 1000).toString(16)};LiduoInstaller;`, app]);
    if (options.allowUnnotarized) run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', app]);
    if (existing) {
      backup = path.join(path.resolve(options.appDir), `Liduo.previous-${Date.now()}.app`);
      await rename(destination, backup);
    } else if (await statIfExists(destination)) {
      throw new Error('Во время установки в папке появилась Liduo.app. Повторите установку.');
    }
    try { await rename(app, destination); }
    catch (error) { if (backup) await rename(backup, destination); throw error; }
    return { destination, backup, version: release.version };
  } finally {
    await rm(stage, { recursive: true, force: true });
  }
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    const options = parseArgs(process.argv.slice(2));
    if (options.help) console.log(help);
    else {
      if (options.allowUnnotarized) console.log('Карантин будет снят только с Liduo.app. У сборки нет Developer ID и проверки Apple.');
      const result = await install(options);
      console.log(`Liduo ${result.version} установлена: ${result.destination}`);
      if (result.backup) console.log(`Предыдущая копия: ${result.backup}`);
      if (!options.allowUnnotarized) console.log('Если macOS блокирует запуск, откройте Системные настройки → Конфиденциальность и безопасность → Все равно открыть.');
      console.log('Откройте Liduo в Finder и разрешите запись экрана в настройках macOS.');
    }
  } catch (error) {
    console.error(error.code === 'EACCES' || error.code === 'EPERM'
      ? 'Нет доступа к папке установки. Повторите с --app-dir "$HOME/Applications".' : error.message);
    process.exitCode = 1;
  }
}
