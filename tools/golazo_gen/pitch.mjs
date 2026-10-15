// The stadium: a 128 x 48 char map (1024 x 384 hires pixels) drawn as a
// multicolour picture, cut into 4x8 cells and de-duplicated into the
// charset. Colour RAM is the same (9 = multicolour white) for every pitch
// cell, so scrolling never touches colour RAM.
//
// MC colours: 0 = $D021 black (stands), 1 = $D022 green, 2 = $D023 light
// green, 3 = colour RAM white (lines, boards, goal frames).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
export const MAPW = 128, MAPH = 48;
export const FW = MAPW * 4, FH = MAPH * 8;       // fat-pixel canvas 512 x 384

// Pitch geometry in hires pixels (game coordinates).
export const G = {
  TOP: 72, BOT: 351,            // touchlines (rows)
  LEFT: 112, RIGHT: 911,        // goal lines (x); line pixels are fat px 56 and 455
  MIDX: 512, MIDY: 212,
  POST_T: 188, POST_B: 236,     // goal mouth (y)
  BAR_H: 20,                    // crossbar height (z)
  NET: 16,                      // net depth behind the goal line
  BOX_D: 132, BOX_T: 129, BOX_B: 295,
  SIX_D: 44, SIX_T: 174, SIX_B: 250,
  SPOT_D: 88,
  CIRC_RX: 72, CIRC_RY: 40,
};

// ROM font (screen codes 0-63) for the HUD / title text.
export function romFont() {
  const p = path.join(HERE, '..', '..', 'C64DevMachine_win.yyp', 'datafiles', 'vice', 'win', 'C64', 'chargen');
  const rom = fs.readFileSync(p);
  const out = [];
  for (let c = 0; c < 64; c++) out.push(Array.from(rom.slice(c * 8, c * 8 + 8)));
  return out;
}

function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1103515245 + 12345) >>> 0; return (s >>> 16) & 0x7fff; }; }

// 3x5 board lettering (fat pixels)
const MINI = {
  A: ['010', '101', '111', '101', '101'], B: ['110', '101', '110', '101', '110'], C: ['011', '100', '100', '100', '011'],
  D: ['110', '101', '101', '101', '110'], E: ['111', '100', '110', '100', '111'], F: ['111', '100', '110', '100', '100'],
  G: ['011', '100', '101', '101', '011'], H: ['101', '101', '111', '101', '101'], I: ['111', '010', '010', '010', '111'],
  K: ['101', '101', '110', '101', '101'], L: ['100', '100', '100', '100', '111'], M: ['101', '111', '111', '101', '101'],
  N: ['110', '101', '101', '101', '101'], O: ['010', '101', '101', '101', '010'], P: ['110', '101', '110', '100', '100'],
  R: ['110', '101', '110', '101', '101'], S: ['011', '100', '010', '001', '110'], T: ['111', '010', '010', '010', '010'],
  U: ['101', '101', '101', '101', '011'], V: ['101', '101', '101', '101', '010'], Y: ['101', '101', '010', '010', '010'],
  Z: ['111', '001', '010', '100', '111'], 6: ['011', '100', '110', '101', '010'], 4: ['101', '101', '111', '001', '001'],
  '*': ['000', '101', '010', '101', '000'], ' ': ['000', '000', '000', '000', '000'], '!': ['010', '010', '010', '000', '010'],
};

