// SHMUP V art: charset, stamps + world map, sprites and the title bitmap.
// The vertical twin of tools/shmup_h_gen/art.mjs. Everything is generated so
// the template can be rebuilt, but once it is in the project JSON the
// editor's own tools own it (TILES, WORLD, ACTORS, FRONT_END).
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
// a wall's inner edge: rock on the left, a grass lip on the right
const EDGE_L = ['bbbg', 'bsbg', 'bbgg', 'bbbg', 'sbbg', 'bbbg', 'bbgg', 'bsbg'];
const EDGE_R = hflip(EDGE_L);
// diagonals: rock in the bottom-right half, grass along the slope
const UP = ['...g', '...g', '..gb', '..gb', '.gbb', '.gbs', 'gbbb', 'gbbb'];
const DN = hflip(UP);                                  // rock bottom-left
// a bunker dome on rock (left half), and what is left of it
const HATCH_L = ['....', '...s', '..ss', '.sgg', '.sgs', 'ssgg', 'gggg', 'bbbb'];
const HATCH_R = hflip(HATCH_L);
const RUBBLE = ['....', '....', '....', '....', 's..s', '.s.b', 'bsbb', 'bbbb'];
// the foot of a rock island, under its bunker
const ISLE_L = ['bbbb', 'bsbb', 'gbbb', '.gbs', '..gb', '...g', '....', '....'];
const ISLE_R = hflip(ISLE_L);

// char numbers (0-95 keep the font)
export const CH = {
  BLANK: 0, HUD_LINE: 96, STAR1: 97, STAR2: 98, STAR3: 99, FILL: 100, FILL2: 101,
  EDGE_L: 102, EDGE_R: 103, UP: 104, DN: 105, CUP: 106, CDN: 107,
  HATCH_L: 108, HATCH_R: 109, RUBBLE: 110, ISLE_L: 111, ISLE_R: 112,
  SHOT0: 120,     // 120-135: the enemy shot, 4 x 4 positions in a cell
};
// The enemy shot: a 2 x 4 multicolour-pixel pellet (4 x 4 hires pixels).
// Char SHOT0 + down * 4 + across. Across 0-3 = 0, 1, 2, 2 multicolour
// pixels in, down 0-3 = rows 0, 2, 4, 4: the pellet must stay inside its
// cell, so the last step each way stays put.
const shotChar = n => {
  const x = Math.min(n & 3, 2), y = Math.min(n >> 2, 2) * 2;
  return Array.from({ length: 8 }, (_, r) => (r >= y && r < y + 4) ? '....'.slice(0, x) + 'ss' + '....'.slice(0, 2 - x) : '....');
};
const CHARS = [
  [CH.HUD_LINE, hiChar(['........', '........', '........', '########', '........', '#.#.#.#.', '........', '........'])],
  [CH.STAR1, mcChar(['....', '....', '..s.', '....', '....', '....', '....', '....'])],
  [CH.STAR2, mcChar(['....', 's...', '....', '....', '....', '....', '..s.', '....'])],
  [CH.STAR3, mcChar(['....', '....', '....', '.s..', '....', '....', '....', '...b'])],
  [CH.FILL, mcChar(FILL)],
  [CH.FILL2, mcChar(FILL2)],
  [CH.EDGE_L, mcChar(EDGE_L)],
  [CH.EDGE_R, mcChar(EDGE_R)],
  [CH.UP, mcChar(UP)],                 // rock bottom-right
  [CH.DN, mcChar(DN)],                 // rock bottom-left
  [CH.CUP, mcChar(vflip(DN))],         // rock top-left
  [CH.CDN, mcChar(vflip(UP))],         // rock top-right
  [CH.HATCH_L, mcChar(HATCH_L)],
  [CH.HATCH_R, mcChar(HATCH_R)],
  [CH.RUBBLE, mcChar(RUBBLE)],
  [CH.ISLE_L, mcChar(ISLE_L)],
  [CH.ISLE_R, mcChar(ISLE_R)],
  ...Array.from({ length: 16 }, (_, n) => [CH.SHOT0 + n, mcChar(shotChar(n))]),
];
export const TAG_WALL = 1, TAG_TARGET = 2;

