import test from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign } from 'node:crypto';
import { verifyArchive, verifyFeed, verifyUpdate } from '../scripts/verify-update.mjs';

const { privateKey, publicKey } = generateKeyPairSync('ed25519');
const publicBase64 = publicKey.export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
const content = Buffer.from('<?xml version="1.0"?><rss><channel/></rss>\n');
const signature = sign(null, content, privateKey).toString('base64');
const signed = Buffer.concat([content, Buffer.from(`<!-- sparkle-signatures:\nedSignature: ${signature}\nlength: ${content.length}\n-->\n`)]);

test('valid signed feed and archive are accepted', () => {
  assert.equal(verifyFeed(signed, publicBase64), content.toString());
  assert.doesNotThrow(() => verifyArchive(content, signature, publicBase64));
});

test('tampered feed or archive is rejected', () => {
  const changed = Buffer.from(signed); changed[8] ^= 1;
  assert.throws(() => verifyFeed(changed, publicBase64), /Invalid/);
  assert.throws(() => verifyArchive(Buffer.from('changed'), signature, publicBase64), /Invalid/);
});

test('unsigned feed, wrong key and incorrect length are rejected', () => {
  assert.throws(() => verifyFeed(content, publicBase64), /Missing/);
  const other = generateKeyPairSync('ed25519').publicKey.export({format:'der', type:'spki'}).subarray(-32).toString('base64');
  assert.throws(() => verifyFeed(signed, other), /Invalid/);
  const wrongLength = Buffer.from(signed.toString().replace(`length: ${content.length}`, 'length: 1'));
  assert.throws(() => verifyFeed(wrongLength, publicBase64), /Invalid/);
});

test('committed feed verifies against the app key and installer URL', async () => {
  await verifyUpdate(new URL('../updates/appcast.xml', import.meta.url));
});
