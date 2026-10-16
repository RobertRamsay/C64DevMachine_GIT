// ALIEN BREED 64 decks. Each deck is described as rooms and corridors on a
// 64 x 48 tile grid (a tile is 2 x 2 chars), carved out of solid void. Walls
// grow round every floor tile and are autotiled per char; the result is the
// 128 x 96 char map the game expands into $A000 (RLE packed in the PRG).
import { CH } from './art.mjs';

export const TW = 64, TH = 48;

// r: room [x, y, w, h, floor 'A'|'B'], h/v: corridor, 2 tiles wide
//   ['h', x0, x1, y] covers rows y, y+1; ['v', y0, y1, x] covers cols x, x+1
// items: [char, x, y]: P start, T terminal, k key, a ammo, m medkit,
//   c credits, v vent, R reactor core, E lift (2 x 2 tiles, top left),
//   D door (on a corridor: spans its width), = hazard floor
export const DECKS = [
  {
    name: 'DECK 1  INTEX CONTROL',
    goal: 'LOCATE THE LIFT TO DECK 2',
    colour: 6,           // colour RAM: blue plating
    alien: 10, alienHp: 2, spawnRate: 70, alienSpeed: 0xA0,
    carve: [
      ['r', 3, 34, 13, 11, 'B'],      // R0 start
      ['h', 16, 23, 38],              // C1 start -> hub
      ['r', 24, 28, 15, 16, 'A'],     // R1 hub
      ['v', 26, 33, 8],               // C2 start -> store
      ['r', 3, 14, 12, 12, 'B'],      // R3 store
      ['v', 20, 27, 30],              // C3 hub -> lab (door)
      ['r', 22, 6, 18, 14, 'A'],      // R2 lab
      ['h', 39, 47, 34],              // C4 hub -> east hall
      ['r', 48, 26, 13, 18, 'B'],     // R4 east hall
      ['v', 12, 25, 54],              // C5 east hall -> lift room (door)
      ['r', 46, 3, 15, 9, 'B'],       // R5 lift room
      ['h', 40, 45, 9],               // C6 lab -> lift room (door)
    ],
    items: [
      ['P', 8, 39], ['T', 4, 35], ['a', 13, 42], ['c', 14, 35], ['m', 4, 43],
      ['v', 26, 30], ['v', 36, 41], ['v', 37, 29], ['v', 25, 42], ['m', 31, 35], ['a', 34, 31], ['c', 25, 30],
      ['k', 5, 16], ['a', 12, 16], ['c', 6, 23], ['v', 13, 24], ['v', 4, 20],
      ['D', 30, 24],
      ['k', 24, 8], ['c', 37, 8], ['m', 38, 17], ['v', 23, 18], ['v', 38, 7], ['T', 31, 6], ['a', 26, 15],
      ['v', 50, 28], ['v', 58, 41], ['a', 59, 27], ['c', 49, 42], ['k', 59, 42], ['m', 55, 34], ['v', 49, 35],
      ['D', 54, 20], ['D', 43, 9],
      ['E', 52, 5], ['=', 51, 4], ['=', 52, 4], ['=', 53, 4], ['=', 54, 4], ['=', 51, 7], ['=', 52, 7], ['=', 53, 7], ['=', 54, 7],
      ['v', 59, 4], ['c', 47, 10],
    ],
  },
  {
    name: 'DECK 2  REACTOR',
    goal: 'DESTROY THE 4 REACTOR CORES',
    colour: 2,           // colour RAM: red alert plating
    alien: 4, alienHp: 3, spawnRate: 50, alienSpeed: 0xC0,
    carve: [
      ['r', 4, 4, 12, 10, 'B'],       // R0 start
      ['h', 16, 25, 8],               // C1
      ['r', 26, 3, 14, 14, 'A'],      // R1 hall
      ['v', 17, 21, 32],              // C2 hall -> reactor (door)
      ['r', 20, 22, 26, 16, 'A'],     // R2 reactor
      ['h', 10, 19, 29],              // C3 reactor -> west
      ['r', 3, 24, 7, 14, 'B'],       // R3 west store
      ['h', 46, 51, 29],              // C4 reactor -> escape (door)
      ['r', 52, 22, 9, 16, 'B'],      // R4 escape
      ['h', 40, 43, 9],               // C5 hall -> armoury (door)
      ['r', 44, 4, 16, 10, 'B'],      // R5 armoury
    ],
    items: [
      ['P', 9, 8], ['T', 5, 5], ['a', 13, 12], ['m', 14, 5],
      ['v', 27, 4], ['v', 38, 15], ['v', 38, 4], ['k', 37, 10], ['c', 28, 15], ['a', 31, 9],
      ['D', 32, 19],
      ['R', 24, 25], ['R', 41, 25], ['R', 24, 34], ['R', 41, 34],
      ['v', 22, 30], ['v', 44, 31], ['v', 32, 36], ['v', 33, 23], ['m', 32, 29], ['a', 28, 30], ['a', 37, 30],
      ['k', 5, 36], ['m', 7, 25], ['T', 4, 30], ['v', 8, 33],
      ['D', 49, 29],
      ['E', 56, 34], ['v', 53, 23], ['v', 59, 26], ['a', 58, 23],
      ['D', 42, 9],
      ['a', 46, 6], ['a', 48, 6], ['m', 50, 6], ['c', 56, 6], ['c', 58, 11], ['k', 52, 11], ['v', 45, 12],
    ],
  },
];

