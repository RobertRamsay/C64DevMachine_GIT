// Title screen: a full-PETSCII picture (ROM upper/graphics charset plus a
// few grass glyphs) composed here and copied to screen A by TitleDraw.
//
// Rows 0-19 are hires (colour RAM 0-15, black background). The title IRQ
// turns multicolour on at line $D1, so rows 20-24 are multicolour: there
// colour RAM 0-7 is still hires (the ad boards) and 8-15 draws the grass
// glyphs with $D022 green / $D023 light green.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));

export const TITLE_CHARS = 0x7800;      // VIC bank 1, $D018 = $0E with screen A
export const TITLE_SCR = 0x7000;        // 1000 screen codes
export const TITLE_COL = 0x73E8;        // 1000 colours
export const TITLE_D018 = 0x0E;

// custom glyphs in slots the picture doesn't use ([ \ ] up-arrow left-arrow)
const G_GRASS1 = 0x1B, G_GRASS2 = 0x1C, G_LINE1 = 0x1D, G_LINE2 = 0x1E;

// PETSCII screen codes used below
const P = {
  SP: 0x20, FULL: 0xA0, HLINE: 0x40, VLINE: 0x5D,
  RTL: 0x55, RTR: 0x49, RBL: 0x4A, RBR: 0x4B,     // rounded corners
  TEE_L: 0x6B, TEE_R: 0x73,
  BALL: 0x51, RING: 0x57, DOT: 0x2E, PLUS: 0x2B, STAR: 0x2A,
  DIAG_D: 0x4D, DIAG_U: 0x4E,                     // \ and /
  UPPER: 0xE2, LOWER: 0x62, LEFT: 0x61, RIGHT: 0xE1,
  TRI_UL: 0x69, TRI_UR: 0x5F, TRI_LL: 0xDF, TRI_LR: 0xE9,
};

function romChars() {
  const p = path.join(HERE, '..', '..', 'C64DevMachine_win.yyp', 'datafiles', 'vice', 'win', 'C64', 'chargen');
  return Array.from(fs.readFileSync(p).subarray(0, 2048));
}

function code(ch) {
  if (ch >= 'A' && ch <= 'Z') return ch.charCodeAt(0) - 64;
  const c = ch.charCodeAt(0);
  if (c >= 32 && c < 64) return c;
  throw new Error('no screen code for ' + ch);
}

// glyph tokens for the big logo letters (4 x 5 cells)
const TOK = {
  '#': P.FULL, d: P.TRI_LR, c: P.TRI_LL, b: P.TRI_UR, a: P.TRI_UL,
  u: P.UPPER, n: P.LOWER, '[': P.LEFT, ']': P.RIGHT,
};
const BIG = {
  G: ['d##c', '#   ', '# ##', '#  #', 'b##a'],
  O: ['d##c', '#  #', '#  #', '#  #', 'b##a'],
  L: ['#   ', '#   ', '#   ', '#   ', 'b###'],
  A: ['d##c', '#  #', '####', '#  #', '#  #'],
  Z: ['####', '  da', ' da ', 'da  ', '####'],
};
// 3 x 6 half-cell digits, packed into 3 x 3 cells with upper/lower halves
const SMALL = {
  6: ['###', '#..', '###', '#.#', '#.#', '###'],
  4: ['#.#', '#.#', '#.#', '###', '..#', '..#'],
};

function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1103515245 + 12345) >>> 0; return (s >>> 16) & 0x7fff; }; }