export function buildPitch() {
  const cv = new Uint8Array(FW * FH);
  const set = (fx, y, c) => { if (fx >= 0 && fx < FW && y >= 0 && y < FH) cv[y * FW + fx] = c; };
  const get = (fx, y) => cv[y * FW + fx];
  const hx = x => Math.floor(x / 2);   // hires x -> fat x

  // grass stripes (32 px = 4 chars), whole canvas below the stands
  for (let y = 0; y < FH; y++)
    for (let fx = 0; fx < FW; fx++)
      set(fx, y, (Math.floor(fx / 16) & 1) ? 2 : 1);

  // ---- stands (top rows 0-4, ends x < 48) : black with a crowd of heads
  const r = rng(1964);
  const crowdTile = [];
  for (let v = 0; v < 6; v++) {           // 6 crowd cells, 4x8 fat px, tiled
    const t = new Uint8Array(32);
    for (let yy = 0; yy < 8; yy += 4) for (let xx = 0; xx < 4; xx += 2) {
      const pick = r() % 7;
      const c = [3, 2, 3, 1, 2, 0, 3][pick];
      const ox = xx + ((r() >> 3) & 1) * 0, oy = yy + (r() & 1);
      if (c) { t[oy * 4 + ox] = c; t[(oy + 1) * 4 + ox] = (c === 3 ? 1 : c); if (r() & 1) t[oy * 4 + ox + 1] = c; }
    }
    crowdTile.push(t);
  }
  const crowdCell = (cx, cy, v) => {
    const t = crowdTile[v];
    for (let yy = 0; yy < 8; yy++) for (let xx = 0; xx < 4; xx++) set(cx * 4 + xx, cy * 8 + yy, t[yy * 4 + xx]);
  };
  for (let cy = 0; cy < 5; cy++) for (let cx = 0; cx < MAPW; cx++) crowdCell(cx, cy, (cx * 7 + cy * 3 + ((cx >> 2) & 1)) % 6);
  for (let cy = 5; cy < MAPH; cy++) for (let cx = 0; cx < 6; cx++) crowdCell(cx, cy, (cx * 5 + cy * 3) % 6);
  for (let cy = 5; cy < MAPH; cy++) for (let cx = MAPW - 6; cx < MAPW; cx++) crowdCell(cx, cy, (cx * 3 + cy * 5) % 6);
  // stand edge: a black step line under the crowd
  for (let fx = 0; fx < FW; fx++) set(fx, 39, 0);

  // ---- advert boards: top rows 5-6 (y 40-55), bottom rows 46-47 (y 368-383)
  const BOARDS = ['GOLAZO 64', 'DEV MACHINE', 'POLYTRICITY', 'C64 FOREVER'];
  function board(y0, fx0, fx1, phase) {
    for (let y = y0; y < y0 + 16; y++) for (let fx = fx0; fx < fx1; fx++) set(fx, y, 3);
    for (let fx = fx0; fx < fx1; fx++) { set(fx, y0 + 15, 0); }
    // one board per 32 fat px (8 chars); text centred, letters every 4 fat px
    for (let b = fx0, n = phase; b + 32 <= fx1; b += 32, n++) {
      const txt = BOARDS[n % BOARDS.length];
      const sep = b;                       // dark seam between boards
      for (let y = y0; y < y0 + 15; y++) set(sep, y, 0);
      const len = Math.min(txt.length, 7);
      const s = txt.slice(0, 7).padEnd(7, ' ');
      for (let i = 0; i < 7; i++) {
        const g = MINI[s[i]] || MINI[' '];
        const cx = b + 2 + i * 4;          // text starts 2 fat px into the board
        for (let gy = 0; gy < 5; gy++) for (let gx = 0; gx < 3; gx++)
          if (g[gy][gx] === '1') set(cx + gx, y0 + 5 + gy, 0);
      }
      void len;
    }
  }
  // boards only exist for whole 8-char boards, so text never straddles a
  // seam; split long names over two boards: use 7-letter slices
  BOARDS.splice(0, BOARDS.length, 'GOLAZO', 'C64', 'DEV', 'MACHINE');
  board(40, 24, FW - 24, 0);
  board(368, 24, FW - 24, 3);

  // ---- markings (colour 3)
  const hline = (x0, x1, y) => { for (let fx = hx(x0); fx <= hx(x1); fx++) set(fx, y, 3); };
  const vline = (x, y0, y1) => { for (let y = y0; y <= y1; y++) set(hx(x), y, 3); };
  const { TOP, BOT, LEFT, RIGHT, MIDX, MIDY } = G;
  hline(LEFT, RIGHT, TOP); hline(LEFT, RIGHT, BOT);
  vline(LEFT, TOP, BOT); vline(RIGHT - 1, TOP, BOT); vline(MIDX, TOP, BOT);
  const ellipse = (cx, cy, rx, ry, keep) => {
    for (let i = 0; i < 2000; i++) {
      const t = i / 2000 * Math.PI * 2;
      const x = cx + Math.cos(t) * rx, y = Math.round(cy + Math.sin(t) * ry);
      if (!keep || keep(x, y)) set(hx(x), y, 3);
    }
  };
  ellipse(MIDX + 1, MIDY, G.CIRC_RX, G.CIRC_RY);
  // centre spot + penalty spots (2 fat px x 2 rows)
  const spot = (x, y) => { set(hx(x), y, 3); set(hx(x) + 1, y, 3); set(hx(x), y + 1, 3); set(hx(x) + 1, y + 1, 3); };
  spot(MIDX - 1, MIDY - 1);
  for (const side of [0, 1]) {
    const gx = side ? RIGHT - 1 : LEFT, dir = side ? -1 : 1;
    const bx = gx + dir * G.BOX_D, sx = gx + dir * G.SIX_D;
    hline(Math.min(gx, bx), Math.max(gx, bx), G.BOX_T); hline(Math.min(gx, bx), Math.max(gx, bx), G.BOX_B);
    vline(bx, G.BOX_T, G.BOX_B);
    hline(Math.min(gx, sx), Math.max(gx, sx), G.SIX_T); hline(Math.min(gx, sx), Math.max(gx, sx), G.SIX_B);
    vline(sx, G.SIX_T, G.SIX_B);
    spot(gx + dir * G.SPOT_D - 1, MIDY - 1);
    ellipse(gx + dir * G.SPOT_D, MIDY, G.CIRC_RX, G.CIRC_RY, x => dir > 0 ? x > bx + 1 : x < bx - 1);
    // corner arcs
    for (const cyy of [TOP, BOT]) ellipse(gx, cyy, 10, 5, (x, y) => (dir > 0 ? x >= gx : x <= gx) && (cyy === TOP ? y >= TOP : y <= BOT));
  }

  // ---- goals: front frame on the goal line, net behind, roof above
  for (const side of [0, 1]) {
    const gx = side ? RIGHT - 1 : LEFT, dir = side ? 1 : -1;     // net goes outwards
    const top = G.POST_T - G.BAR_H, bot = G.POST_B;
    const back = gx + dir * G.NET;
    // net: black with a white mesh, from the goal line back to the back frame,
    // between the crossbar and the ground (seen from slightly above)
    for (let y = top; y <= bot; y++) {
      for (let x = Math.min(gx, back); x <= Math.max(gx, back); x += 2) {
        const fx = hx(x);
        const mesh = ((y - top) % 4 === 0) || ((fx - hx(Math.min(gx, back))) % 2 === 0);
        set(fx, y, mesh ? 3 : 0);
      }
    }
    // roof edge + back frame + ground line of the net
    for (let x = Math.min(gx, back); x <= Math.max(gx, back); x += 2) { set(hx(x), top, 3); set(hx(x), bot, 3); }
    // front frame: two fat px thick posts and crossbar, with a black outline
    for (let y = top - 1; y <= bot + 1; y++) for (const k of [-1, 0, 1, 2]) {
      const fx = hx(gx) + (side ? -k + 1 : k - 1);
      set(fx, y, (k === 0 || k === 1) && y >= top && y <= bot ? 3 : 0);
    }
    // shadow of the frame on the grass (inside the pitch)
    for (let y = G.POST_T; y <= bot; y++) { const fx = hx(gx) - dir * 2; if (get(fx, y) !== 3) set(fx, y, 0); }
  }

  // ---- cut into chars
  return cv;
}

