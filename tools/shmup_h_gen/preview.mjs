// Render the generated art to PNGs for a quick look: node preview.mjs OUTDIR
import { writePng } from '../golazo_gen/png.mjs';
import { buildCharset, buildMap, buildSprites, buildTitle, STAMPS, MAP_ROWS, MAP_COLS } from './art.mjs';

const out = process.argv[2] || '.';
const cs = buildCharset();
const mc = [0, 12, 9, 5];              // space, $D022, $D023, colour RAM nibble & 7
const sprites = buildSprites();
const map = buildMap();

const charPix = (c, x, y, multi) => {
  const b = cs.bytes[c * 8 + y];
  if (!multi) return (b >> (7 - x)) & 1 ? 1 : 0;
  return mc[(b >> (6 - (x & 6))) & 3];
};
// the visible map, chars expanded from 2x2 stamps
const W = MAP_COLS * 16, H = MAP_ROWS * 16;
writePng(`${out}/h_map.png`, W, H, (x, y) => {
  const st = map.grid[Math.floor(y / 16) * MAP_COLS + Math.floor(x / 16)];
  const cell = ((y >> 3) & 1) * 2 + ((x >> 3) & 1);
  return charPix(STAMPS[st][1][cell], x & 7, y & 7, true);
}, 2);
writePng(`${out}/h_sprites.png`, 26 * sprites.list.length, 22, (x, y) => {
  const i = Math.floor(x / 26), sx = x % 26;
  if (sx >= 24 || y >= 21) return 11;
  return sprites.list[i][1][y][sx] ? sprites.list[i][2] : 0;
}, 3);
const t = buildTitle(sprites);
writePng(`${out}/h_title.png`, 320, 200, (x, y) => t.px[y * 320 + x] ? t.cellFg[(y >> 3) * 40 + (x >> 3)] : 0, 2);
console.log('floor', map.floor.join(''));
console.log('ceil ', map.ceil.join(''));
