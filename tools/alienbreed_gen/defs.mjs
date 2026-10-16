// ALIEN BREED 64 - memory map, variables and constants shared by every
// code block. Everything here is folded to plain hex by resolve() before it
// reaches the project JSON, so the editor never needs these names.
//
// $0002-$002E  Music Maker player zero page (SID SONG node, base $03)
// $0030-$00FF  game zero page (Z_*)
// $0200-$02FF  variables          $0340-$03FF  variables
// $0400-$07FF  arrays (sprite shadow, actors, HUD buffers)
// $0801-$1FFF  BASIC stub, INIT, low code
// $2000-$2BFF  SFX column (SFX_MAKER driver, built by the editor's macros)
// $2C00-$3FFF  MUSIC column (Music Maker player + TITLE THEME)
// $4000/$4400  game screens A/B (double buffered), HUD rows 22-24 in both
// $4800-$4FFF  game charset (0-95 font, 96-254 station tiles)
// $5000-$5FFF  sprites (64 frames, pointer $40 up)
// $6000-$77FF  high code
// $7800-$7FCF  title screen RAM + colour, saved here at boot (see below)
// $8000-$9FFF  data: levels (RLE), char types, tables, title sprite text
// $A000-$CFFF  the expanded level: 128 x 96 chars (RAM under BASIC)
// $E000-$FF3F  TITLE BITMAP (AB_TITLE_BMP, VIC bank 3, under the KERNAL)
//
// The title is the Koala picture in bank 3: bitmap $E000, screen $C400,
// colour source $C7E8 (the editor's bank-3 layout). Screen and colour sit
// in the level area, so BOOT saves them to $7800 and the title puts them
// back; the title's sprite text is copied to $C000 the same way.
export const MEM = {
  SCRA: 0x4000, SCRB: 0x4400, CHARSET: 0x4800, SPRITES: 0x5000,
  MAP: 0xA000, MAPW: 128, MAPH: 96,
  DATA: 0x8000, DATA_END: 0xA000,
  SFX_ORG: 0x2000, MUSIC_ORG: 0x2C00, MUSIC_END: 0x4000,
  LOW_ORG: 0x0900, LOW_END: 0x2000,
  HIGH_ORG: 0x6000, HIGH_END: 0x7800,
  TITLE_BMP: 0xE000, TITLE_VSCR: 0xC400, TITLE_VCOL: 0xC7E8, TITLE_STORE: 0x7800, TITLE_VSPR: 0xC000,
};
export const SPR_PTR0 = (MEM.SPRITES - 0x4000) / 64;   // $40

const C = {};
export const CONSTS = C;
Object.assign(C, MEM);
C.SPR_PTR0 = SPR_PTR0;
C.PFROWS = 21;                                  // playfield rows 0-20
C.HUDROW = 21;                                  // HUD rows 21-23 in both screens
C.HUDA = MEM.SCRA + 21 * 40; C.HUDB = MEM.SCRB + 21 * 40; C.HUDC = 0xD800 + 21 * 40;
C.SPTRA = MEM.SCRA + 0x3F8; C.SPTRB = MEM.SCRB + 0x3F8;
// $D018: screen A ($4000) / B ($4400) with the game charset ($4800);
// title: screen $C400 + bitmap $E000 in bank 3
C.D018_A = 0x02; C.D018_B = 0x12; C.D018_T = 0x18;
// $DD00 bank bits: 2 = bank 1 ($4000, the game), 0 = bank 3 ($C000, the title)
C.BANK_GAME = 2; C.BANK_TITLE = 0;
C.TITLE_PTRS = MEM.TITLE_VSCR + 0x3F8;
// raster lines: HUD split (FLD from $D7, row 21 = HUD at $E0) and the frame
// IRQ; on the title the second IRQ moves the sprites to the lower text band
C.LINE_HUD = 0xD4; C.LINE_HUD_GO = 0xD7; C.LINE_HUD_END = 0xDE; C.LINE_VBL = 0xFA; C.LINE_TSPLIT = 0xA0;
// camera limits (world is 1024 x 768 pixels)
C.CAMX_MAX = (MEM.MAPW - 40) * 8;               // 704
C.CAMY_MAX = (MEM.MAPH - 21) * 8;               // 600

// ---- zero page ($30-$FF). The IRQ uses only Z_IA/Z_IX/Z_IY and Z_IP.
const zp = [
  'Z_IA', 'Z_IX', 'Z_IY', 'Z_IP', 'Z_IPH',
  'Z_T0', 'Z_T1', 'Z_T2', 'Z_T3', 'Z_T4', 'Z_T5', 'Z_T6', 'Z_T7',
  'Z_PTR', 'Z_PTRH', 'Z_PTR2', 'Z_PTR2H', 'Z_MP', 'Z_MPH', 'Z_SP', 'Z_SPH',
  'Z_BX', 'Z_BXH', 'Z_BY', 'Z_BYH', 'Z_BH', 'Z_CX', 'Z_CY', 'Z_HX', 'Z_HY', 'Z_HT', 'Z_HIT',
  'Z_TX', 'Z_TY', 'Z_I', 'Z_J', 'Z_K', 'Z_DX', 'Z_DXH', 'Z_DY', 'Z_DYH',
  'Z_SX', 'Z_SXH', 'Z_SY', 'Z_SYH', 'Z_SND',
];
zp.forEach((n, i) => { C[n] = 0x30 + i; });
// the redraw's 22 row pointers (44 bytes)
C.Z_RP = 0x80;
for (let r = 0; r < 22; r++) { C['Z_RP' + r] = 0x80 + r * 2; }
if (0x30 + zp.length > 0x80) throw new Error('zero page overflow');

