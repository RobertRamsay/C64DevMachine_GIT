// node zoom.mjs in.png out.png x y w h scale  - crop + nearest-neighbour zoom (8-bit RGB/RGBA/palette PNGs)
import fs from 'fs'; import zlib from 'zlib';
const [inp, out, X, Y, W, H, S] = process.argv.slice(2); const x0 = +X, y0 = +Y, w = +W, h = +H, s = +S;
const b = fs.readFileSync(inp); let o = 8, ihdr, plte, idat = [];
while (o < b.length) { const len = b.readUInt32BE(o), t = b.toString('latin1', o + 4, o + 8), d = b.subarray(o + 8, o + 8 + len);
  if (t === 'IHDR') ihdr = { w: d.readUInt32BE(0), h: d.readUInt32BE(4), depth: d[8], ct: d[9] }; if (t === 'PLTE') plte = d; if (t === 'IDAT') idat.push(d); o += 12 + len; }
const raw = zlib.inflateSync(Buffer.concat(idat)); const bpp = { 2: 3, 6: 4, 3: 1, 0: 1 }[ihdr.ct]; const stride = ihdr.w * bpp;
const img = Buffer.alloc(ihdr.h * stride); let prev = Buffer.alloc(stride);
for (let y = 0; y < ihdr.h; y++) { const f = raw[y * (stride + 1)], line = raw.subarray(y * (stride + 1) + 1, (y + 1) * (stride + 1)), cur = Buffer.alloc(stride);
  for (let i = 0; i < stride; i++) { const a = i >= bpp ? cur[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0; let v = line[i];
    if (f === 1) v += a; else if (f === 2) v += up; else if (f === 3) v += (a + up) >> 1; else if (f === 4) { const p = a + up - c, pa = Math.abs(p - a), pb = Math.abs(p - up), pc = Math.abs(p - c); v += pa <= pb && pa <= pc ? a : pb <= pc ? up : c; }
    cur[i] = v & 255; } cur.copy(img, y * stride); prev = cur; }
const px = (x, y) => { const i = y * stride + x * bpp; if (bpp === 1) return [plte[img[i] * 3], plte[img[i] * 3 + 1], plte[img[i] * 3 + 2]]; return [img[i], img[i + 1], img[i + 2]]; };
const OW = w * s, OH = h * s, rows = [];
for (let y = 0; y < OH; y++) { const r = [0]; for (let x = 0; x < OW; x++) r.push(...px(x0 + Math.floor(x / s), y0 + Math.floor(y / s))); rows.push(Buffer.from(r)); }
const crc = (buf) => { let c, t = []; for (let n = 0; n < 256; n++) { c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } let r = 0xFFFFFFFF; for (const v of buf) r = t[(r ^ v) & 255] ^ (r >>> 8); return (r ^ 0xFFFFFFFF) >>> 0; };
const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
const hd = Buffer.alloc(13); hd.writeUInt32BE(OW, 0); hd.writeUInt32BE(OH, 4); hd[8] = 8; hd[9] = 2;
fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', hd), chunk('IDAT', zlib.deflateSync(Buffer.concat(rows))), chunk('IEND', Buffer.alloc(0))]));