export function buildCharset() {
  const v = blobOf(V_ASSETS.TILES);
  const out = Buffer.alloc(2048);
  v.copy(out, 0, 0, 96 * 8);            // blank + the font (ASCII order)
  for (const [n, rows] of CHARS) Buffer.from(rows).copy(out, n * 8);
  const tags = Array(256).fill(0);
  for (const n of [CH.FILL, CH.FILL2, CH.EDGE_L, CH.EDGE_R, CH.UP, CH.DN, CH.CUP, CH.CDN, CH.RUBBLE, CH.ISLE_L, CH.ISLE_R]) tags[n] = TAG_WALL;
  for (const n of [CH.HATCH_L, CH.HATCH_R]) tags[n] = TAG_TARGET;
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
  ['LEFT EDGE', [CH.FILL, CH.EDGE_L, CH.FILL2, CH.EDGE_L]],
  ['RIGHT EDGE', [CH.EDGE_R, CH.FILL, CH.EDGE_R, CH.FILL2]],
  ['LEFT NARROWS UP', [CH.DN, 0, CH.FILL, CH.DN]],        // wall thinner in the row above
  ['LEFT WIDENS UP', [CH.FILL, CH.CUP, CH.CUP, 0]],       // wall thinner in the row below
  ['RIGHT NARROWS UP', [0, CH.UP, CH.UP, CH.FILL]],
  ['RIGHT WIDENS UP', [CH.CDN, CH.FILL, 0, CH.CDN]],
  ['WALL BUNKER', [CH.HATCH_L, CH.HATCH_R, CH.FILL2, CH.FILL]],
  ['ISLAND BUNKER', [CH.HATCH_L, CH.HATCH_R, CH.ISLE_L, CH.ISLE_R]],
];
const S = Object.fromEntries(STAMPS.map(([n], i) => [n, i]));

export const MAP_COLS = 20;           // 20 stamps = 40 chars, the whole screen width
export const LOOP_STAMPS = 64;        // the level proper, played bottom to top
export const REPEAT_STAMPS = 12;      // the first 12 rows again under it: the loop seam
export const MAP_ROWS = LOOP_STAMPS + REPEAT_STAMPS;
export const LOOP_ROW = LOOP_STAMPS * 2;   // char row the camera starts on and jumps back to

// Wall widths per stamp row, top to bottom. Every width holds for at least two
// rows, so a row is never both the top and the foot of a slope; the first and
// last rows of the loop are quiet so the seam matches.
function widths(r, lo, hi, quiet, start) {
  const w = [];
  let cur = start, run = 0;
  for (let i = 0; i < LOOP_STAMPS; i++) {
    const still = i < quiet || i >= LOOP_STAMPS - quiet;
    let next = cur;
    if (still) next = start;
    else if (run >= 2 && r() < 0.4) next = Math.max(lo, Math.min(hi, cur + (r() < 0.2 + 0.6 * (cur - lo) / (hi - lo) ? -1 : 1)));
    if (Math.abs(next - cur) > 1) next = cur + Math.sign(next - cur);
    if (next !== cur && run < 2) next = cur;
    run = next === cur ? run + 1 : 1;
    w.push(next);
    cur = next;
  }
  return w;
}

