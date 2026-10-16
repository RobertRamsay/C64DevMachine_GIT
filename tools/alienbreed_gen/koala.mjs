// Koala (.kla) multicolour bitmap helpers.
//   node koala.mjs in.kla out.png   - render to PNG (VICE-like palette)
import fs from 'fs';
import zlib from 'zlib';

export const PALETTE = [[0, 0, 0], [255, 255, 255], [136, 57, 50], [103, 182, 189], [139, 63, 150], [85, 160, 73], [64, 49, 141], [191, 206, 114],
  [139, 84, 41], [87, 66, 0], [184, 105, 98], [80, 80, 80], [120, 120, 120], [148, 224, 137], [120, 105, 196], [159, 159, 159]];
// { bitmap[8000], screen[1000], colour[1000], bg }
export function readKoala(file) {
  const b = fs.readFileSync(file);
  if (b.length < 10003) throw new Error(file + ': not a Koala file (' + b.length + ' bytes)');
  return { bitmap: [...b.subarray(2, 8002)], screen: [...b.subarray(8002, 9002)], colour: [...b.subarray(9002, 10002)].map(c => c & 15), bg: b[10002] & 15 };
}
// 160 x 200 colour indices
export function koalaPixels(k) {
  const px = Array.from({ length: 200 }, () => Array(160).fill(0));
  for (let cy = 0; cy < 25; cy++) for (let cx = 0; cx < 40; cx++) {
    const i = cy * 40 + cx, sc = k.screen[i];
    const cols = [k.bg, sc >> 4, sc & 15, k.colour[i]];
    for (let y = 0; y < 8; y++) { const byte = k.bitmap[i * 8 + y]; for (let x = 0; x < 4; x++) px[cy * 8 + y][cx * 4 + x] = cols[(byte >> (6 - 2 * x)) & 3]; }
  }
  return px;
}
export function writePng(file, rgbRows) {
  const h = rgbRows.length, w = rgbRows[0].length / 3;
  const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = buf => { let r = 0xFFFFFFFF; for (const v of buf) r = crcT[(r ^ v) & 255] ^ (r >>> 8); return (r ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const hd = Buffer.alloc(13); hd.writeUInt32BE(w, 0); hd.writeUInt32BE(h, 4); hd[8] = 8; hd[9] = 2;
  const raw = Buffer.concat(rgbRows.map(r => Buffer.from([0, ...r])));
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', hd), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
if (process.argv[1] && process.argv[1].endsWith('koala.mjs')) {
  const [inp, out] = process.argv.slice(2);
  const k = readKoala(inp), px = koalaPixels(k);
  writePng(out, px.map(r => r.flatMap(c => [...PALETTE[c], ...PALETTE[c]])));
  const used = new Set(px.flat()); console.log('bg', k.bg, 'colours used', [...used].sort((a, b) => a - b).join(','));
  const rowsUsed = px.map((r, y) => r.some(c => c !== k.bg) ? y : -1).filter(y => y >= 0);
  console.log('artwork rows', rowsUsed[0], '-', rowsUsed[rowsUsed.length - 1]);
}
