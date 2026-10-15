// upscale a PNG screenshot (nearest) for inspection: node zoom.mjs in.png out.png scale [x y w h]
import zlib from 'zlib'; import fs from 'fs';
export function readPng(file) {
  const b = fs.readFileSync(file); let p = 8, w, h, ct, idat = [], plte = null;
  while (p < b.length) { const len = b.readUInt32BE(p), type = b.toString('ascii', p + 4, p + 8), d = b.slice(p + 8, p + 8 + len);
    if (type === 'IHDR') { w = d.readUInt32BE(0); h = d.readUInt32BE(4); ct = d[9]; if (d[8] !== 8) throw new Error('bit depth ' + d[8]); }
    if (type === 'PLTE') plte = d; if (type === 'IDAT') idat.push(d); p += 12 + len; }
  const raw = zlib.inflateSync(Buffer.concat(idat)); const bpp = { 2: 3, 6: 4, 3: 1, 0: 1 }[ct]; const stride = w * bpp;
  const out = Buffer.alloc(w * h * 3); let prev = Buffer.alloc(stride);
  for (let y = 0; y < h; y++) { const f = raw[y * (stride + 1)]; const line = Buffer.from(raw.slice(y * (stride + 1) + 1, (y + 1) * (stride + 1)));
    for (let i = 0; i < stride; i++) { const a = i >= bpp ? line[i - bpp] : 0, up = prev[i], c = i >= bpp ? prev[i - bpp] : 0;
      if (f === 1) line[i] = (line[i] + a) & 255; else if (f === 2) line[i] = (line[i] + up) & 255; else if (f === 3) line[i] = (line[i] + ((a + up) >> 1)) & 255;
      else if (f === 4) { const pp = a + up - c, pa = Math.abs(pp - a), pb = Math.abs(pp - up), pc = Math.abs(pp - c); line[i] = (line[i] + (pa <= pb && pa <= pc ? a : pb <= pc ? up : c)) & 255; } }
    for (let x = 0; x < w; x++) { if (ct === 3) { const k = line[x]; out[(y * w + x) * 3] = plte[k * 3]; out[(y * w + x) * 3 + 1] = plte[k * 3 + 1]; out[(y * w + x) * 3 + 2] = plte[k * 3 + 2]; }
      else if (ct === 0) { out.fill(line[x], (y * w + x) * 3, (y * w + x) * 3 + 3); } else { out[(y * w + x) * 3] = line[x * bpp]; out[(y * w + x) * 3 + 1] = line[x * bpp + 1]; out[(y * w + x) * 3 + 2] = line[x * bpp + 2]; } }
    prev = line; }
  return { w, h, rgb: out };
}
export function writeRgbPng(file, w, h, rgb) {
  const raw = Buffer.alloc((w * 3 + 1) * h); for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3); }
  const crcT = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; crcT[n] = c >>> 0; }
  const crc = buf => { let c = 0xFFFFFFFF; for (const x of buf) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
if (process.argv[1] && process.argv[1].endsWith('zoom.mjs')) {
  const [i, o, s, x0 = 0, y0 = 0, ww, hh] = process.argv.slice(2);
  const img = readPng(i); const S = +s; const W = +(ww || img.w), H = +(hh || img.h);
  const out = Buffer.alloc(W * S * H * S * 3);
  for (let y = 0; y < H * S; y++) for (let x = 0; x < W * S; x++) { const sx = +x0 + Math.floor(x / S), sy = +y0 + Math.floor(y / S); img.rgb.copy(out, (y * W * S + x) * 3, (sy * img.w + sx) * 3, (sy * img.w + sx) * 3 + 3); }
  writeRgbPng(o, W * S, H * S, out);
}
