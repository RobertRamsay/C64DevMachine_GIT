// SHMUP H art: charset, stamps + world map, sprites and the title bitmap.
// Everything here is generated so the template can be rebuilt, but once it is
// in the project JSON the editor's own tools own it (TILES, WORLD, ACTORS,
// FRONT_END) and nothing reads these back.
import fs from 'fs';

// The font, sounds, music, HUD and editor metadata both SHMUP generators
// start from (taken from the original hand-made SHMUP V).
const BASE_JSON = new URL('../shmup_common/base_assets.json', import.meta.url);
export const BASE = JSON.parse(fs.readFileSync(BASE_JSON, 'utf8'));
export const V_ASSETS = Object.fromEntries(BASE.assets.map(a => [a.name, a]));
export const blobOf = a => Buffer.from(a.blob.slice(4), 'base64');

// Seeded PRNG so a rebuild gives the same map and title stars.
export function rng(seed) {
  let s = seed >>> 0;
  return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; };
}

// ------------------------------------------------------------ charset
// Multicolour chars are 4 pixels wide: '.' = 00 background (space),
// 's' = 01 $D022 (speckle / stars), 'b' = 10 $D023 (rock), 'g' = 11 the
// colour RAM nibble (the METASCROLL FIXED colour, green).
const MC = { '.': 0, s: 1, b: 2, g: 3 };
const mcChar = rows => rows.map(r => [...r].reduce((v, c) => (v << 2) | MC[c], 0));
const hiChar = rows => rows.map(r => [...r].reduce((v, c) => (v << 1) | (c === '#' ? 1 : 0), 0));
const vflip = rows => [...rows].reverse();
const hflip = rows => rows.map(r => [...r].reverse().join(''));

const FILL = ['bbbb', 'bsbb', 'bbbb', 'bbbs', 'bbbb', 'sbbb', 'bbbb', 'bbsb'];
const FILL2 = ['bbbb', 'bbbb', 'bbsb', 'bbbb', 'sbbb', 'bbbb', 'bbbb', 'bsbb'];
const FLOOR_TOP = ['g.g.', 'gggg', 'gbgg', 'bbgb', 'bbbb', 'bsbb', 'bbbb', 'bbbs'];
const UP = ['...g', '...g', '..gb', '..gb', '.gbb', '.gbs', 'gbbb', 'gbbb'];
const DN = hflip(UP);
const HATCH_L = ['....', '...s', '..ss', '.sgg', '.sgs', 'ssgg', 'gggg', 'bbbb'];
const HATCH_R = hflip(HATCH_L);
const RUBBLE = ['....', '....', '....', '....', 's..s', '.s.b', 'bsbb', 'bbbb'];

// char number -> [name, rows, multicolour?, tag]
export const CH = {
  BLANK: 0, HUD_LINE: 96, STAR1: 97, STAR2: 98, STAR3: 99, FILL: 100, FILL2: 101,
  FLOOR_TOP: 102, CEIL_BOT: 103, UP: 104, DN: 105, CUP: 106, CDN: 107,
  HATCH_L: 108, HATCH_R: 109, CHATCH_L: 110, CHATCH_R: 111, RUBBLE: 112, CRUBBLE: 113,
};
const CHARS = [
  [CH.HUD_LINE, hiChar(['........', '........', '........', '########', '........', '#.#.#.#.', '........', '........'])],
  [CH.STAR1, mcChar(['....', '....', '..s.', '....', '....', '....', '....', '....'])],
  [CH.STAR2, mcChar(['....', 's...', '....', '....', '....', '....', '..s.', '....'])],
  [CH.STAR3, mcChar(['....', '....', '....', '.s..', '....', '....', '....', '...b'])],
  [CH.FILL, mcChar(FILL)],
  [CH.FILL2, mcChar(FILL2)],
  [CH.FLOOR_TOP, mcChar(FLOOR_TOP)],
  [CH.CEIL_BOT, mcChar(vflip(FLOOR_TOP))],
  [CH.UP, mcChar(UP)],
  [CH.DN, mcChar(DN)],
  [CH.CUP, mcChar(vflip(DN))],
  [CH.CDN, mcChar(vflip(UP))],
  [CH.HATCH_L, mcChar(HATCH_L)],
  [CH.HATCH_R, mcChar(HATCH_R)],
  [CH.CHATCH_L, mcChar(vflip(HATCH_L))],
  [CH.CHATCH_R, mcChar(vflip(HATCH_R))],
  [CH.RUBBLE, mcChar(RUBBLE)],
  [CH.CRUBBLE, mcChar(vflip(RUBBLE))],
];
export const TAG_WALL = 1, TAG_TARGET = 2;