// ------------------------------------------------------------ carving
function carveDeck(deck) {
  const T = Array.from({ length: TH }, () => Array(TW).fill(' '));
  const floorAt = (x, y, f) => { if (x < 1 || y < 1 || x >= TW - 1 || y >= TH - 1) throw new Error(`${deck.name}: carve outside the map at ${x},${y}`); T[y][x] = f; };
  for (const c of deck.carve) {
    if (c[0] === 'r') { const [, x, y, w, h, f] = c; for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) floorAt(x + i, y + j, f === 'A' ? '.' : ','); }
    else if (c[0] === 'h') { const [, x0, x1, y] = c; for (let x = x0; x <= x1; x++) { if (T[y][x] === ' ') floorAt(x, y, '.'); if (T[y + 1][x] === ' ') floorAt(x, y + 1, '.'); } }
    else if (c[0] === 'v') { const [, y0, y1, x] = c; for (let y = y0; y <= y1; y++) { if (T[y][x] === ' ') floorAt(x, y, '.'); if (T[y][x + 1] === ' ') floorAt(x + 1, y, '.'); } }
  }
  const isFloor = ch => ch === '.' || ch === ',';
  const items = [];
  for (const [ch, x, y] of deck.items) {
    if (ch === 'D') {
      // a door spans the corridor: two tiles across it
      const horiz = isFloor(T[y][x + 1]) && !isFloor(T[y][x - 1]) ? 1 : isFloor(T[y][x - 1]) && !isFloor(T[y][x + 1]) ? -1 : 0;
      const vert = isFloor(T[y + 1][x]) && !isFloor(T[y - 1][x]) ? 1 : isFloor(T[y - 1][x]) && !isFloor(T[y + 1][x]) ? -1 : 0;
      if (!isFloor(T[y][x])) throw new Error(`${deck.name}: door off the floor at ${x},${y}`);
      if (horiz) { T[y][x] = 'H'; T[y][x + horiz] = 'H'; }          // door bar runs across a vertical corridor
      else if (vert) { T[y][x] = 'V'; T[y + vert][x] = 'V'; }
      else throw new Error(`${deck.name}: door at ${x},${y} is not in a 2-wide corridor`);
      continue;
    }
    if (ch === 'E') {
      for (const [i, j] of [[0, 0], [1, 0], [0, 1], [1, 1]]) { if (!isFloor(T[y + j][x + i])) throw new Error(`${deck.name}: lift off the floor`); T[y + j][x + i] = 'E'; }
      continue;
    }
    if (ch === '=') { T[y][x] = '='; continue; }
    if (!isFloor(T[y][x])) throw new Error(`${deck.name}: item ${ch} off the floor at ${x},${y}`);
    if (ch === 'P') { items.push({ ch, x, y }); continue; }
    T[y][x] = ch;
    items.push({ ch, x, y });
  }
  // walls round the floor (8-neighbourhood)
  const open = ch => ch !== ' ' && ch !== '#';
  for (let y = 0; y < TH; y++) for (let x = 0; x < TW; x++) {
    if (T[y][x] !== ' ') continue;
    for (let j = -1; j <= 1; j++) for (let i = -1; i <= 1; i++) {
      const r = T[y + j]; if (r && r[x + i] !== undefined && open(r[x + i]) && r[x + i] !== '#') T[y][x] = '#';
    }
  }
  return { T, items };
}