export function buildTitle() {
  const scr = new Array(1000).fill(P.SP), col = new Array(1000).fill(0);
  const used = new Array(1000).fill(false);
  const put = (x, y, c, k) => {
    if (x < 0 || x > 39 || y < 0 || y > 24) return;
    scr[y * 40 + x] = c; col[y * 40 + x] = k; used[y * 40 + x] = true;
  };
  const text = (x, y, s, k, rev = 0) => [...s].forEach((ch, i) => put(x + i, y, code(ch) | rev, typeof k === 'function' ? k(i) : k));
  const centre = (y, s, k, rev) => text(Math.floor((40 - s.length) / 2), y, s, k, rev);
  const R = rng(1966);

  // ---- floodlight towers: lamp heads rows 0-2, lattice pylons down to the stand
  for (const x0 of [0, 36]) {
    for (let x = 0; x < 4; x++) {
      put(x0 + x, 0, P.BALL, (x & 1) ? 7 : 1);
      put(x0 + x, 1, P.BALL, (x & 1) ? 1 : 7);
      put(x0 + x, 2, P.UPPER, 12);
    }
    for (let y = 3; y <= 18; y++) {
      put(x0 + 1, y, (y & 1) ? P.DIAG_D : P.DIAG_U, 11);
      put(x0 + 2, y, (y & 1) ? P.DIAG_U : P.DIAG_D, 11);
    }
  }

  // ---- GOLAZO in big rounded block letters, rows 1-5, in a yellow-to-red gradient
  const word = 'GOLAZO';
  const W = word.length * 5 - 1, lx = Math.floor((40 - W) / 2), ly = 1;
  const GRAD = [7, 7, 8, 8, 2];
  const cells = [];
  [...word].forEach((ch, i) => BIG[ch].forEach((row, r) => [...row].forEach((t, c) => {
    if (t !== ' ') cells.push([lx + i * 5 + c, ly + r, TOK[t]]);
  })));
  for (const [x, y, c] of cells) put(x, y, c, GRAD[y - ly]);

  // ---- "64" in half-cell digits between two fading rules, rows 7-9
  const dx = 17;
  ['6', '4'].forEach((d, i) => {
    const g = SMALL[d];
    for (let r = 0; r < 3; r++) for (let c = 0; c < 3; c++) {
      const up = g[r * 2][c] === '#', lo = g[r * 2 + 1][c] === '#';
      if (up || lo) put(dx + i * 4 + c, 7 + r, up && lo ? P.FULL : up ? P.UPPER : P.LOWER, [14, 14, 6][r]);
    }
  });
  const FADE = [6, 11, 4, 14, 3, 1];
  for (let i = 0; i < 11; i++) {
    const k = FADE[Math.min(FADE.length - 1, Math.floor(i * FADE.length / 11))];
    put(5 + i, 8, P.HLINE, k);
    put(34 - i, 8, P.HLINE, k);
  }

  // ---- strapline
  centre(11, 'THE BEAUTIFUL GAME', 1);
  put(9, 11, P.BALL, 7); put(30, 11, P.BALL, 7);

  // ---- menu box, rows 12-17 (rounded corners)
  const bx0 = 5, bx1 = 34, by0 = 12, by1 = 17, BOX = 14;
  for (let x = bx0 + 1; x < bx1; x++) { put(x, by0, P.HLINE, BOX); put(x, by1, P.HLINE, BOX); }
  for (let y = by0 + 1; y < by1; y++) { put(bx0, y, P.VLINE, BOX); put(bx1, y, P.VLINE, BOX); }
  put(bx0, by0, P.RTL, BOX); put(bx1, by0, P.RTR, BOX); put(bx0, by1, P.RBL, BOX); put(bx1, by1, P.RBR, BOX);
  put(bx0, 15, P.TEE_L, BOX); put(bx1, 15, P.TEE_R, BOX);
  for (let x = bx0 + 1; x < bx1; x++) put(x, 15, P.HLINE, 6);
  const menu = (y, left, right) => {
    const inner = bx1 - bx0 - 1, x = bx0 + 2;
    put(x, y, P.BALL, 1);
    text(x + 2, y, left, 7);
    const rx = bx0 + inner - right.length;
    for (let i = x + 3 + left.length; i < rx - 1; i++) put(i, y, P.DOT, 11);
    text(rx, y, right, 1);
  };
  menu(13, 'PORT 2 FIRE', '1 PLAYER');
  menu(14, 'PORT 1 FIRE', '2 PLAYERS');
  text(7, 16, 'C64', 14); text(11, 16, 'IN BLUE', 14);
  text(19, 16, 'V', 7);
  text(21, 16, 'VIC', 1); text(25, 16, 'IN WHITE', 1);

  // ---- crowd, rows 18-19 (between the pylons on row 18). Row 19 is the
  // last hires row and the multicolour switch lands in its last pixel line,
  // so it keeps to colours 0-7.
  const FACE = [1, 7, 2, 3, 4, 6, 1, 6, 14, 10, 15, 8];
  for (let y = 18; y < 20; y++) for (let x = 0; x < 40; x++) {
    if (used[y * 40 + x]) continue;
    const k = FACE[R() % (y === 19 ? 6 : FACE.length)];
    put(x, y, R() % 6 ? P.BALL : P.RING, k);
  }

  // ---- ad boards, row 20 (hires: colours 0-7, reverse text)
  const boards = [[' GOLAZO 64 ', 7], [' DEV MACHINE ', 3], [' C64 ', 1], [' VIC ', 2], [' GOAL ', 5]];
  let bx = 0, bi = 0;
  while (bx < 40) {
    const [s, k] = boards[bi++ % boards.length];
    text(bx, 20, s.slice(0, 40 - bx), k, 0x80);
    bx += s.length;
  }

  // ---- pitch, rows 21-24: touchline on top of mown stripes (multicolour)
  for (let x = 0; x < 40; x++) {
    const s = (x >> 2) & 1;
    put(x, 21, s ? G_LINE2 : G_LINE1, 9);
    for (let y = 22; y < 25; y++) put(x, y, s ? G_GRASS2 : G_GRASS1, 9);
  }

  // ---- stars in the free sky, rows 0-11, kept off the lettering
  for (let i = 0; i < 40; i++) {
    const x = R() % 40, y = R() % 12;
    if (used[y * 40 + x] || used[y * 40 + x - 1] || used[y * 40 + x + 1] || (y >= ly - 1 && y <= ly + 5 && x >= lx - 1 && x <= lx + W) || (y >= 6 && y <= 10 && x >= dx - 1 && x <= dx + 7)) continue;
    const r = R() % 8;
    put(x, y, r < 6 ? P.DOT : P.PLUS, [11, 12, 15, 1, 11, 12, 7, 1][r]);
  }

  // ---- charset: ROM glyphs plus the grass
  const charset = romChars();
  const setGlyph = (i, bytes) => bytes.forEach((b, j) => { charset[i * 8 + j] = b; });
  setGlyph(G_GRASS1, Array(8).fill(0x55));
  setGlyph(G_GRASS2, Array(8).fill(0xAA));
  setGlyph(G_LINE1, [0xFF, ...Array(7).fill(0x55)]);
  setGlyph(G_LINE2, [0xFF, ...Array(7).fill(0xAA)]);
  return { charset, scr, col };
}

