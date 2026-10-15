// Memory map, variables and constants shared by every code block.
import { IDX } from './sprites.mjs';
import { G } from './pitch.mjs';

export const MEM = {
  SCRA: 0x4000, SCRB: 0x4400, CHARSET: 0x4800, SPRITES: 0x5000,
  MAP: 0x8000,            // 128 x 48 = $1800 bytes
  TABLES: 0x9800,         // BYTE_DATA tables $9800-$9FFF
  VARS: 0xC000,           // runtime variables (not in the PRG)
};
export const SPR_PTR0 = (MEM.SPRITES - 0x4000) / 64;

const C = {};
export const CONSTS = C;
Object.assign(C, MEM);
C.SPR_PTR0 = SPR_PTR0;
// $D018: screen A ($4000) / B ($4400), charset at $4800 (bits 3-1 = 1)
C.D018_A = 0x02; C.D018_B = 0x12;
C.BALL = 22;
C.NOBJ = 26;
C.NPL = 22;
C.IDLE_LIM = 0xD0;
C.AI_LIM = 0xDC;      // last raster line to start the deferred AI    // last raster line to start an idle redraw slice
C.OBJ_SHADOW = 23; C.OBJ_MARK1 = 24; C.OBJ_MARK2 = 25;

// ---- zero page ($10-$4F); IRQ handlers only use Z_SA/Z_SX/Z_SY/Z_MUX
const zp = ['Z_T0', 'Z_T1', 'Z_T2', 'Z_T3', 'Z_T4', 'Z_T5', 'Z_T6', 'Z_T7',
  'Z_PTR', 'Z_PTRH', 'Z_PTR2', 'Z_PTR2H', 'Z_DX', 'Z_DXH', 'Z_DY', 'Z_DYH',
  'Z_I', 'Z_J', 'Z_A0', 'Z_A1', 'Z_A2', 'Z_A3', 'Z_R0', 'Z_R1', 'Z_R2',
  'Z_TX', 'Z_TXH', 'Z_TY', 'Z_TYH', 'Z_SPD', 'Z_SPDH', 'Z_VZ', 'Z_VZH',
  'Z_SA', 'Z_SX', 'Z_SY', 'Z_MUX', 'Z_D010', 'Z_HUM', 'Z_K', 'Z_S0', 'Z_S1', 'Z_S2', 'Z_S3', 'Z_U0', 'Z_U1', 'Z_U2', 'Z_U3'];
zp.forEach((n, i) => { C[n] = 0x10 + i; });

// ---- variables at $C000
let va = MEM.VARS;
function v(name, size = 1) { C[name] = va; va += size; }
[
  'READY', 'NEW_DL', 'NEW_D016', 'NEW_S', 'NEW_FLIP', 'FRONT_DL', 'CUR_D016', 'CUR_S', 'CUR_D018',
  'HUD_D016', 'MUX_I', 'FRAMECNT', 'BACK_DL', 'FLIP_REQ', 'TITLE_MODE',
  'CAM1Y', 'CAMNY', 'CAMTY', 'SNAP_REQ', 'FRONTC', 'FRONTR', 'PRE_C', 'PRE_R', 'PRE_ST', 'PRE_ON', 'CSX', 'CSY',
  'MODE', 'HUMANS', 'GSTATE', 'GTIMER', 'RS_TYPE', 'RS_TEAM', 'KO_TEAM', 'RS_AUTO',
  'SCORE0', 'SCORE1', 'CLK_SUB', 'CLK_SEC', 'CLK_MIN', 'HALF', 'ATT0',
  'OWNER', 'LASTTOUCH', 'PASS_TO', 'GK_TRIED', 'SHOT_GOAL', 'SHOT_REACT', 'SCORER',
  'CTRL1', 'CTRL2', 'CHASE0', 'CHASE1', 'RNG', 'RNGH', 'CROWD_T', 'CROWD_C',
  'SFX_REQ1', 'SFX_REQ2', 'SFX_P1', 'SFX_P2', 'SFX_ON1', 'SFX_ON2', 'SFX_C1', 'SFX_C2', 'SFX_F2',
  'MSG_T', 'MSG_ID', 'BZL', 'BZH', 'BVZL', 'BVZH', 'BANIM', 'BFRAME', 'DRIFT0', 'DRIFT1',
  'TT_TIMER', 'TT_X', 'TT_XH', 'DEMO_T', 'WAITMIN', 'WAITCNT', 'IDLE_T',
  'AI_X', 'UP_X', 'GOALSIDE', 'SHOT_P', 'SHOT_SIDE',
  'FLOCK1', 'FLOCK2', 'HCTRL0', 'HCTRL1', 'RD_BUSY', 'KICKED', 'CC_LAST', 'CC_TURN', 'AI_SKIP', 'CMT_FC', 'BK_C', 'BK_R', 'BK_OK', 'AI_STEP', 'TATT', 'TATT1', 'TSHL', 'TSHL1', 'TSHH', 'TSHH1', 'YOFFL', 'YOFFH', 'ITER_FC', 'OVRCNT',
  'JOY1', 'JOY2', 'FHOLD1', 'FHOLD2', 'FPRESS1', 'FPRESS2', 'FREL1', 'FREL2',
].forEach(n => v(n));
v('CAM1X', 2); v('CAMNX', 2); v('CAMTX', 2); v('PRED_Y', 2); v('RS_X', 2); v('RS_Y', 2);
v('RING', 8); v('OVRCNT', 2); v('ITERCNT', 2);
// entity arrays (players 0-21, ball 22)
for (const n of ['PXF', 'PXL', 'PXH', 'PYF', 'PYL', 'PYH', 'VXL', 'VXH', 'VYL', 'VYH', 'PDIR', 'PANIM',
  'PSTATE', 'PTIMER', 'PCOOL', 'PMOVE', 'PSPD', 'PFRAME', 'PVI']) v(n, 24);