export function buildCharset() {
  const v = blobOf(V_ASSETS.TILES);
  const out = Buffer.alloc(2048);
  v.copy(out, 0, 0, 96 * 8);            // blank + the SHMUP V font (ASCII order)
  for (const [n, rows] of CHARS) Buffer.from(rows).copy(out, n * 8);
  const tags = Array(256).fill(0);
  for (const n of [CH.FILL, CH.FILL2, CH.FLOOR_TOP, CH.CEIL_BOT, CH.UP, CH.DN, CH.CUP, CH.CDN, CH.RUBBLE, CH.CRUBBLE]) tags[n] = TAG_WALL;
  for (const n of [CH.HATCH_L, CH.HATCH_R, CH.CHATCH_L, CH.CHATCH_R]) tags[n] = TAG_TARGET;
  return { bytes: out, tags };
}

// ------------------------------------------------------------ stamps + map
// 2x2 stamps: [top-left, top-right, bottom-left, bottom-right]
export const STAMPS = [
  ['EMPTY', [0, 0, 0, 0]],
  ['STARS A', [CH.STAR1, 0, 0, 0]],
  ['STARS B', [0, 0, 0, CH.STAR2]],
  ['STARS C', [0, CH.STAR3, 0, 0]],
  ['ROCK', [CH.FILL, CH.FILL2, CH.FILL2, CH.FILL]],
  ['FLOOR', [CH.FLOOR_TOP, CH.FLOOR_TOP, CH.FILL, CH.FILL2]],
  ['CEILING', [CH.FILL2, CH.FILL, CH.CEIL_BOT, CH.CEIL_BOT]],
  ['FLOOR UP', [0, CH.UP, CH.UP, CH.FILL]],
  ['FLOOR DOWN', [CH.DN, 0, CH.FILL2, CH.DN]],
  ['CEILING DOWN', [CH.CDN, CH.FILL, 0, CH.CDN]],
  ['CEILING UP', [CH.FILL2, CH.CUP, CH.CUP, 0]],
  ['FLOOR HATCH', [CH.HATCH_L, CH.HATCH_R, CH.FILL, CH.FILL2]],
  ['CEILING HATCH', [CH.FILL2, CH.FILL, CH.CHATCH_L, CH.CHATCH_R]],
];
const S = Object.fromEntries(STAMPS.map(([n], i) => [n, i]));

export const MAP_ROWS = 11;        // 11 stamps = 22 chars = screen rows 3-24
export const LOOP_STAMPS = 96;     // the level proper; 20 more repeat its start
export const MAP_COLS = LOOP_STAMPS + 20;
export const LOOP_COL = LOOP_STAMPS * 2;   // camera column that wraps to 0