// ------------------------------------------------------------ chars
function charMap(T) {
  const W = TW * 2, H = TH * 2;
  const m = new Uint8Array(W * H);
  const tileAt = (cx, cy) => (cx < 0 || cy < 0 || cx >= W || cy >= H) ? ' ' : T[cy >> 1][cx >> 1];
  const solid = ch => ch === ' ' || ch === '#';
  const wallish = ch => ch === '#';
  let liftSeen = new Map();
  for (let cy = 0; cy < H; cy++) for (let cx = 0; cx < W; cx++) {
    const t = tileAt(cx, cy), q = (cx & 1) + 2 * (cy & 1);
    let c;
    if (t === ' ') c = CH.VOID;
    else if (t === '#') {
      const o = ch => !solid(ch);
      const mask = (o(tileAt(cx, cy - 1)) ? 1 : 0) | (o(tileAt(cx + 1, cy)) ? 2 : 0) | (o(tileAt(cx, cy + 1)) ? 4 : 0) | (o(tileAt(cx - 1, cy)) ? 8 : 0);
      c = CH.WALL + mask;
    } else if (t === '.' || t === ',' || t === 'P') {
      const n = wallish(tileAt(cx, cy - 1)) || tileAt(cx, cy - 1) === ' ' ? 1 : 0;
      const w = wallish(tileAt(cx - 1, cy)) || tileAt(cx - 1, cy) === ' ' ? 2 : 0;
      c = (t === ',' ? CH.FLOOR_B : CH.FLOOR_A) + q + 4 * (n | w);
    } else if (t === '=') c = CH.HAZARD + q;
    else if (t === 'H') c = CH.DOOR_H + q;
    else if (t === 'V') c = CH.DOOR_V + q;
    else if (t === 'E') {
      // the lift: 4 x 4 chars from its top-left tile
      let ox = cx, oy = cy;
      while (tileAt(ox - 1, cy) === 'E') ox--;
      while (tileAt(cx, oy - 1) === 'E') oy--;
      c = CH.LIFT + (cy - oy) * 4 + (cx - ox);
      liftSeen.set(`${ox},${oy}`, 1);
    } else {
      const base = { k: CH.KEY, a: CH.AMMO, m: CH.MEDKIT, c: CH.CREDIT, T: CH.TERM, v: CH.VENT, R: CH.CORE }[t];
      if (base === undefined) throw new Error('unknown tile ' + t);
      c = base + q;
    }
    m[cy * W + cx] = c;
  }
  return m;
}

// RLE: $FF n c = n copies of c (n 1-255); anything else is itself. Char
// $FF is never used in a map.
export function rle(m) {
  const out = [];
  for (let i = 0; i < m.length;) {
    let n = 1;
    while (i + n < m.length && m[i + n] === m[i] && n < 255) n++;
    if (n >= 4 || m[i] === 0xFF) { out.push(0xFF, n, m[i]); i += n; }
    else { for (let k = 0; k < n; k++) out.push(m[i]); i += n; }
  }
  return out;
}

