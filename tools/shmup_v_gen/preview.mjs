// Render the generated art to PNGs for a quick look: node preview.mjs OUTDIR
import { writePng } from '../golazo_gen/png.mjs';
import { buildCharset, buildMap, buildSprites, buildTitle, buildSpawns, STAMPS, MAP_ROWS, MAP_COLS } from './art.mjs';

const out = process.argv[2] || '.';
const cs = buildCharset();
const mc = [0, 12, 11, 5];             // space, $D022, $D023, colour RAM nibble & 7
const sprites = buildSprites();
const map = buildMap();
const spawns = buildSpawns(map);

const charPix = (c, x, y) => {
  const b = cs.bytes[c * 8 + y];
  return mc[(b >> (6 - (x & 6))) & 3];
};
// the whole map, chars expanded from 2x2 stamps; spawns as yellow boxes
const W = MAP_COLS * 16, H = MAP_ROWS * 16;
const box = new Uint8Array(W * H);
for (const [c, r, t] of spawns) for (let y = 0; y < 24; y++) for (let x = 0; x < 24; x++) if (x === 0 || y === 0 || x === 23 || y === 23) {
  const px = c * 8 + x, py = r * 8 + y;
  if (px < W && py < H) box[py * W + px] = t === 1 ? 2 : 7;
}
writePng(`${out}/v_map.png`, W, H, (x, y) => {
  if (box[y * W + x]) return box[y * W + x];
  const st = map.grid[Math.floor(y / 16) * MAP_COLS + Math.floor(x / 16)];
  const cell = ((y >> 3) & 1) * 2 + ((x >> 3) & 1);
  return charPix(STAMPS[st][1][cell], x & 7, y & 7);
}, 2);
writePng(`${out}/v_sprites.png`, 26 * sprites.list.length, 22, (x, y) => {
  const i = Math.floor(x / 26), sx = x % 26;
  if (sx >= 24 || y >= 21) return 11;
  return sprites.list[i][1][y][sx] ? sprites.list[i][2] : 0;
}, 3);
const t = buildTitle(sprites);
writePng(`${out}/v_title.png`, 320, 200, (x, y) => t.px[y * 320 + x] ? t.cellFg[(y >> 3) * 40 + (x >> 3)] : 0, 2);
console.log('left ', map.left.join(''));
console.log('right', map.right.join(''));
console.log('spawns', spawns.length, JSON.stringify(spawns));