// Floor and ceiling heights per column, in stamps. Plateaus are at least two
// stamps long so a column is never both the foot and the top of a slope.
function heights(r, lo, hi, quietStart, quietEnd, start) {
  const h = [];
  let cur = start, run = 0;
  for (let i = 0; i < LOOP_STAMPS; i++) {
    const quiet = i < quietStart || i >= LOOP_STAMPS - quietEnd;
    let next = cur;
    if (quiet) next = start;
    // high ground tends to come back down, low ground to rise
    else if (run >= 2 && r() < 0.42) next = Math.max(lo, Math.min(hi, cur + (r() < 0.2 + 0.6 * (cur - lo) / (hi - lo) ? -1 : 1)));
    if (Math.abs(next - cur) > 1) next = cur + Math.sign(next - cur);
    if (next !== cur && run < 2) next = cur;
    run = next === cur ? run + 1 : 1;
    h.push(next);
    cur = next;
  }
  return h;
}

export function buildMap() {
  const r = rng(0x5EED64);
  const floor = heights(r, 1, 4, 6, 6, 1);
  const ceil = heights(r, 0, 3, 10, 8, 0).map((c, i) => Math.min(c, 6 - floor[i]));
  // re-check the ceiling plateau rule after the clamp
  for (let i = 1; i < LOOP_STAMPS; i++) if (Math.abs(ceil[i] - ceil[i - 1]) > 1) ceil[i] = ceil[i - 1] + Math.sign(ceil[i] - ceil[i - 1]);
  const grid = Array.from({ length: MAP_ROWS }, () => Array(LOOP_STAMPS).fill(S.EMPTY));
  for (let x = 0; x < LOOP_STAMPS; x++) {
    const f = floor[x], c = ceil[x];
    const fPrev = floor[(x + LOOP_STAMPS - 1) % LOOP_STAMPS], fNext = floor[(x + 1) % LOOP_STAMPS];
    const cPrev = ceil[(x + LOOP_STAMPS - 1) % LOOP_STAMPS], cNext = ceil[(x + 1) % LOOP_STAMPS];
    for (let y = 0; y < MAP_ROWS; y++) {
      const roll = r();
      grid[y][x] = roll < 0.07 ? S['STARS A'] : roll < 0.14 ? S['STARS B'] : roll < 0.2 ? S['STARS C'] : S.EMPTY;
    }
    // floor
    for (let y = MAP_ROWS - f; y < MAP_ROWS; y++) grid[y][x] = S.ROCK;
    let top = S.FLOOR;
    if (f > fPrev) top = S['FLOOR UP'];
    else if (fNext < f) top = S['FLOOR DOWN'];
    else if (fPrev === f && fNext === f && r() < 0.22) top = S['FLOOR HATCH'];
    grid[MAP_ROWS - f][x] = top;
    // ceiling
    if (c > 0) {
      for (let y = 0; y < c; y++) grid[y][x] = S.ROCK;
      let bot = S.CEILING;
      if (c > cPrev) bot = S['CEILING DOWN'];
      else if (cNext < c) bot = S['CEILING UP'];
      else if (cPrev === c && cNext === c && r() < 0.2) bot = S['CEILING HATCH'];
      grid[c - 1][x] = bot;
    } else if (cNext === 1) {
      // nothing: the next column starts the ceiling with its own CEILING DOWN
    }
  }
  // the loop: the last 20 stamps repeat the first 20
  const full = grid.map(row => [...row, ...row.slice(0, MAP_COLS - LOOP_STAMPS)]);
  return { grid: full.flat(), floor, ceil };
}

// ------------------------------------------------------------ spawn layer
// Entity types for the WORLD map's SPAWN layer (frames are ACTORS frames,
// the runtime adds 1 every 8 frames, so each type uses a pair).
// move: 0 STRAIGHT 1 SINE 2 CHASE 3 ZIGZAG 4 DIVE 5 WALKER 6 TURRET
export const SPAWN_TYPES = [
  { name: 'FAN', frame: 10, col: 14, hp: 1, pts: 1, speed: 2, move: 1, value: 2, drop: 0 },
  { name: 'RED FAN', frame: 10, col: 2, hp: 1, pts: 2, speed: 2, move: 1, value: 2, drop: 1 },
  { name: 'JET', frame: 12, col: 10, hp: 1, pts: 1, speed: 3, move: 0, value: 0, drop: 0 },
  { name: 'RING', frame: 14, col: 7, hp: 2, pts: 2, speed: 1, move: 2, value: 1, drop: 0 },
  { name: 'DART', frame: 16, col: 13, hp: 1, pts: 1, speed: 2, move: 3, value: 2, drop: 0 },
  { name: 'DIVER', frame: 12, col: 4, hp: 1, pts: 2, speed: 2, move: 4, value: 3, drop: 0 },
  { name: 'WALKER', frame: 24, col: 15, hp: 2, pts: 3, speed: 0, move: 5, value: 1, drop: 0 },
];

