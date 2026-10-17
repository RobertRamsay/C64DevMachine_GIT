// ALIEN BREED 64 art: the station charset (font + autotiled tiles), the
// title charset with the logo, and every sprite. All generated, so the
// template can be rebuilt; once in the project JSON the editor's own char
// and sprite editors own it.
import fs from 'fs';

const BASE = JSON.parse(fs.readFileSync(new URL('../shmup_common/base_assets.json', import.meta.url), 'utf8'));
const BASE_TILES = Buffer.from(BASE.assets.find(a => a.name === 'TILES').blob.slice(4), 'base64');
export const BASE_ASSETS = Object.fromEntries(BASE.assets.map(a => [a.name, a]));

// ------------------------------------------------------------ helpers
// Multicolour chars are 4 pixels wide: '.' = 00 $D021 (black), 'd' = 01
// $D022 (dark grey), 'l' = 10 $D023 (light grey), 'b' = 11 colour RAM (the
// deck colour: blue on deck 1, red on deck 2).
const MC = { '.': 0, d: 1, l: 2, b: 3 };
export const mcChar = rows => rows.map(r => [...r].reduce((v, c) => (v << 2) | MC[c], 0));
export const hiChar = rows => rows.map(r => [...r].reduce((v, c) => (v << 1) | (c === '#' ? 1 : 0), 0));
const grid = s => s.trim().split('\n').map(r => r.trim());
// split an 8 x 16 multicolour tile (rows of 8 pixels) into its 4 chars TL TR BL BR
const quads = rows => [0, 1, 2, 3].map(q => {
  const ox = (q & 1) * 4, oy = (q >> 1) * 8;
  return rows.slice(oy, oy + 8).map(r => r.slice(ox, ox + 4));
});
const setPx = (rows, x, y, c) => { rows[y] = rows[y].slice(0, x) + c + rows[y].slice(x + 1); };

// ------------------------------------------------------------ char numbers
// 0-95: font (ASCII order, hires on the HUD), 1-9: energy bar
// 96-255: station tiles
export const CH = {};
let next = 96;
const alloc = (name, n = 1) => { CH[name] = next; next += n; return CH[name]; };
alloc('VOID');
alloc('FLOOR_A', 16);   // quadrant q (0-3) + 4 * shadow (0 none, 1 north, 2 west, 3 both)
alloc('FLOOR_B', 16);
alloc('HAZARD', 4);
alloc('WALL', 16);      // + open-side mask N1 E2 S4 W8
alloc('DOOR_H', 4); alloc('DOOR_V', 4);
alloc('KEY', 4); alloc('AMMO', 4); alloc('MEDKIT', 4); alloc('CREDIT', 4);
alloc('TERM', 4); alloc('VENT', 4); alloc('CORE', 4); alloc('DEAD', 4);
alloc('LIFT', 16);      // 4 x 4 chars
if (next > 255) throw new Error('charset full: ' + next);
export const CHAR_COUNT = next;

