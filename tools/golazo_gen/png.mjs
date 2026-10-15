// Minimal PNG writer (RGB) for previews, plus the C64 palette.
import zlib from 'zlib';
import fs from 'fs';

export const PALETTE = [
  [0x00, 0x00, 0x00], [0xFF, 0xFF, 0xFF], [0x68, 0x37, 0x2B], [0x70, 0xA4, 0xB2],
  [0x6F, 0x3D, 0x86], [0x58, 0x8D, 0x43], [0x35, 0x28, 0x79], [0xB8, 0xC7, 0x6F],
  [0x6F, 0x4F, 0x25], [0x43, 0x39, 0x00], [0x9A, 0x67, 0x59], [0x44, 0x44, 0x44],
  [0x6C, 0x6C, 0x6C], [0x9A, 0xD2, 0x84], [0x6C, 0x5E, 0xB5], [0x95, 0x95, 0x95],
];

const CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
function crc32(buf) { let c = 0xFFFFFFFF; for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; }
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}

// pix(x, y) -> C64 colour index
export function writePng(path, w, h, pix, scale = 1) {
  const W = w * scale, H = h * scale;
  const raw = Buffer.alloc((W * 3 + 1) * H);
  for (let y = 0; y < H; y++) {
    raw[y * (W * 3 + 1)] = 0;
    for (let x = 0; x < W; x++) {
      const c = PALETTE[pix(Math.floor(x / scale), Math.floor(y / scale)) & 15];
      const o = y * (W * 3 + 1) + 1 + x * 3;
      raw[o] = c[0]; raw[o + 1] = c[1]; raw[o + 2] = c[2];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  fs.writeFileSync(path, Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
    chunk('IHDR', ihdr), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0)),
  ]));
}