// Placements [col, row, type] in WORLD map chars (row 0 = screen row 3).
// Three enemy sprites means three alive at once, so groups are spaced out.
// The first and last 40 columns stay empty: that is where the map loops.
export function buildSpawns(map) {
  const out = [];
  const free = c => {                       // usable rows at map column c
    const s = Math.floor(c / 2) % map.floor.length;
    const top = map.ceil[s] * 2 + 1;
    const bottom = 22 - map.floor[s] * 2 - 4;   // 3-char sprite clear of the floor
    return [top, Math.max(top, bottom)];
  };
  const mid = c => { const [a, b] = free(c); return Math.round((a + b) / 2); };
  const groups = ['fans', 'jets', 'walker', 'rings', 'fans_red', 'darts', 'diver', 'walker', 'fans', 'jets', 'darts', 'fans_red'];
  let c = 44;
  for (const g of groups) {
    if (c > 176) break;
    const [top, bottom] = free(c);
    if (g === 'fans' || g === 'fans_red') {
      const y = mid(c);
      for (let i = 0; i < 3; i++) out.push([c + i * 3, y, g === 'fans_red' && i === 2 ? 1 : 0]);
    } else if (g === 'jets') {
      out.push([c, top + 1, 2]); out.push([c + 4, bottom - 1, 2]);
    } else if (g === 'rings') {
      out.push([c, mid(c), 3]); out.push([c + 8, top + 1, 3]);
    } else if (g === 'darts') {
      out.push([c, mid(c) - 2, 4]); out.push([c + 5, mid(c) + 2, 4]);
    } else if (g === 'diver') {
      out.push([c, top + 1, 5]); out.push([c + 6, bottom - 1, 5]);
    } else if (g === 'walker') {
      // on the first flat stretch of floor from here
      let x = c;
      while (x < c + 10 && !(map.floor[Math.floor(x / 2)] === map.floor[Math.floor(x / 2) + 1] && map.floor[Math.floor(x / 2) - 1] === map.floor[Math.floor(x / 2)])) x += 2;
      out.push([x & ~1, 22 - map.floor[Math.floor(x / 2)] * 2 - 3, 6]);
    }
    c += 12;
  }
  return out;
}

// ------------------------------------------------------------ sprites
// 24x21, '#' = set. Hires, one colour each (set by DrawActors).
const blank = () => Array.from({ length: 21 }, () => Array(24).fill(0));
const fromArt = art => { const g = blank(); art.forEach((row, y) => [...row].forEach((c, x) => { if (c === '#') g[y][x] = 1; })); return g; };
const disc = (g, cx, cy, r, v = 1) => { for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) if ((x - cx) ** 2 + (y - cy) ** 2 <= r * r) g[y][x] = v; return g; };
const ring = (g, cx, cy, r0, r1) => { for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) { const d = (x - cx) ** 2 + (y - cy) ** 2; if (d <= r1 * r1 && d >= r0 * r0) g[y][x] = 1; } return g; };
const line = (g, x0, y0, x1, y1, t = 1) => {
  const n = Math.max(Math.abs(x1 - x0), Math.abs(y1 - y0));
  for (let i = 0; i <= n; i++) {
    const x = Math.round(x0 + (x1 - x0) * i / n), y = Math.round(y0 + (y1 - y0) * i / n);
    for (let dy = 0; dy < t; dy++) for (let dx = 0; dx < t; dx++) if (y + dy < 21 && x + dx < 24) g[y + dy][x + dx] = 1;
  }
  return g;
};