// ------------------------------------------------------------ tile art
const FLOOR_A = grid(`
dddddddd
d.....d.
d.d.d.d.
d.....d.
d.d.d.d.
d.....d.
d.d.d.d.
d.....d.
dddddddd
d.....d.
d.d.d.d.
d.....d.
d.d.d.d.
d.....d.
d.d.d.d.
d.....d.`);
const FLOOR_B = grid(`
ddddddd.
d.d.d.d.
dd.d.dd.
d.d.d.d.
dd.d.dd.
d.d.d.d.
ddddddd.
........
ddddddd.
d.d.l.d.
dd.d.dd.
d.d.d.d.
dd.d.dd.
d.d.d.d.
ddddddd.
........`);
const HAZARD = grid(`
bb..bb..
b..bb..b
..bb..bb
.bb..bb.
bb..bb..
b..bb..b
..bb..bb
.bb..bb.
bb..bb..
b..bb..b
..bb..bb
.bb..bb.
bb..bb..
b..bb..b
..bb..bb
........`);
// a floor char with a shadow cast by a wall to the north and/or the west
function shadowed(rows, n, w) {
  const out = rows.map(r => r);
  if (n) for (let y = 0; y < 3; y++) out[y] = [...out[y]].map((c, x) => (y < 2 || (x + y) % 2) ? '.' : c).join('');
  if (w) for (let y = 0; y < 8; y++) out[y] = '.' + out[y].slice(1);
  return out;
}
// wall: blue plating, lit from the top left. mask bit set = that side is open
function wallChar(mask) {
  const rows = ['blbb', 'bbbb', 'bbdb', 'bbbb', 'blbb', 'bbbb', 'bbdb', 'bbbb'];
  if (mask & 1) { rows[0] = 'llll'; rows[1] = 'lbbb'; }
  if (mask & 8) for (let y = 0; y < 8; y++) setPx(rows, 0, y, 'l');
  if (mask & 2) for (let y = 0; y < 8; y++) setPx(rows, 3, y, 'd');
  if (mask & 4) { rows[4] = 'dddd'; rows[5] = 'dbdb'; rows[6] = 'dddd'; rows[7] = '....'; }
  if ((mask & 1) && (mask & 8)) setPx(rows, 0, 0, 'l');
  return rows;
}
const DOOR_H = grid(`
dddddddd
.lbllbll
.lblblbl
.llblblb
.lbllbll
.lblblbl
.llblblb
dddddddd
dddddddd
.lbllbll
.lblblbl
.llblblb
.lbllbll
.lblblbl
.llblblb
........`);
const DOOR_V = grid(`
d.....d.
dllllld.
dbbbbbd.
dlllbld.
dlblbld.
dlbllld.
dbbbbbd.
dllllld.
dllllld.
dbbbbbd.
dlllbld.
dlblbld.
dlbllld.
dbbbbbd.
dllllld.
d.....d.`);
const KEY = grid(`
........
..llll..
.ll..ll.
.l....l.
.ll..ll.
..llll..
...ll...
...ll...
...llb..
...ll...
...llbb.
...ll...
...llb..
...ll...
........
........`);
const AMMO = grid(`
........
.dddddd.
.dllld..
.dbbbdd.
.dlllld.
.dbbbbd.
.dlllld.
.dbbbbd.
.dlllld.
.dbbbbd.
.dlllld.
.dbbbbd.
.dlllld.
.dddddd.
........
........`);
const MEDKIT = grid(`
........
.llllll.
.llbbll.
.llbbll.
.llbbll.
.bbbbbb.
.bbbbbb.
.bbbbbb.
.llbbll.
.llbbll.
.llbbll.
.llllll.
.dddddd.
........
........
........`);
const CREDIT = grid(`
........
...ll...
..llll..
.ll..ll.
.l.bb.l.
.l.b..l.
.l.b..l.
.l.b..l.
.l.bb.l.
.ll..ll.
..llll..
...ll...
...dd...
........
........
........`);
const TERM = grid(`
dddddddd
dllllll.
dl....l.
dlb.b.l.
dl....l.
dlbbb.l.
dl....l.
dlb.bbl.
dl....l.
dllllll.
d......d
dbdbdbd.
dddddddd
dbdbdbd.
dddddddd
........`);
const VENT = grid(`
bbbbbbbb
b......d
b.dddd.d
b......d
b.dddd.d
b......d
b.dddd.d
b......d
b.dddd.d
b......d
b.dddd.d
b......d
b.dddd.d
b......d
bddddddd
........`);
const CORE = grid(`
.bbbbbb.
bbllllbb
bllddllb
blddddlb
bldlldlb
bldlldlb
blddddlb
bllddllb
bblllldb
.bbbbbb.
.dbbbbd.
.d.ll.d.
.d.ll.d.
.dbbbbd.
.dddddd.
........`);
const DEAD = grid(`
........
..d..d..
.d.dd...
..d..d..
.d....d.
...dd...
.d.d..d.
...d.d..
..d...d.
.d.dd...
...d..d.
..d..d..
.d.d.d..
........
.dddddd.
........`);
// the lift: 16 x 32 pixels (4 x 4 chars)
const LIFT = grid(`
dddddddddddddddd
dlllllllllllllld
dl............ld
dl.bbbbbbbbbb.ld
dl.b........b.ld
dl.b...ll...b.ld
dl.b..llll..b.ld
dl.b.llllll.b.ld
dl.b...ll...b.ld
dl.b...ll...b.ld
dl.b........b.ld
dl.b...ll...b.ld
dl.b...ll...b.ld
dl.b.llllll.b.ld
dl.b..llll..b.ld
dl.b...ll...b.ld
dl.b........b.ld
dl.b.d.d.d..b.ld
dl.b........b.ld
dl.bbbbbbbbbb.ld
dl............ld
dl.d.d.d.d.d..ld
dl............ld
dl.d.d.d.d.d..ld
dl............ld
dl.d.d.d.d.d..ld
dl............ld
dl.d.d.d.d.d..ld
dl............ld
dlllllllllllllld
dddddddddddddddd
................`);

