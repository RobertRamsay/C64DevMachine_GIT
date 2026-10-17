// node marinesheet.mjs out.png - the marine's frames as the game shows them:
// a row per direction: walk A, walk B, recoil (x4, on the deck floor grey)
import { buildSprites, SPR } from './art.mjs';
import { writePng } from './koala.mjs';
const PAL = [[0, 0, 0], [255, 255, 255], [136, 57, 50], [103, 182, 189], [139, 63, 150], [85, 160, 73], [64, 49, 141], [191, 206, 114],
  [139, 84, 41], [87, 66, 0], [184, 105, 98], [80, 80, 80], [120, 120, 120], [148, 224, 137], [120, 105, 196], [159, 159, 159]];
const { bytes } = buildSprites();
const S = 4, BG = PAL[11], cols = [BG, PAL[0], PAL[5], PAL[15]];   // bg, mc1 black, individual green, mc2 light grey
const frame = (f, x0, y0, img) => { for (let y = 0; y < 21; y++) for (let bx = 0; bx < 3; bx++) { const b = bytes[f * 64 + y * 3 + bx];
  for (let p = 0; p < 4; p++) { const c = (b >> (6 - 2 * p)) & 3; for (let dy = 0; dy < S; dy++) for (let dx = 0; dx < 2 * S; dx++) img[y0 + y * S + dy][x0 + (bx * 4 + p) * 2 * S + dx] = cols[c]; } } };
const W = 3 * (24 * S + 8) + 8, H = 8 * (21 * S + 8) + 8;
const img = Array.from({ length: H }, () => Array.from({ length: W }, () => [30, 30, 30]));
for (let d = 0; d < 8; d++) [SPR.MARINE + d * 2, SPR.MARINE + d * 2 + 1, SPR.RECOIL + d].forEach((f, k) => frame(f, 8 + k * (24 * S + 8), 8 + d * (21 * S + 8), img));
writePng(process.argv[2] || 'out/marine_sheet.png', img.map(r => r.flat()));
