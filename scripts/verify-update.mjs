#!/usr/bin/env node
import { createPublicKey, verify } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { validateRelease, verifyChecksum } from '../installer/cli.mjs';

function keyFromBase64(publicKey) {
  const raw = Buffer.from(publicKey, 'base64');
  if (raw.length !== 32) throw new Error('Expected a 32-byte Ed25519 public key.');
  return createPublicKey({ key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), raw]), format: 'der', type: 'spki' });
}

export function verifyFeed(data, publicKey) {
  const marker = Buffer.from('<!-- sparkle-signatures:\n');
  const start = data.lastIndexOf(marker);
  if (start < 0) throw new Error('Missing feed signature.');
  const block = data.subarray(start).toString('utf8');
  const fields = block.match(/^<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/=]+)\nlength: (\d+)\n-->\n?$/);
  const content = data.subarray(0, start);
  if (!fields || Number(fields[2]) !== content.length ||
      !verify(null, content, keyFromBase64(publicKey), Buffer.from(fields[1], 'base64'))) {
    throw new Error('Invalid feed signature or length.');
  }
  return content.toString('utf8');
}

export function verifyArchive(data, signature, publicKey) {
  if (!verify(null, data, keyFromBase64(publicKey), Buffer.from(signature, 'base64'))) throw new Error('Invalid archive signature.');
}

export async function verifyUpdate(feedPath, archivePath) {
  const root = fileURLToPath(new URL('../', import.meta.url));
  const plist = await readFile(path.join(root, 'Liduo/Info.plist'), 'utf8');
  const publicKey = plist.match(/<key>SUPublicEDKey<\/key>\s*<string>([^<]+)<\/string>/)?.[1];
  const manifest = JSON.parse(await readFile(path.join(root, 'installer/release.json'), 'utf8'));
  const xml = verifyFeed(await readFile(feedPath), publicKey);
  const expectedURL = validateRelease(manifest);
  const enclosures = [...xml.matchAll(/<enclosure\b([^>]+)>/g)].map(match =>
    Object.fromEntries([...match[1].matchAll(/([\w:]+)="([^"]*)"/g)].map(m => [m[1], m[2]])));
  const item = enclosures.find(entry => entry.url === expectedURL);
  if (!item) throw new Error('Current release download missing from feed.');
  if (archivePath) {
    const archive = await readFile(archivePath);
    verifyChecksum(archive, manifest.sha256);
    if (Number(item.length) !== archive.length) throw new Error('Archive length mismatch.');
    verifyArchive(archive, item['sparkle:edSignature'], publicKey);
  }
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    await verifyUpdate(process.argv[2] ?? 'updates/appcast.xml', process.argv[3]);
    console.log('Feed and supplied archive verified with the public key (no Keychain access).');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