// ------------------------------------------------------------ checks
// Walk from the start, opening a door only with a key in hand, until the
// lift is reached; cores must be reachable too.
function check(deck, T, items) {
  const start = items.find(i => i.ch === 'P');
  if (!start) throw new Error(deck.name + ': no start');
  const passable = ch => ch !== ' ' && ch !== '#' && ch !== 'T' && ch !== 'R';
  const opened = new Set();
  let doorsOpened = 0;
  for (;;) {
    const seen = new Set([`${start.x},${start.y}`]), q = [[start.x, start.y]], doors = [];
    while (q.length) {
      const [x, y] = q.shift();
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx, ny = y + dy, k = `${nx},${ny}`;
        if (seen.has(k)) continue;
        const ch = T[ny][nx];
        if ((ch === 'H' || ch === 'V') && !opened.has(k)) { doors.push([nx, ny]); continue; }
        if (!passable(ch)) continue;
        seen.add(k); q.push([nx, ny]);
      }
    }
    const keys = items.filter(i => i.ch === 'k' && seen.has(`${i.x},${i.y}`)).length;
    const lift = [...seen].some(k => { const [x, y] = k.split(',').map(Number); return T[y][x] === 'E'; });
    const coresOk = items.filter(i => i.ch === 'R').every(i => [[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => seen.has(`${i.x + dx},${i.y + dy}`)));
    if (lift && coresOk) return { keysFound: keys, doorsNeeded: doorsOpened };
    if (!doors.length || keys <= doorsOpened) throw new Error(`${deck.name}: the lift cannot be reached (keys ${keys}, doors opened ${doorsOpened})`);
    // open one door: both of its tiles
    const [dx, dy] = doors[0];
    for (const [i, j] of [[0, 0], [1, 0], [-1, 0], [0, 1], [0, -1]]) if (T[dy + j][dx + i] === T[dy][dx]) opened.add(`${dx + i},${dy + j}`);
    doorsOpened++;
  }
}

// Every deck is stored as metatile indices (one byte per 2 x 2 char tile,
// RLE packed) plus one shared table of the 2 x 2 char blocks: TL TR BL BR.
export function buildDecks() {
  const meta = new Map();
  const decks = DECKS.map((deck, n) => {
    const { T, items } = carveDeck(deck);
    const res = check(deck, T, items);
    const map = charMap(T);
    const tiles = [];
    for (let ty = 0; ty < TH; ty++) for (let tx = 0; tx < TW; tx++) {
      const o = ty * 2 * 128 + tx * 2;
      const k = [map[o], map[o + 1], map[o + 128], map[o + 129]].join(',');
      if (!meta.has(k)) meta.set(k, meta.size);
      tiles.push(meta.get(k));
    }
    const start = items.find(i => i.ch === 'P');
    const vents = items.filter(i => i.ch === 'v');
    const cores = items.filter(i => i.ch === 'R');
    if (vents.length > 32) throw new Error(deck.name + ': more than 32 vents');
    if (cores.length > 4) throw new Error(deck.name + ': more than 4 cores');
    // deck table: start x,y (pixels, centre of the tile), vents, cores
    const px = start.x * 16 + 8, py = start.y * 16 + 8;
    const table = [px & 255, px >> 8, py & 255, py >> 8, vents.length, cores.length, deck.colour, deck.alien,
      deck.alienHp, deck.spawnRate, deck.alienSpeed, 0, 0, 0, 0, 0];
    for (let i = 0; i < 32; i++) table.push(vents[i] ? vents[i].x * 2 : 0);
    for (let i = 0; i < 32; i++) table.push(vents[i] ? vents[i].y * 2 : 0);
    for (let i = 0; i < 4; i++) table.push(cores[i] ? cores[i].x * 2 : 0);
    for (let i = 0; i < 4; i++) table.push(cores[i] ? cores[i].y * 2 : 0);
    return { n, deck, T, map, tiles, packed: rle(Uint8Array.from(tiles)), table, keysFound: res.keysFound, vents: vents.length, cores: cores.length };
  });
  if (meta.size > 64) throw new Error('too many metatiles: ' + meta.size);
  const metaTable = [[], [], [], []];
  for (const k of meta.keys()) k.split(',').map(Number).forEach((c, i) => metaTable[i].push(c));
  return { decks, metaTable, metaCount: meta.size };
}
// deck table layout (offsets into the per-deck BYTE_DATA table)
export const DT = { PX: 0, PY: 2, NVENT: 4, NCORE: 5, COLOUR: 6, ALIEN: 7, HP: 8, RATE: 9, SPEED: 10, VX: 16, VY: 48, CX: 80, CY: 84, SIZE: 88 };
