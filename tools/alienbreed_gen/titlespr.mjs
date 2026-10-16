// ALIEN BREED 64 title sprite text, drawn to match the logo on the Koala
// picture: tall condensed letters, shaded top to bottom like the logo
// (blue, blue/purple dither, purple, purple/light blue dither).
//
// Multicolour sprites, Y-expanded: a glyph row is one sprite row (two raster
// lines), so the 14-row letters stand 28 lines tall like ALIEN / BREED.
// Bit pairs: 10 = sprite colour (blue, or dark grey when dimmed),
// 01 = $D025 (purple), 11 = $D026 (light blue).
export const TITLE_SPR_COLS = { individual: 6, dim: 11, mc1: 4, mc2: 14 };
const G = s => s.trim().split('\n').map(r => r.trim());
const FONT = {
  A: G(`.##.\n####\n#..#\n#..#\n#..#\n#..#\n####\n####\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#`),
  C: G(`.###\n####\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n####\n.###`),
  E: G(`####\n####\n#...\n#...\n#...\n#...\n###.\n###.\n#...\n#...\n#...\n#...\n####\n####`),
  F: G(`####\n####\n#...\n#...\n#...\n#...\n###.\n###.\n#...\n#...\n#...\n#...\n#...\n#...`),
  I: G(`##\n##\n##\n##\n##\n##\n##\n##\n##\n##\n##\n##\n##\n##`),
  L: G(`#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n#...\n####\n####`),
  O: G(`.##.\n####\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n####\n.##.`),
  P: G(`###.\n####\n#..#\n#..#\n#..#\n#..#\n####\n###.\n#...\n#...\n#...\n#...\n#...\n#...`),
  R: G(`###.\n####\n#..#\n#..#\n#..#\n#..#\n####\n###.\n#.#.\n#.#.\n#..#\n#..#\n#..#\n#..#`),
  S: G(`.###\n####\n#...\n#...\n#...\n##..\n.##.\n..##\n...#\n...#\n...#\n...#\n####\n###.`),
  T: G(`####\n####\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.`),
  U: G(`#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n####\n.##.`),
  Y: G(`#..#\n#..#\n#..#\n#..#\n#..#\n####\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.\n.##.`),
  4: G(`#..#\n#..#\n#..#\n#..#\n#..#\n#..#\n####\n####\n...#\n...#\n...#\n...#\n...#\n...#`),
  6: G(`.###\n####\n#...\n#...\n#...\n###.\n####\n#..#\n#..#\n#..#\n#..#\n#..#\n####\n.##.`),
  ' ': G(`..\n..\n..\n..\n..\n..\n..\n..\n..\n..\n..\n..\n..\n..`),
};
// the shading: bit pair for a lit pixel at row y, column x
function shade(y, x) {
  if (y < 3) return 2;
  if (y < 6) return (x + y) & 1 ? 2 : 1;
  if (y < 9) return 1;
  if (y < 12) return (x + y) & 1 ? 1 : 3;
  return 3;
}
// a word as rows of multicolour pixels (0-3)
function strip(word, dim) {
  const rows = Array.from({ length: 14 }, () => []);
  [...word].forEach((ch, i) => {
    const g = FONT[ch];
    if (!g) throw new Error('no glyph ' + ch);
    if (i) rows.forEach(r => r.push(0));                 // 1 pixel between letters
    g.forEach((r, y) => [...r].forEach(c => rows[y].push(c === '#' ? (dim ? 2 : shade(y, rows[y].length)) : 0)));
  });
  return rows;
}
// cut a strip into 12-pixel sprites (64 bytes each)
function sprites(rows) {
  const w = rows[0].length, n = Math.ceil(w / 12), out = [];
  for (let s = 0; s < n; s++) {
    const b = [];
    for (let y = 0; y < 21; y++) for (let k = 0; k < 3; k++) {
      let v = 0;
      for (let i = 0; i < 4; i++) v = (v << 2) | ((rows[y] || [])[s * 12 + k * 4 + i] || 0);
      b.push(v);
    }
    b.push(0);
    out.push(b);
  }
  return { frames: out, width: w };
}

// Layout: the picture leaves columns 0-13 and 25-39 free above and below
// the logo row. Top band: C64 | C64U (the version), bottom band:
// PRESS FIRE | TO PLAY. X = VIC sprite X (screen pixel + 24).
export const BANDS = { TOP_Y: 0x50, LOW_Y: 0xCC, LEFT_CX: 56, RIGHT_CX: 260 };
export function buildTitleSprites() {
  const frames = [];
  const add = s => { const first = frames.length; frames.push(...s.frames); return { first, n: s.frames.length, width: s.width }; };
  const W = {
    C64: add(sprites(strip('C64', false))), C64D: add(sprites(strip('C64', true))),
    C64U: add(sprites(strip('C64U', false))), C64UD: add(sprites(strip('C64U', true))),
    PRESS: add(sprites(strip('PRESS FIRE', false))), PLAY: add(sprites(strip('TO PLAY', false))),
  };
  if (frames.length > 16) throw new Error('title sprite text needs ' + frames.length + ' frames (16 fit at $C000)');
  // X positions of a word's sprites, centred on cx (screen pixels)
  const xs = (w, cx) => { const px = w.width * 2, x0 = 24 + cx - Math.floor(px / 2); return Array.from({ length: w.n }, (_, k) => x0 + 24 * k); };
  const top = [...xs(W.C64, BANDS.LEFT_CX), ...xs(W.C64U, BANDS.RIGHT_CX)];
  const low = [...xs(W.PRESS, BANDS.LEFT_CX), ...xs(W.PLAY, BANDS.RIGHT_CX)];
  if (top.length > 8 || low.length > 8) throw new Error('more than 8 sprites in a band');
  return { bytes: frames.flat(), count: frames.length, W, top, low };
}