// ---- preview PNG (node title.mjs out.png): VICE-like rendering, 2x
const PAL = [0x000000, 0xFFFFFF, 0x813338, 0x75CEC8, 0x8E3C97, 0x56AC4D, 0x2E2C9B, 0xEDF171,
  0x8E5029, 0x553800, 0xC46C71, 0x4A4A4A, 0x7B7B7B, 0xA9FF9F, 0x706DEB, 0xB2B2B2];
function png(file, w, h, rgb) {
  const zlib = awaitZlib();
  const raw = Buffer.alloc((w * 3 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 3 + 1)] = 0; rgb.copy(raw, y * (w * 3 + 1) + 1, y * w * 3, (y + 1) * w * 3); }
  const crcT = [...Array(256)].map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc = b => { let c = 0xFFFFFFFF; for (const x of b) c = crcT[(c ^ x) & 255] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const chunk = (t, d) => { const l = Buffer.alloc(4); l.writeUInt32BE(d.length); const td = Buffer.concat([Buffer.from(t), d]); const c = Buffer.alloc(4); c.writeUInt32BE(crc(td)); return Buffer.concat([l, td, c]); };
  const ih = Buffer.alloc(13); ih.writeUInt32BE(w, 0); ih.writeUInt32BE(h, 4); ih[8] = 8; ih[9] = 2;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ih), chunk('IDAT', zlib.deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]));
}
let _z;
function awaitZlib() { return _z; }
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  _z = (await import('zlib')).default;
  const { charset, scr, col } = buildTitle();
  const S = 2, W = 320 * S, H = 200 * S, rgb = Buffer.alloc(W * H * 3);
  const D022 = 5, D023 = 13;
  for (let y = 0; y < 200; y++) for (let x = 0; x < 320; x++) {
    const i = (y >> 3) * 40 + (x >> 3), ch = scr[i], k = col[i], b = charset[ch * 8 + (y & 7)];
    let c;
    if ((y >> 3) >= 20 && k >= 8) {
      const pr = (b >> (6 - (x & 6))) & 3;
      c = [0, D022, D023, k & 7][pr];
    } else c = (b >> (7 - (x & 7))) & 1 ? k : 0;
    for (let sy = 0; sy < S; sy++) for (let sx = 0; sx < S; sx++) {
      const o = ((y * S + sy) * W + x * S + sx) * 3, v = PAL[c];
      rgb[o] = v >> 16; rgb[o + 1] = (v >> 8) & 255; rgb[o + 2] = v & 255;
    }
  }
  png(process.argv[2] || 'out/title_preview.png', W, H, rgb);
}
