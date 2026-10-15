import { FRAMES } from './sprites.mjs';
import { writePng } from './png.mjs';
const cols = 12, cw = 28, ch = 25;
const rowsN = Math.ceil(FRAMES.length / cols);
const shirt = process.argv[2] ? +process.argv[2] : 2;
writePng('out/sprites.png', cols * cw, rowsN * ch, (x, y) => {
  const f = Math.floor(y / ch) * cols + Math.floor(x / cw);
  const sx = x % cw - 2, sy = y % ch - 2;
  const bg = (Math.floor(x / 64) & 1) ? 13 : 5;
  if (f >= FRAMES.length || sx < 0 || sx >= 24 || sy < 0 || sy >= 21) return bg;
  const c = FRAMES[f][1][sy][sx >> 1];
  return { '.': bg, S: 10, C: f >= 30 && f <= 32 ? 1 : shirt, B: 0 }[c];
}, 3);
