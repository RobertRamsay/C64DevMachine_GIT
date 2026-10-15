import { buildCharset, FW, FH } from './pitch.mjs';
import { writePng } from './png.mjs';
const r = buildCharset();
console.log("used", r.used, 'unique pitch', r.uniquePitch);
const col = [0, 5, 13, 1];
writePng('out/pitch.png', FW * 2, FH, (x, y) => col[r.canvas[y * FW + (x >> 1)]], 1);