// ---- variables
let va = 0x0200;
const blocks = [[0x0200, 0x0300], [0x0340, 0x0400], [0x0400, 0x0800]];
let bi = 0;
function v(name, size = 1) {
  while (va + size > blocks[bi][1]) { bi++; if (bi >= blocks.length) throw new Error('variables overflow'); va = blocks[bi][0]; }
  C[name] = va; va += size;
}
[
  // frame / display
  'READY', 'FRAMECNT', 'CUR_SCR', 'NEW_SCR', 'NEW_D011', 'NEW_D016', 'NEW_D018', 'NEW_D020',
  'HUD_D016', 'GSTATE', 'GTIMER', 'FORCE_RD', 'TEXTMODE', 'RNG', 'RNGH', 'JOY', 'JOYOLD', 'JOYNEW',
  'DISP_CX', 'DISP_CY', 'NCX', 'NCY',
  // player
  'P_DIR', 'P_ANIM', 'P_ACC', 'P_INV', 'P_DEAD', 'P_MOVED', 'ENERGY', 'LIVES', 'KEYS', 'AMMOL', 'AMMOH',
  'FIRE_CD', 'TERM_LOCK', 'LEVEL', 'CORES', 'SD_ON', 'SD_MIN', 'SD_SEC', 'SD_SUB', 'MSG_T',
  'HUD_DIRTY', 'SPAWN_T', 'VENT_I', 'NVENTS', 'NCORES', 'MENU_I', 'MENU_CD', 'BORDER_T',
  'START_X', 'START_XH', 'START_Y', 'START_YH',
  // audio
  'AUDIO_MODE', 'REU_OK', 'A_ON', 'A_PRI', 'A_LOOP', 'A_REM0', 'A_REM1', 'A_REM2', 'A_SPF', 'A_CLIP',
  'A_LATL', 'A_LATH', 'MUSIC_ON', 'SFX_ON',
  // display state applied by the frame IRQ, deck settings, misc
  'CUR_D011', 'CUR_D016', 'CUR_EN', 'CUR_D020', 'COL_REQ', 'TOUCH_TERM', 'GAME_COL', 'ALIEN_COL', 'ALIEN_HP', 'SPAWN_RATE', 'ALIEN_SPD',
  'TITLE_T', 'MSG_DEF', 'SEL_ROW', 'BUY_I', 'DEAD_CAUSE', 'RD_COUNT',
  'NEW_BANK', 'TITLE_ON', 'TCOL',
].forEach(n => v(n));
v('CAMX', 2); v('CAMY', 2); v('PX', 2); v('PY', 2);
v('SCORE', 3); v('CREDITS', 3);
v('ROWCOL', 21);                       // colour RAM per playfield row (text pages)
v('REU_HDR', 128);                      // the REU audio directory, fetched at boot
// sprite shadow (applied by the frame IRQ)
for (const n of ['SH_X', 'SH_Y', 'SH_PTR', 'SH_COL']) v(n, 8);
v('SH_MSB'); v('SH_EN');
// bullets (2) and aliens (5): actor arrays, index 0-6 (0-1 bullets, 2-6 aliens)
C.NBUL = 2; C.NALIEN = 5; C.NACT = 7;
for (const n of ['AXL', 'AXH', 'AYL', 'AYH', 'AST', 'ATM', 'AHP', 'ADIR', 'AFR', 'AACC', 'ASTK']) v(n, 8);
// cores (4 max) and vents (32 max) of the current level
v('CORE_X', 4); v('CORE_Y', 4); v('CORE_HP', 4);
v('VENT_X', 32); v('VENT_Y', 32);
v('MSG_BUF', 40);
C.VARS_END = va;

// ---- char types (CHAR_TYPES table): bit 7 = solid
Object.assign(C, {
  T_FLOOR: 0x00, T_KEY: 0x01, T_AMMO: 0x02, T_MEDKIT: 0x03, T_CREDIT: 0x04, T_EXIT: 0x05, T_VENT: 0x06,
  T_WALL: 0x80, T_DOOR: 0x81, T_TERM: 0x82, T_CORE: 0x83, T_DEAD: 0x84,
});
// ---- actor states
Object.assign(C, { AS_FREE: 0, AS_LIVE: 1, AS_SPAWN: 2, AS_DIE: 3 });
// ---- game states
Object.assign(C, { GS_PLAY: 0, GS_DEAD: 1, GS_INTEX: 2, GS_DONE: 3, GS_OVER: 4, GS_WIN: 5 });
// ---- sound ids (SFX_MAKER instrument index = REU clip index - 1)
export const SFX = ['GUN', 'ALIEN_DIE', 'HURT', 'PICKUP', 'DOOR', 'KEY', 'TERMINAL', 'ALARM', 'CORE_HIT', 'EXPLODE'];
SFX.forEach((n, i) => { C['S_' + n] = i; });
C.NSFX = SFX.length;
// clip 0 = title music, 1.. = SFX in SFX[] order
C.CLIP_MUSIC = 0;
// HUD dirty bits
Object.assign(C, { HD_ENERGY: 1, HD_LIVES: 2, HD_AMMO: 4, HD_KEYS: 8, HD_CREDITS: 16, HD_SCORE: 32, HD_MSG: 64, HD_TIMER: 128 });