// ------------------------------------------------------------ font
// HUD energy bar: char 1 = empty slot, 2-9 = 1-8 pixels filled (hires)
function barChar(n) {
  return hiChar(Array.from({ length: 8 }, (_, y) => (y === 0 || y === 7) ? '........'
    : (y === 1 || y === 6) ? '########' : '#'.repeat(n).padEnd(8, '.')));
}

export function buildCharset() {
  const out = Buffer.alloc(2048);
  BASE_TILES.copy(out, 0, 0, 96 * 8);                 // the Dev Machine template font (ASCII order)
  for (let n = 0; n <= 8; n++) barChar(n).forEach((b, i) => { out[(1 + n) * 8 + i] = b; });
  const put = (ch, rows) => mcChar(rows).forEach((b, i) => { out[ch * 8 + i] = b; });
  put(CH.VOID, Array(8).fill('....'));
  for (const [base, art] of [[CH.FLOOR_A, FLOOR_A], [CH.FLOOR_B, FLOOR_B]]) {
    const q = quads(art);
    for (let s = 0; s < 4; s++) for (let i = 0; i < 4; i++) put(base + i + 4 * s, shadowed(q[i], s & 1, s & 2));
  }
  quads(HAZARD).forEach((r, i) => put(CH.HAZARD + i, r));
  for (let m = 0; m < 16; m++) put(CH.WALL + m, wallChar(m));
  for (const [name, art] of [['DOOR_H', DOOR_H], ['DOOR_V', DOOR_V], ['KEY', KEY], ['AMMO', AMMO], ['MEDKIT', MEDKIT],
    ['CREDIT', CREDIT], ['TERM', TERM], ['VENT', VENT], ['CORE', CORE], ['DEAD', DEAD]])
    quads(art).forEach((r, i) => put(CH[name] + i, r));
  for (let cy = 0; cy < 4; cy++) for (let cx = 0; cx < 4; cx++)
    put(CH.LIFT + cy * 4 + cx, LIFT.slice(cy * 8, cy * 8 + 8).map(r => r.slice(cx * 4, cx * 4 + 4)));
  return out;
}

// char -> type (bit 7 = solid). Font chars never appear in the map.
export function buildCharTypes(C) {
  const t = Array(256).fill(C.T_WALL);
  const set = (base, n, type) => { for (let i = 0; i < n; i++) t[base + i] = type; };
  set(CH.FLOOR_A, 16, C.T_FLOOR); set(CH.FLOOR_B, 16, C.T_FLOOR); set(CH.HAZARD, 4, C.T_FLOOR);
  set(CH.DOOR_H, 8, C.T_DOOR); set(CH.KEY, 4, C.T_KEY); set(CH.AMMO, 4, C.T_AMMO); set(CH.MEDKIT, 4, C.T_MEDKIT);
  set(CH.CREDIT, 4, C.T_CREDIT); set(CH.TERM, 4, C.T_TERM); set(CH.VENT, 4, C.T_VENT); set(CH.CORE, 4, C.T_CORE);
  set(CH.DEAD, 4, C.T_DEAD); set(CH.LIFT, 16, C.T_EXIT);
  return t;
}