const SHIP = [
  '........................',
  '........................',
  '........................',
  '....###.................',
  '.....####...............',
  '......##########........',
  '.......###########......',
  '........#######.........',
  '...##..##########.......',
  '...#####################',
  '...#####################',
  '...##..##########.......',
  '........#######.........',
  '.......###########......',
  '......##########........',
  '.....####...............',
  '....###.................',
];
const flame = (g, long) => { for (const y of [9, 10]) { g[y][2] = 1; g[y][1] = long ? 1 : 0; g[y][0] = long ? 0 : 0; } if (long) { g[9][0] = 1; } return g; };
function shipTilt(dir) {
  // dir -1 = climbing (top wing tucked in), +1 = diving
  const g = fromArt(SHIP);
  const out = blank();
  for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) {
    if (!g[y][x]) continue;
    const top = y < 9, bottom = y > 10;
    let ny = y;
    if (dir < 0 && top) ny = Math.min(8, y + 1);
    if (dir < 0 && bottom) ny = Math.min(20, y + 1);
    if (dir > 0 && bottom) ny = Math.max(11, y - 1);
    if (dir > 0 && top) ny = Math.max(0, y - 1);
    out[ny][x] = 1;
  }
  return flame(out, false);
}
const fan = plus => {
  const g = disc(blank(), 12, 10, 3);
  const arms = plus ? [[0, -7], [0, 7], [-8, 0], [8, 0]] : [[-6, -5], [6, -5], [-6, 5], [6, 5]];
  for (const [dx, dy] of arms) line(g, 12, 10, 12 + dx, 10 + dy, 2);
  g[10][12] = 0; g[10][13] = 0;
  return g;
};
const JET = [
  '........................',
  '........................',
  '........................',
  '........................',
  '........................',
  '................###.....',
  '.............######.....',
  '..........#########.....',
  '......##############....',
  '..####################..',
  '##########..##########..',
  '..####################..',
  '......##############....',
  '..........#########.....',
  '.............######.....',
  '................###.....',
];
const jet = flick => { const g = fromArt(JET); if (flick) { g[9][23] = 1; g[11][23] = 1; g[10][22] = 1; g[10][23] = 1; } return g; };
const diamond = phase => {
  const g = blank();
  for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) {
    const d = Math.abs(x - 12) / 1.1 + Math.abs(y - 10);
    if (d <= 8 && d >= (phase ? 3 : 5)) g[y][x] = 1;
  }
  disc(g, 12, 10, phase ? 1 : 2);
  return g;
};
const capsule = shine => {
  const g = blank();
  for (let y = 6; y <= 14; y++) for (let x = 5; x <= 19; x++) {
    const ex = x < 9 ? (x - 9) / 4 : x > 15 ? (x - 15) / 4 : 0, ey = (y - 10) / 4.5;
    if (ex * ex + ey * ey <= 1) g[y][x] = 1;
  }
  // hollow window with a moving highlight
  for (let x = 8; x <= 16; x++) { g[9][x] = 0; g[11][x] = 0; }
  g[10][8] = 0; g[10][16] = 0;
  for (let x = 9; x <= 15; x++) g[10][x] = 1;
  g[8][shine ? 14 : 9] = 0; g[8][shine ? 15 : 10] = 0;
  return g;
};
const boom = n => {
  const g = blank();
  const r = rng(77 + n);
  if (n === 0) disc(g, 12, 10, 3);
  if (n === 1) { disc(g, 12, 10, 5); for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; line(g, 12, 10, Math.round(12 + Math.cos(a) * 8), Math.round(10 + Math.sin(a) * 8)); } disc(g, 12, 10, 2, 0); }
  if (n === 2) { ring(g, 12, 10, 6, 8); for (let i = 0; i < 20; i++) { const x = Math.floor(r() * 24), y = Math.floor(r() * 21); g[y][x] = 0; } }
  if (n === 3) for (let i = 0; i < 14; i++) { const a = r() * Math.PI * 2, d = 6 + r() * 4; const x = Math.round(12 + Math.cos(a) * d), y = Math.round(10 + Math.sin(a) * d); if (x >= 0 && x < 24 && y >= 0 && y < 21) g[y][x] = 1; }
  return g;
};