export function buildMap() {
  const r = rng(0x5EEDF0);
  const left = widths(r, 1, 6, 6, 2);
  const right = widths(r, 1, 6, 6, 2).map((w, i) => Math.min(w, 20 - 9 - left[i]));   // corridor 9+ stamps
  for (let i = 1; i < LOOP_STAMPS; i++) if (Math.abs(right[i] - right[i - 1]) > 1) right[i] = right[i - 1] + Math.sign(right[i] - right[i - 1]);
  const grid = Array.from({ length: LOOP_STAMPS }, () => Array(MAP_COLS).fill(S.EMPTY));
  const at = (a, i) => a[(i + LOOP_STAMPS) % LOOP_STAMPS];
  const islands = [];
  for (let y = 0; y < LOOP_STAMPS; y++) {
    const wl = left[y], wr = right[y];
    for (let x = 0; x < MAP_COLS; x++) {
      const roll = r();
      grid[y][x] = roll < 0.07 ? S['STARS A'] : roll < 0.14 ? S['STARS B'] : roll < 0.2 ? S['STARS C'] : S.EMPTY;
    }
    for (let x = 0; x < wl; x++) grid[y][x] = S.ROCK;
    for (let x = MAP_COLS - wr; x < MAP_COLS; x++) grid[y][x] = S.ROCK;
    // left wall edge
    const la = at(left, y - 1), lb = at(left, y + 1);
    grid[y][wl - 1] = la < wl ? S['LEFT NARROWS UP'] : lb < wl ? S['LEFT WIDENS UP'] : S['LEFT EDGE'];
    // right wall edge
    const ra = at(right, y - 1), rb = at(right, y + 1);
    grid[y][MAP_COLS - wr] = ra < wr ? S['RIGHT NARROWS UP'] : rb < wr ? S['RIGHT WIDENS UP'] : S['RIGHT EDGE'];
    // bunkers on a steady stretch of wall, one stamp in from the edge
    const quiet = y >= 8 && y < LOOP_STAMPS - 8;
    if (quiet && wl >= 3 && la === wl && lb === wl && r() < 0.18) grid[y][wl - 2] = S['WALL BUNKER'];
    if (quiet && wr >= 3 && ra === wr && rb === wr && r() < 0.18) grid[y][MAP_COLS - wr + 1] = S['WALL BUNKER'];
    // now and then a rock island with a bunker in the corridor
    if (quiet && y % 9 === 4) {
      const lo = wl + 2, hi = MAP_COLS - wr - 3;
      if (hi >= lo) { const x = lo + Math.floor(r() * (hi - lo + 1)); grid[y][x] = S['ISLAND BUNKER']; islands.push([x, y]); }
    }
  }
  // the loop seam: the first REPEAT_STAMPS rows again at the bottom
  const full = [...grid, ...grid.slice(0, REPEAT_STAMPS)];
  return { grid: full.flat(), left, right, islands };
}

// ------------------------------------------------------------ spawn layer
// Entity types for the WORLD map's SPAWN layer (frames are ACTORS frames,
// the runtime adds 1 every 8 frames, so each type uses a pair).
// move: 0 STRAIGHT 1 SINE 2 CHASE 3 ZIGZAG 4 DIVE 5 WALKER 6 TURRET
export const SPAWN_TYPES = [
  { name: 'FAN', frame: 10, col: 14, hp: 1, pts: 1, speed: 1, move: 1, value: 2, drop: 0 },
  { name: 'RED FAN', frame: 10, col: 2, hp: 1, pts: 2, speed: 1, move: 1, value: 2, drop: 1 },
  { name: 'JET', frame: 12, col: 10, hp: 1, pts: 1, speed: 3, move: 0, value: 0, drop: 0 },
  { name: 'RING', frame: 14, col: 7, hp: 2, pts: 2, speed: 1, move: 2, value: 1, drop: 0 },
  { name: 'DART', frame: 16, col: 13, hp: 1, pts: 1, speed: 2, move: 3, value: 2, drop: 0 },
  { name: 'DIVER', frame: 12, col: 4, hp: 1, pts: 2, speed: 2, move: 4, value: 3, drop: 0 },
  { name: 'TANK', frame: 24, col: 15, hp: 2, pts: 3, speed: 0, move: 5, value: 1, drop: 0 },
];