// ------------------------------------------------------------ sprites
// Drawn as shapes on a 24 x 21 grid and sampled per multicolour pixel
// (2 hires pixels wide). Colours: 0 transparent, 1 $D025 black outline,
// 2 sprite colour, 3 $D026 light grey.
function drawSprite(shapes, outline = true) {
  const px = Array.from({ length: 21 }, () => Array(12).fill(0));
  for (let j = 0; j < 21; j++) for (let i = 0; i < 12; i++) {
    const x = 2 * i + 1, y = j + 0.5;
    for (const s of shapes) if (s.hit(x, y)) px[j][i] = s.c;
  }
  if (outline) {
    const o = px.map(r => [...r]);
    for (let j = 0; j < 21; j++) for (let i = 0; i < 12; i++) {
      if (px[j][i]) continue;
      if ([[0, 1], [0, -1], [1, 0], [-1, 0]].some(([dj, di]) => px[j + dj] && px[j + dj][i + di] > 1)) o[j][i] = 1;
    }
    return o;
  }
  return px;
}
const ell = (cx, cy, rx, ry, ang, c) => ({ c, hit: (x, y) => {
  const dx = x - cx, dy = y - cy, ca = Math.cos(ang), sa = Math.sin(ang);
  const u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
  return (u * u) / (rx * rx) + (v * v) / (ry * ry) <= 1;
} });
const seg = (x0, y0, x1, y1, w, c) => ({ c, hit: (x, y) => {
  const vx = x1 - x0, vy = y1 - y0, l2 = vx * vx + vy * vy;
  let t = ((x - x0) * vx + (y - y0) * vy) / l2; t = Math.max(0, Math.min(1, t));
  const dx = x - (x0 + t * vx), dy = y - (y0 + t * vy);
  return dx * dx + dy * dy <= w * w;
} });
const packMc = px => { const b = []; for (const r of px) { for (let k = 0; k < 3; k++) { let v = 0; for (let i = 0; i < 4; i++) v = (v << 2) | r[k * 4 + i]; b.push(v); } } b.push(0); return b; };
const packHi = px => { const b = []; for (const r of px) { for (let k = 0; k < 3; k++) { let v = 0; for (let i = 0; i < 8; i++) v = (v << 1) | (r[k * 8 + i] ? 1 : 0); b.push(v); } } b.push(0); return b; };