// a two-legged ground walker (Nemesis "ducker"), bottom of the sprite on the ground
const walker = step => {
  const g = blank();
  disc(g, 12, 9, 5);
  disc(g, 12, 9, 2, 0);
  g[9][9] = 1; g[9][10] = 1;               // the eye looks left, at the player
  const legs = step ? [[9, 6], [15, 18]] : [[7, 9], [17, 15]];
  for (const [top, foot] of legs) line(g, top + 2, 13, foot, 20);
  return g;
};

// [name, grid, colour shown in the editor] - order = sprite pointer $A0 + n
export function buildSprites() {
  const list = [
    ['SHIP', flame(fromArt(SHIP), false), 1],
    ['SHIP FLAME', flame(fromArt(SHIP), true), 1],
    ['SHIP CLIMB', shipTilt(-1), 1],
    ['SHIP DIVE', shipTilt(1), 1],
    ['SHOT', line(blank(), 7, 9, 16, 9, 2), 7],
    ['LASER', line(blank(), 0, 9, 23, 9, 2), 3],
    ['DOUBLE', line(blank(), 7, 14, 16, 5, 2), 7],
    ['MISSILE', fromArt(['', '', '', '', '', '', '', '', '.........##', '.........####', '..........#####', '...........####', '............##']), 10],
    ['OPTION A', (() => { const g = disc(blank(), 12, 10, 5); disc(g, 12, 10, 2, 0); g[8][10] = 0; return g; })(), 8],
    ['OPTION B', (() => { const g = disc(blank(), 12, 10, 5); disc(g, 12, 10, 3, 0); g[10][12] = 1; return g; })(), 8],
    ['FAN A', fan(false), 14],
    ['FAN B', fan(true), 14],
    ['JET A', jet(false), 10],
    ['JET B', jet(true), 10],
    ['RING A', ring(blank(), 12, 10, 5, 8), 7],
    ['RING B', ring(blank(), 12, 10, 4, 6), 7],
    ['DART A', diamond(0), 13],
    ['DART B', diamond(1), 13],
    ['CAPSULE A', capsule(false), 2],
    ['CAPSULE B', capsule(true), 2],
    ['BOOM 1', boom(0), 7],
    ['BOOM 2', boom(1), 7],
    ['BOOM 3', boom(2), 7],
    ['BOOM 4', boom(3), 7],
    ['WALKER A', walker(0), 15],
    ['WALKER B', walker(1), 15],
  ];
  const bytes = Buffer.alloc(list.length * 64);
  list.forEach(([, g], i) => {
    for (let y = 0; y < 21; y++) for (let b = 0; b < 3; b++) {
      let v = 0;
      for (let k = 0; k < 8; k++) v = (v << 1) | (g[y][b * 8 + k] ? 1 : 0);
      bytes[i * 64 + y * 3 + b] = v;
    }
  });
  return { list, bytes };
}