export function cutCells(cv) {
  const cells = [];
  for (let cy = 0; cy < MAPH; cy++) for (let cx = 0; cx < MAPW; cx++) {
    const bytes = [];
    for (let yy = 0; yy < 8; yy++) {
      let b = 0;
      for (let xx = 0; xx < 4; xx++) b = (b << 2) | cv[(cy * 8 + yy) * FW + cx * 4 + xx];
      bytes.push(b);
    }
    cells.push(bytes);
  }
  return cells;
}

// Title / logo glyphs and HUD extras (MC blocks + hires bars).
export const EXTRA = {
  SOLID: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF],          // MC %11 block (colour RAM colour)
  HALF_T: [0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0],
  HALF_B: [0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF],
  TRI_TL: [0x03, 0x0F, 0x3F, 0x3F, 0xFF, 0xFF, 0xFF, 0xFF],        // rounded corners
  TRI_TR: [0xC0, 0xF0, 0xFC, 0xFC, 0xFF, 0xFF, 0xFF, 0xFF],
  TRI_BL: [0xFF, 0xFF, 0xFF, 0xFF, 0x3F, 0x3F, 0x0F, 0x03],
  TRI_BR: [0xFF, 0xFF, 0xFF, 0xFF, 0xFC, 0xFC, 0xF0, 0xC0],
  BAR: [0xFF, 0x00, 0xAA, 0x00, 0, 0, 0, 0],                       // HUD row 1 rule (rows 0-3 only)
  BALLC: [0x3C, 0x7E, 0xDB, 0xFF, 0xE7, 0x7E, 0x3C, 0x00],          // hires ball icon
};

// space ! ' - . / A-Z 0-9 :
export const FONT_KEEP = [32, 33, 39, 45, 46, 47, 58, ...Array.from({ length: 26 }, (_, i) => i + 1), ...Array.from({ length: 10 }, (_, i) => 48 + i)];

// screen code for a text character
export function scr(ch) {
  if (ch >= 'A' && ch <= 'Z') return ch.charCodeAt(0) - 64;
  const c = ch.charCodeAt(0);
  if (c >= 32 && c < 64) {
    if (!FONT_KEEP.includes(c)) throw new Error('glyph not kept in charset: ' + ch);
    return c;
  }
  throw new Error('no screen code for ' + ch);
}

export function buildCharset() {
  const font = romFont();
  const cv = buildPitch();
  const cells = cutCells(cv);
  // Only the screen codes the HUD / title text uses keep their ROM glyph;
  // every other slot is free for pitch tiles.
  const charset = new Array(256).fill(null);
  for (const i of FONT_KEEP) charset[i] = font[i];
  let next = 0;
  const alloc = bytes => {
    while (next < 256 && charset[next] !== null) next++;
    if (next >= 256) throw new Error('charset full');
    charset[next] = bytes;
    return next;
  };
  const extraIdx = {};
  for (const [k, v] of Object.entries(EXTRA)) extraIdx[k] = alloc(v);
  const lut = new Map();
  const map = new Uint8Array(MAPW * MAPH);
  cells.forEach((bytes, i) => {
    const key = bytes.join(',');
    let idx = lut.get(key);
    if (idx === undefined) { idx = alloc(bytes); lut.set(key, idx); }
    map[i] = idx;
  });
  const used = charset.filter(c => c !== null).length;
  for (let i = 0; i < 256; i++) if (charset[i] === null) charset[i] = [0, 0, 0, 0, 0, 0, 0, 0];
  return { charset, map, extraIdx, uniquePitch: lut.size, used, canvas: cv };
}
