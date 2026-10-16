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

  t('MARKCOL', [7, 3]);
  t('BALLFR', [C.F_BALL0, C.F_BALL1, C.F_BALL2, C.F_BALL1]);
  t('RSMSG', [C.MSG_THROW, C.MSG_CORNER, C.MSG_GOALKICK, C.MSG_KICKOFF]);

  C.CH_BAR = cs.extraIdx.BAR;

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