// Placements [col, row, type] in WORLD map chars (row 0 = the top of the map).
// The camera climbs, so a group at a lower row comes first. Three enemy
// sprites means three alive at once, so groups are 12 rows apart. The
// repeated rows at the bottom stay empty: that is where a game starts.
export function buildSpawns(map) {
  const out = [];
  const corridor = row => {                 // usable columns at a map char row
    const s = Math.floor(row / 2) % LOOP_STAMPS;
    return [map.left[s] * 2 + 1, 40 - map.right[s] * 2 - 4];
  };
  const groups = ['fans', 'jets', 'tank', 'rings', 'fans_red', 'darts', 'diver', 'tank', 'fans', 'jets', 'darts'];
  let row = LOOP_ROW - 14;
  for (const g of groups) {
    if (row < 4) break;
    const [l, rr] = corridor(row);
    const mid = Math.round((l + rr) / 2);
    if (g === 'fans' || g === 'fans_red') {
      for (let i = 0; i < 3; i++) out.push([mid - 6 + i * 6, row, g === 'fans_red' && i === 2 ? 1 : 0]);
    } else if (g === 'jets') {
      out.push([l + 2, row, 2]); out.push([rr - 2, row - 4, 2]);
    } else if (g === 'rings') {
      out.push([mid, row, 3]); out.push([l + 3, row - 6, 3]);
    } else if (g === 'darts') {
      out.push([mid - 4, row, 4]); out.push([mid + 4, row - 5, 4]);
    } else if (g === 'diver') {
      out.push([l + 2, row, 5]); out.push([rr - 2, row - 6, 5]);
    } else if (g === 'tank') {
      out.push([mid, row, 6]);
    }
    row -= 12;
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

// the ship points up; the nose is at (11-12, 0)
const SHIP = [
  '...........##...........',
  '...........##...........',
  '..........####..........',
  '..........####..........',
  '.........##..##.........',
  '.........######.........',
  '....#....######....#....',
  '....#...########...#....',
  '...###..########..###...',
  '...###.##########.###...',
  '..####################..',
  '.######################.',
  '########################',
  '###.################.###',
  '##...##############...##',
  '#.....############.....#',
  '.......##########.......',
  '........###..###........',
  '........##....##........',
];
const flame = (g, long) => {
  for (const x of [9, 14]) { g[19][x] = 1; g[19][x + (x < 12 ? 1 : -1)] = 1; if (long) g[20][x] = 1; }
  return g;
};
// bank: the wing on one side tucks in (dir -1 = moving left, +1 = right)
function shipBank(dir) {
  const g = fromArt(SHIP);
  const out = blank();
  for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) {
    if (!g[y][x]) continue;
    let nx = x;
    if (dir < 0 && x < 12) nx = Math.round(12 - (12 - x) * 0.65);
    if (dir > 0 && x > 11) nx = Math.round(11 + (x - 11) * 0.65);
    out[y][nx] = 1;
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
// a jet flying down the screen: tail fins at the top, nose at the bottom
const jet = flick => {
  const hw = [5, 5, 2, 2, 2, 4, 7, 9, 11, 11, 6, 2.5, 2.5, 2.5, 2.5, 2, 1.5, 1, 0.5];
  const g = blank();
  hw.forEach((w, y) => { for (let x = 0; x < 24; x++) if (Math.abs(x - 11.5) <= w) g[y + 1][x] = 1; });
  g[1][11] = 0; g[1][12] = 0;                      // between the fins
  if (flick) { g[0][10] = 1; g[0][13] = 1; }       // exhaust flicker
  for (const x of [8, 15]) g[9][x] = 0;            // wing detail
  return g;
};
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
// a ground tank seen from above, gun pointing down at the player; the
// tread marks move between the two frames
const tank = step => {
  const g = blank();
  for (let y = 3; y <= 17; y++) for (let x = 5; x <= 18; x++) {
    const tread = x <= 7 || x >= 16;
    if (!tread || (y + step) % 3 !== 0) g[y][x] = 1;
  }
  for (let y = 4; y <= 16; y++) { g[y][8] = 0; g[y][15] = 0; }
  disc(g, 12, 9, 3, 0);
  ring(g, 12, 9, 2, 3);
  for (let y = 12; y <= 20; y++) { g[y][11] = 1; g[y][12] = 1; }
  return g;
};

// [name, grid, colour shown in the editor] - order = sprite pointer $A0 + n
export function buildSprites() {
  const list = [
    ['SHIP', flame(fromArt(SHIP), false), 1],
    ['SHIP FLAME', flame(fromArt(SHIP), true), 1],
    ['SHIP BANK LEFT', shipBank(-1), 1],
    ['SHIP BANK RIGHT', shipBank(1), 1],
    ['SHOT', line(blank(), 11, 3, 11, 13, 2), 7],
    ['LASER', line(blank(), 11, 0, 11, 20, 2), 3],
    ['DOUBLE', line(blank(), 16, 15, 7, 6, 2), 7],
    ['MISSILE', fromArt(['', '', '', '', '', '', '...........##', '..........####', '..........####', '..........####', '.........######', '..........#..#', '..........#..#']), 10],
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
    ['TANK A', tank(0), 15],
    ['TANK B', tank(1), 15],
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
// stored with the $4000 load address in front.
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
  const paint = (x, y, w, h, col) => {
    for (let cy = Math.floor(y / 8); cy <= Math.floor((y + h - 1) / 8); cy++)
      for (let cx = Math.floor(x / 8); cx <= Math.floor((x + w - 1) / 8); cx++)
        if (cy >= 0 && cy < 25 && cx >= 0 && cx < 40) cellFg[cy * 40 + cx] = col;
  };
  // centred in the area right of the ship (x 96-316)
  const text = (str, y, s, col) => {
    const w = str.length * 8 * s, x0 = Math.round((96 + (220 - w) / 2) / 8) * 8;
    [...str].forEach((ch, i) => glyph(ch, x0 + i * 8 * s, y, s));
    paint(x0, y, w, 8 * s, col);
  };
  // stars
  const r = rng(1985);
  for (let i = 0; i < 120; i++) set(Math.floor(r() * W), Math.floor(r() * H));
  for (let cy = 0; cy < 25; cy++) for (let cx = 0; cx < 40; cx++) cellFg[cy * 40 + cx] = r() < 0.5 ? 15 : 12;
  // frame
  for (let x = 4; x < W - 4; x++) { set(x, 4); set(x, H - 5); }
  for (let y = 4; y < H - 4; y++) { set(4, y); set(W - 5, y); }
  // canyon walls down the left edge
  let w = 10;
  for (let y = 5; y < H - 5; y++) {
    if (y % 6 === 0) w = Math.max(6, Math.min(18, w + Math.round((r() - 0.5) * 6)));
    for (let x = 5; x < 5 + w; x++) if (x === 4 + w || (x + y) % 3 === 0) set(x, y);
  }
  paint(0, 0, 24, H, 9);
  // the ship, three times size, climbing with a laser above it
  const ship = sprites.list[1][1];
  const sx = 24, sy = 128;
  for (let y = 0; y < 21; y++) for (let x = 0; x < 24; x++) if (ship[y][x]) for (let d = 0; d < 9; d++) set(sx + x * 3 + (d % 3), sy + y * 3 + Math.floor(d / 3));
  paint(sx, sy, 72, 64, 1);
  for (let y = 12; y < sy - 2; y += (y > 60 ? 1 : 3)) { set(sx + 34, y); set(sx + 35, y); set(sx + 36, y); }
  paint(sx + 32, 8, 8, sy - 8, 3);
  // words
  text('SKY LANCE', 22, 3, 3);
  text('VERTICAL SHMUP TEMPLATE', 56, 1, 14);
  text('JOYSTICK PORT 2', 120, 1, 15);
  text('SPACE ACTIVATES', 136, 1, 15);
  text('THE LIT POWER', 146, 1, 15);
  text('PRESS FIRE TO START', 170, 1, 7);
  const bmp = Buffer.alloc(8000);
  for (let cy = 0; cy < 25; cy++) for (let cx = 0; cx < 40; cx++) for (let rr = 0; rr < 8; rr++) {
    let v = 0;
    for (let c = 0; c < 8; c++) v = (v << 1) | px[(cy * 8 + rr) * W + cx * 8 + c];
    bmp[(cy * 40 + cx) * 8 + rr] = v;
  }
  const scr = Buffer.from(cellFg.map(f => (f << 4) | 0));
  return { file: Buffer.concat([Buffer.from([0x00, 0x40]), bmp, scr]), px, cellFg };
}
