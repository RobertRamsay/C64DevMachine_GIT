// BYTE_DATA tables (each becomes a BYTE_DATA asset at a fixed address).
import { CONSTS as C, MEM } from './defs.mjs';
import { scr } from './pitch.mjs';

const lo = v => v & 255, hi = v => (v >> 8) & 255;
const fx88 = f => Math.round(f * 256) & 0xffff;

// 8 directions: 0 R, 1 DR, 2 D, 3 DL, 4 L, 5 UL, 6 U, 7 UR
const DCX = [1, 1, 0, -1, -1, -1, 0, 1];
const DCY = [0, 1, 1, 1, 0, -1, -1, -1];
const YSCALE = 0.62;            // vertical foreshortening of the pitch

export function buildTables(cs) {
  const T = [];                 // [name, bytes]
  const t = (name, bytes) => { bytes.forEach(b => { if (b < 0 || b > 255 || !Number.isInteger(b)) throw new Error(name + ' bad byte ' + b); }); T.push([name, bytes]); };

  t('NOTBIT2', Array.from({ length: 16 }, (_, i) => (i & 1) ? 0 : (255 ^ (1 << (i >> 1)))));
  t('ENMASK', [0, 1, 3, 7, 15, 31, 63, 127, 255]);
  t('BITTAB', [1, 2, 4, 8, 16, 32, 64, 128]);
  t('BITJ', Array.from({ length: 64 }, (_, j) => 1 << (j & 7)));
  // joystick bits (up=1 down=2 left=4 right=8) -> direction
  const jd = Array(16).fill(255);
  jd[8] = 0; jd[10] = 1; jd[2] = 2; jd[6] = 3; jd[4] = 4; jd[5] = 5; jd[1] = 6; jd[9] = 7;
  t('JOYDIR', jd);
  // sprite frame base per facing (stand frame; run = base+1..4)
  t('DIRBASE', [C.F_R_STAND, C.F_R_STAND, C.F_D_STAND, C.F_L_STAND, C.F_L_STAND, C.F_L_STAND, C.F_U_STAND, C.F_R_STAND]);
  t('ISLEFT', [0, 0, 0, 1, 1, 1, 1, 0]);
  t('DIRCX', DCX.map(v => v & 255));
  t('DIRCY', DCY.map(v => v & 255));
  // steer: index (vy+1)*3 + (vx+1)
  t('DIRHV', [5, 6, 7, 4, 255, 0, 3, 2, 1]);
  // velocities: speed index 0 jog, 1 with ball, 2 run, 3 slide, 4 keeper dive
  const SPEEDS0 = [0.80, 1.12, 1.36, 2.30, 1.0];
  const SPEEDS = [...SPEEDS0, ...SPEEDS0.map(v => v * 4)];   // 5-9: x4 (off-screen players move every 4th frame)
  const vxl = [], vxh = [], vyl = [], vyh = [];
  for (const s of SPEEDS) for (let d = 0; d < 8; d++) {
    const diag = DCX[d] && DCY[d] ? 0.74 : 1;
    const vx = fx88(s * DCX[d] * diag), vy = fx88(s * DCY[d] * diag * YSCALE);
    vxl.push(lo(vx)); vxh.push(hi(vx)); vyl.push(lo(vy)); vyh.push(hi(vy));
  }
  t('SPVXL', vxl); t('SPVXH', vxh); t('SPVYL', vyl); t('SPVYH', vyh);
  t('SPVXS', vxh.map(h => h & 0x80 ? 255 : 0)); t('SPVYS', vyh.map(h => h & 0x80 ? 255 : 0));
  // ball offset from the feet when dribbling
  t('DRIBX', [8, 6, 0, -6, -8, -6, 0, 6].map(v => v & 255));
  t('DRIBY', [0, 2, 3, 2, 0, -2, -3, -2].map(v => v & 255));
  // roles: 0 GK, 1-4 defence, 5-8 midfield, 9-10 attack
  const ROLE = [...Array(11).keys(), ...Array(11).keys()];
  t('ROLE', ROLE);
  t('TEAMOF', [...Array(11).fill(0), ...Array(11).fill(1), 0, 0]);
  t('TEAMBASE', [0, 11]);
  t('PCOL', [7, ...Array(10).fill(14), 3, ...Array(10).fill(1)]);
  const FDIST = [16, 100, 100, 100, 100, 230, 230, 230, 230, 330, 330];
  const FY = [212, 100, 180, 244, 324, 104, 176, 248, 320, 188, 236];
  const FMIN = [0, 24, 24, 24, 24, 80, 80, 80, 80, 160, 160];
  const FMAX = [60, 440, 440, 440, 440, 600, 600, 600, 600, 740, 740];
  const KODIST = [16, 90, 90, 90, 90, 220, 220, 220, 220, 320, 320];
  t('FDISTL', FDIST.map(lo)); t('FDISTH', FDIST.map(hi));
  t('FYL', FY.map(lo)); t('FYH', FY.map(hi));
  t('FMINL', FMIN.map(lo)); t('FMINH', FMIN.map(hi));
  t('FMAXL', FMAX.map(lo)); t('FMAXH', FMAX.map(hi));
  t('KODISTL', KODIST.map(lo)); t('KODISTH', KODIST.map(hi));

  // ---- HUD (row 0) and messages; 12-char messages at HUD col 14
  const hud = Array(40).fill(' '), hcol = Array(40).fill(1);
  const put = (c, txt, col) => [...txt].forEach((ch, i) => { hud[c + i] = ch; hcol[c + i] = col; });
  put(1, 'C64', 3); put(5, '0', 7); put(6, '-', 1); put(7, '0', 7); put(9, 'VIC', 1);
  put(29, '1ST', 7); put(33, '00:00', 1);
  t('HUDROW', hud.map(scr));
  t('HUDCOL', hcol);
  const MSGS = ['            ', '   GOAL !   ', '  THROW IN  ', '   CORNER   ', ' GOAL KICK  ', '  KICK OFF  ',
    ' HALF  TIME ', ' FULL  TIME ', ' DEMO  MATCH', 'PRESS  FIRE ', '   SAVED !  ', ' 2ND  HALF  '];
  MSGS.forEach(m => { if (m.length !== 12) throw new Error('msg ' + m); });
  t('MSGTXT', MSGS.flatMap(m => [...m].map(scr)));
  C.MSG_NONE = 0; C.MSG_GOAL = 1; C.MSG_THROW = 2; C.MSG_CORNER = 3; C.MSG_GOALKICK = 4; C.MSG_KICKOFF = 5;
  C.MSG_HALF = 6; C.MSG_FULL = 7; C.MSG_DEMO = 8; C.MSG_FIRE = 9; C.MSG_SAVED = 10; C.MSG_2ND = 11;
  t('MSGOFS', MSGS.map((_, i) => i * 12));
  t('HALFTXT', [...'1ST2ND'].map(scr));

  // ---- sound effects: AD, SR, then (ctrl, freq hi) per frame, 0 = end
  // AD, SR, then (ctrl, freq hi, frames) triples, ctrl 0 = end. Voice 2
  // trills the frequency every other frame (referee's whistle).
  const FX = {
    KICK: [0x05, 0x00, 0x81, 0x40, 1, 0x81, 0x28, 1, 0x41, 0x0A, 1, 0x41, 0x08, 1, 0x41, 0x06, 1, 0x40, 0x05, 1],
    BOUNCE: [0x04, 0x00, 0x11, 0x0E, 1, 0x11, 0x0B, 1, 0x11, 0x09, 1, 0x10, 0x08, 1],
    TACKLE: [0x06, 0x00, 0x81, 0x14, 1, 0x81, 0x10, 1, 0x81, 0x0C, 1, 0x80, 0x0A, 1],
    CATCH: [0x04, 0x00, 0x81, 0x08, 1, 0x11, 0x06, 1, 0x10, 0x05, 1],
    WHISTLE: [0x00, 0xC0, 0x11, 0xA2, 14, 0x10, 0xA2, 1],
    WHISTLE_L: [0x00, 0xC0, 0x11, 0xA2, 44, 0x10, 0xA2, 1],
    WHISTLE3: [0x00, 0xC0, 0x11, 0xA2, 10, 0x10, 0xA2, 6, 0x11, 0xA2, 10, 0x10, 0xA2, 6, 0x11, 0xA2, 40, 0x10, 0xA2, 1],
  };
  const order = ['KICK', 'BOUNCE', 'TACKLE', 'CATCH', 'WHISTLE', 'WHISTLE_L', 'WHISTLE3'];
  const sfx = [], ofs = [];
  for (const k of order) { ofs.push(sfx.length); sfx.push(...FX[k], 0); }
  if (sfx.length > 256) throw new Error('sfx data > 256');
  t('SFXOFS', ofs);
  t('SFXDATA', sfx);

  // ---- title screen text rows (screen codes) + colour: [row, col, colour, text]
  const TITLE_TEXT = [
    [9, 4, 7, 'THE BEAUTIFUL GAME - 8-BIT STYLE'],
    [12, 7, 1, 'PORT 2 FIRE  -  ONE PLAYER'],
    [14, 6, 1, 'PORT 1 FIRE  -  TWO PLAYERS'],
    [16, 6, 3, 'C64 IN BLUE  V  VIC IN WHITE'],
    [18, 7, 5, 'MADE WITH C64 DEV MACHINE'],
  ];
  // plain text uses only kept glyphs; '(' ')' ',' are not kept, swap them
  const clean = s => s.replace(/[(),]/g, m => ({ '(': '-', ')': '-', ',': ' ' }[m]));
  const ttext = [];
  for (const [row, col, colour, s] of TITLE_TEXT) {
    const cs = clean(s);
    ttext.push(row, col, colour, cs.length, ...[...cs].map(scr));
  }
  ttext.push(255);
  t('TITLETXT', ttext);
  t('ROWLO', Array.from({ length: 25 }, (_, r) => lo(MEM.SCRA + r * 40)));
  t('ROWHI', Array.from({ length: 25 }, (_, r) => hi(MEM.SCRA + r * 40)));
  t('MARKCOL', [7, 3]);
  t('BALLFR', [C.F_BALL0, C.F_BALL1, C.F_BALL2, C.F_BALL1]);
  t('RSMSG', [C.MSG_THROW, C.MSG_CORNER, C.MSG_GOALKICK, C.MSG_KICKOFF]);

  // ---- title logo: 3x5 block letters, rounded corners, rows 2-8
  const findChar = bytes => {
    const k = bytes.join(',');
    const i = cs.charset.findIndex(c => c.join(',') === k);
    if (i < 0) throw new Error('char not in set: ' + k);
    return i;
  };
  const E = cs.extraIdx;
  C.CH_BAR = E.BAR;
  const FILL1 = findChar(Array(8).fill(0x55)), FILL2 = findChar(Array(8).fill(0xAA));
  const LET = {
    G: ['###', '#..', '#.#', '#.#', '###'], O: ['###', '#.#', '#.#', '#.#', '###'],
    L: ['#..', '#..', '#..', '#..', '###'], A: ['###', '#.#', '###', '#.#', '#.#'],
    Z: ['###', '..#', '.#.', '#..', '###'], 6: ['###', '#..', '###', '#.#', '###'],
    4: ['#.#', '#.#', '###', '..#', '..#'], ' ': ['.', '.', '.', '.', '.'],
  };
  const word = 'GOLAZO 64';
  const grid = Array.from({ length: 5 }, () => []);
  const colOf = [];
  for (const ch of word) {
    const g = LET[ch];
    for (let r = 0; r < 5; r++) grid[r].push(...g[r].split(''), '.');
    for (let i = 0; i < g[0].length + 1; i++) colOf.push(ch === '6' || ch === '4' ? 1 : 0);
  }
  const W = grid[0].length - 1, x0 = Math.floor((40 - W) / 2);
  const logoCh = Array(280).fill(32), logoCol = Array(280).fill(1);
  const ROWCOL = [[1, 7, 7, 7, 2], [1, 3, 3, 3, 6]];
  const solid = (r, c) => r >= 0 && r < 5 && c >= 0 && c < W && grid[r][c] === '#';
  for (let r = 0; r < 5; r++) for (let c = 0; c < W; c++) {
    if (!solid(r, c)) continue;
    let ch = E.SOLID;
    const u = solid(r - 1, c), d = solid(r + 1, c), l = solid(r, c - 1), rr = solid(r, c + 1);
    if (!u && !l) ch = E.TRI_TL; else if (!u && !rr) ch = E.TRI_TR;
    else if (!d && !l) ch = E.TRI_BL; else if (!d && !rr) ch = E.TRI_BR;
    const i = (r + 1) * 40 + x0 + c;
    logoCh[i] = ch;
    logoCol[i] = 8 + ROWCOL[colOf[c]][r];
  }
  t('LOGOCH', logoCh);
  t('LOGOCOL', logoCol);
  t('TGRASS', Array.from({ length: 40 }, (_, x) => ((x >> 2) & 1) ? FILL2 : FILL1));
  // a touchline: map row 9 (the line is the cell's top pixel row) in the middle
  t('TLINE', Array.from({ length: 40 }, (_, x) => cs.map[9 * 128 + 66 + x]));

  // assign addresses
  let a = MEM.TABLES;
  const out = [];
  for (const [name, bytes] of T) {
    C[name] = a;
    out.push({ name, address: a, bytes });
    a += bytes.length;
  }
  if (a > 0xA000) throw new Error('tables overflow ' + a.toString(16));
  C.TABLES_END = a;
  return out;
}