// sprite objects
for (const n of ['OBY', 'OBXL', 'OBXH', 'OBP', 'OBC', 'SORT', 'ALIST', 'SKEY']) v(n, 32);
// display lists: two buffers of 32 entries (base 0 / 32)
for (const n of ['DLY', 'DLXL', 'DLXH', 'DLP', 'DLC', 'DLT']) v(n, 64);
C.VARS_END = va;
if (va > 0xD000) throw new Error('vars overflow');
// JOY/FHOLD/FPRESS/FREL are used as 2-entry arrays (index 0 = port 2 / P1, 1 = port 1 / P2)
C.JOY = C.JOY1; C.FLOCK = C.FLOCK1; C.FHOLD = C.FHOLD1; C.FPRESS = C.FPRESS1; C.FREL = C.FREL1;
C.CTRL = C.CTRL1; C.CHASE = C.CHASE0; C.SCORE = C.SCORE0; C.DRIFT = C.DRIFT0;
for (const [a, b] of [['JOY1', 'JOY2'], ['FLOCK1', 'FLOCK2'], ['FHOLD1', 'FHOLD2'], ['FPRESS1', 'FPRESS2'], ['FREL1', 'FREL2'],
  ['CTRL1', 'CTRL2'], ['CHASE0', 'CHASE1'], ['SCORE0', 'SCORE1'], ['DRIFT0', 'DRIFT1']])
  if (C[b] !== C[a] + 1) throw new Error('pair not adjacent ' + a);

// ---- player states
Object.assign(C, { ST_NORMAL: 0, ST_SLIDE: 1, ST_KICK: 2, ST_FALLEN: 3, ST_DIVE: 4, ST_CELEB: 5, ST_HOLD: 6, ST_WAIT: 7 });
// ---- game states
Object.assign(C, { GS_PLAY: 0, GS_RESTART: 1, GS_GOAL: 2, GS_BREAK: 3, GS_FULL: 4 });
// ---- restart types
Object.assign(C, { RS_THROW: 0, RS_CORNER: 1, RS_GOALKICK: 2, RS_KICKOFF: 3 });
// ---- sound effects
Object.assign(C, { FX_KICK: 1, FX_BOUNCE: 2, FX_TACKLE: 3, FX_CATCH: 4, FX_WHISTLE: 5, FX_WHISTLE_L: 6, FX_WHISTLE3: 7 });

// ---- sprite frames
for (const [n, i] of Object.entries(IDX)) C['F_' + n] = i;

// ---- pitch geometry
Object.assign(C, {
  P_TOP: G.TOP, P_BOT: G.BOT, P_LEFT: G.LEFT, P_RIGHT: G.RIGHT, P_MIDX: G.MIDX, P_MIDY: G.MIDY,
  P_POST_T: G.POST_T, P_POST_B: G.POST_B, P_BAR: G.BAR_H,
});
C.GRAV = 0x1F;