// direction d: 0 up, 1 up-right ... 7 up-left; screen y grows down
const dirVec = d => { const a = d * Math.PI / 4; return [Math.sin(a), -Math.cos(a)]; };
function marine(d, phase) {
  const [fx, fy] = dirVec(d), [qx, qy] = [-fy, fx];   // q = to the marine's right
  const cx = 12, cy = 10.5, ang = Math.atan2(fy, fx);
  const leg = (side) => ell(cx + qx * 3.2 * side + fx * 2.6 * phase * side, cy + qy * 3.2 * side + fy * 2.6 * phase * side, 2.6, 2.2, ang, 1);
  return drawSprite([
    leg(1), leg(-1),
    ell(cx - fx * 3.2, cy - fy * 3.2, 2.2, 4, ang, 1),                                       // backpack
    ell(cx, cy, 4.2, 6.2, ang, 2),                                                          // shoulders
    // armour shading: a black dither over the rear half darkens the green to a mid tone
    { c: 1, hit: (x, y) => ell(cx, cy, 4.2, 6.2, ang, 0).hit(x, y) && ((x - cx) * fx + (y - cy) * fy) < -0.6
      && (Math.floor(x / 2) + Math.floor(y)) % 2 === 0 },
    seg(cx + qx * 2.8, cy + qy * 2.8, cx + qx * 2.8 + fx * 9.5, cy + qy * 2.8 + fy * 9.5, 1.5, 3),   // rifle
    ell(cx + fx * 0.6, cy + fy * 0.6, 2.9, 2.9, 0, 3),                                      // helmet
    ell(cx + fx * 1.3, cy + fy * 1.3, 1.4, 1.4, 0, 2),                                      // visor
  ]);
}
function alien(d, phase) {
  const [fx, fy] = dirVec(d), [qx, qy] = [-fy, fx];
  const cx = 12, cy = 10.5, ang = Math.atan2(fy, fx);
  const shapes = [];
  for (const k of [-1, 0, 1]) for (const side of [1, -1]) {      // six legs
    const sw = (k === 0 ? -phase : phase) * 1.6;
    const bx = cx + fx * (k * 2.6), by = cy + fy * (k * 2.6);
    shapes.push(seg(bx, by, bx + qx * 7.5 * side + fx * (k * 2 + sw), by + qy * 7.5 * side + fy * (k * 2 + sw), 0.9, 1));
  }
  shapes.push(ell(cx - fx * 3, cy - fy * 3, 3.2, 4.4, ang, 2));   // abdomen
  shapes.push(ell(cx + fx * 1.5, cy + fy * 1.5, 2.6, 3.4, ang, 2));
  shapes.push(ell(cx + fx * 5.5, cy + fy * 5.5, 2.6, 2.4, ang, 3));   // the long head
  shapes.push(ell(cx + fx * 7.5, cy + fy * 7.5, 1.4, 1.2, ang, 1));   // jaws
  shapes.push(ell(cx - fx * 3.4 + qx * 1, cy - fy * 3.4 + qy * 1, 0.9, 1.6, ang, 3));   // shell sheen
  return drawSprite(shapes);
}
function boom(n) {
  const r = [3, 6, 8, 9][n];
  const shapes = [];
  for (let k = 0; k < 7; k++) {
    const a = k * 2.1 + n, rr = r * (0.55 + 0.25 * ((k * 37) % 3));
    shapes.push(ell(12 + Math.cos(a) * rr * 0.9, 10.5 + Math.sin(a) * rr * 0.7, 2.4 + n * 0.6, 2 + n * 0.5, 0, n >= 3 ? 1 : 2));
  }
  shapes.push(ell(12, 10.5, Math.max(1, r * 0.55 - n), Math.max(1, r * 0.5 - n), 0, n >= 3 ? 2 : 3));
  return drawSprite(shapes, n < 3);
}
function bullet(d) {
  const [fx, fy] = dirVec(d);
  const px = Array.from({ length: 21 }, () => Array(24).fill(0));
  for (let t = -2.5; t <= 2.5; t += 0.25) for (const w of [-0.5, 0, 0.5]) {
    const x = Math.round(12 + fx * t - fy * w), y = Math.round(10 + fy * t + fx * w);
    if (x >= 0 && x < 24 && y >= 0 && y < 21) px[y][x] = 1;
  }
  return px;
}

// muzzle flash: a hires star burst (shown in the bullet's yellow)
function flash() {
  const px = Array.from({ length: 21 }, () => Array(24).fill(0));
  for (let a = 0; a < 8; a++) {
    const len = a % 2 ? 4 : 6, dx = Math.sin(a * Math.PI / 4), dy = -Math.cos(a * Math.PI / 4);
    for (let t = 0; t <= len; t += 0.5) px[Math.round(10 + dy * t)][Math.round(12 + dx * t)] = 1;
  }
  for (let y = 8; y <= 12; y++) for (let x = 10; x <= 14; x++) if (Math.abs(x - 12) + Math.abs(y - 10) <= 3) px[y][x] = 1;
  return px;
}

// frame order (pointer = SPR_PTR0 + index)
export const SPR = { MARINE: 0, ALIEN: 16, BOOM: 32, BULLET: 36, GOO: 44, FLASH: 48, COUNT: 49 };
export function buildSprites() {
  const frames = [];
  for (let d = 0; d < 8; d++) for (const ph of [1, -1]) frames.push(packMc(marine(d, ph)));
  for (let d = 0; d < 8; d++) for (const ph of [1, -1]) frames.push(packMc(alien(d, ph)));
  for (let n = 0; n < 4; n++) frames.push(packMc(boom(n)));
  for (let d = 0; d < 8; d++) frames.push(packHi(bullet(d)));
  for (let n = 0; n < 4; n++) frames.push(packMc(boom(3 - n)));   // GOO: an alien climbing out of a vent
  frames.push(packHi(flash()));
  const mcs = frames.map((_, i) => ((i >= SPR.BULLET && i < SPR.GOO) || i === SPR.FLASH) ? 0 : 1);
  return { bytes: frames.flat(), count: frames.length, mcs };
}