// ------------------------------------------------------------ title bitmap
// Hires 320x200: 8000 bitmap bytes + 1000 screen bytes (fg << 4 | bg),
// stored with the $4000 load address in front like SHMUP V's FRONT_END.
export function buildTitle(sprites) {
  const font = blobOf(V_ASSETS.TILES);
  const W = 320, H = 200;
  const px = new Uint8Array(W * H);          // 1 = ink
  const cellFg = new Uint8Array(1000).fill(1);
  const set = (x, y) => { if (x >= 0 && x < W && y >= 0 && y < H) px[y * W + x] = 1; };
  const glyph = (ch, x, y, s) => {
    const code = ch.charCodeAt(0);
    for (let r = 0; r < 8; r++) { const b = font[code * 8 + r]; for (let c = 0; c < 8; c++) if (b & (0x80 >> c)) for (let dy = 0; dy < s; dy++) for (let dx = 0; dx < s; dx++) set(x + c * s + dx, y + r * s + dy); }
  };
  const text = (str, y, s, col) => {
    const w = str.length * 8 * s, x0 = Math.round((W - w) / 2 / 8) * 8;
    [...str].forEach((ch, i) => glyph(ch, x0 + i * 8 * s, y, s));
    paint(x0, y, w, 8 * s, col);
  };
  const paint = (x, y, w, h, col) => {
    for (let cy = Math.floor(y / 8); cy <= Math.floor((y + h - 1) / 8); cy++)
      for (let cx = Math.floor(x / 8); cx <= Math.floor((x + w - 1) / 8); cx++)
        if (cy >= 0 && cy < 25 && cx >= 0 && cx < 40) cellFg[cy * 40 + cx] = col;
  };
  // stars
  const r = rng(1984);
  for (let i = 0; i < 110; i++) { const x = Math.floor(r() * W), y = Math.floor(r() * 150); set(x, y); }
  for (let cy = 0; cy < 25; cy++) for (let cx = 0; cx < 40; cx++) cellFg[cy * 40 + cx] = r() < 0.5 ? 15 : 12;
  // frame
  for (let x = 4; x < W - 4; x++) { set(x, 4); set(x, H - 5); }
  for (let y = 4; y < H - 4; y++) { set(4, y); set(W - 5, y); }
  // mountains along the bottom
  let h = 18;
  for (let x = 5; x < W - 5; x++) {
    if (x % 6 === 0) h = Math.max(6, Math.min(34, h + Math.round((r() - 0.5) * 10)));
    for (let y = H - 5 - h; y < H - 5; y++) if (y === H - 5 - h || (x + y) % 3 === 0 || y > H - 5 - h + 6) set(x, y);
  }
  paint(0, 152, W, 48, 9);
  for (let cx = 0; cx < 40; cx++) cellFg[24 * 40 + cx] = 9;
  // the ship, three times size, with a laser
  const ship = sprites.list[1][1];
  for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) if (ship[y][x]) for (let d = 0; d < 9; d++) set(36 + x * 3 + (d % 3), 88 + y * 3 + Math.floor(d / 3));
  paint(32, 96, 80, 48, 1);
  for (let x = 112; x < 300; x += (x < 200 ? 1 : 3)) { set(x, 115); set(x, 116); }
  paint(112, 112, 188, 8, 3);
  // words
  text('NOVA FORCE', 22, 3, 3);
  text('HORIZONTAL SHMUP TEMPLATE', 56, 1, 14);
  text('JOYSTICK PORT 2', 132, 1, 15);
  text('SPACE ACTIVATES THE LIT POWER', 144, 1, 15);
  text('PRESS FIRE TO START', 166, 1, 7);
  const bmp = Buffer.alloc(8000);
  for (let cy = 0; cy < 25; cy++) for (let cx = 0; cx < 40; cx++) for (let rr = 0; rr < 8; rr++) {
    let v = 0;
    for (let c = 0; c < 8; c++) v = (v << 1) | px[(cy * 8 + rr) * W + cx * 8 + c];
    bmp[(cy * 40 + cx) * 8 + rr] = v;
  }
  const scr = Buffer.from(cellFg.map(f => (f << 4) | 0));
  return { file: Buffer.concat([Buffer.from([0x00, 0x40]), bmp, scr]), px, cellFg };
}
