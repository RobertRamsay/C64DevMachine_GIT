// SHMUP H template generator: node build.mjs [OUT.json]
// Writes the bundled template project (C64DMResources/TEMPLATES/SHMUP_H.json).
// The game is laid out like SHMUP V: one mapping box per job, a heading
// comment on top, the code / macro spine underneath, and a notes lane on the
// right with arrowed comments and the Creator panels.
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { reflow } from './reflow.mjs';
import { V_ASSETS, buildCharset, buildMap, buildSprites, buildTitle, buildSpawns, SPAWN_TYPES, STAMPS, MAP_ROWS, MAP_COLS, LOOP_COL, CH } from './art.mjs';
import { C, STATE, stateMapCode, stateUsed } from './code.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATES = path.join(HERE, '../../C64DevMachine_win.yyp/datafiles/C64DMResources/TEMPLATES');
const OUT = process.argv[2] || path.join(TEMPLATES, 'SHMUP_H.json');
const GROUP = 'TEMPLATE';

// ------------------------------------------------------------ assets
const b64 = d => 'b64:' + Buffer.from(d).toString('base64');
const byteString = d => [...d].map(b => '$' + b.toString(16).toUpperCase().padStart(2, '0')).join(', ');
const asset = (name, type, address, blob, meta) => ({ group: GROUP, file: '', type, linked_assets: [], reu_used: 0, reu_size: 0,
  reu_filename: '', d64_filename: '', load_later: false, blob: b64(blob), address, name, meta });
const dataMeta = d => ({ tone_sorted: false, mc_fg: 1, mc_col1: 1, mc_bg: 0, mc_mode: 0, mc_col2: 2, bmp_mode: 'MC', ecm_bg3: 3,
  byte_string: byteString(d), ecm_bg2: 14, save_file_size: 256, ecm_bg1: 6, is_save_file: false });

const ADDR = { TILES: 0x2000, ACTORS: 0x2800, FRONT_END: 0x4000, WORLD: 0x6800 };
const COLOURS = { space: 0, speckle: 12, rock: 8, terrain: 13, border: 0 };

const charset = buildCharset();
const map = buildMap();
const sprites = buildSprites();
const title = buildTitle(sprites);

function buildAssets() {
  const out = [];
  const tmeta = structuredClone(V_ASSETS.TILES.meta);
  Object.assign(tmeta, { char_count: 256, total_size: 2048, mc_mode: 1, mc_fg: COLOURS.terrain & 7, mc_bg: COLOURS.space,
    mc_col1: COLOURS.speckle, mc_col2: COLOURS.rock, tile_types: charset.tags });
  out.push(asset('TILES', 'CHAR_SET', ADDR.TILES, charset.bytes, tmeta));

  const smeta = structuredClone(V_ASSETS.ACTORS.meta);
  Object.assign(smeta, { used_count: sprites.list.length, sprite_mcs: sprites.list.map(() => 0), sprite_ucs: sprites.list.map(s => s[2]) });
  out.push(asset('ACTORS', 'SPRITE_SET', ADDR.ACTORS, sprites.bytes, smeta));

  out.push(asset('FRONT_END', 'BITMAP', ADDR.FRONT_END, title.file, structuredClone(V_ASSETS.FRONT_END.meta)));

  const wmeta = structuredClone(V_ASSETS.WORLD.meta);
  const stampData = STAMPS.flatMap(([, cells]) => cells);
  const charLut = Array(256).fill(1);
  for (let c = 96; c < 128; c++) charLut[c] = 0x10 | COLOURS.terrain;
  Object.assign(wmeta, { map_size_key: '2x2', stamp_w: 2, stamp_h: 2, stamp_count: STAMPS.length, stamp_data: stampData,
    stamp_mc: STAMPS.map(() => 1), stamp_override: STAMPS.map(() => 128), char_lut: charLut, char_lut_len: 256,
    map_w: [MAP_COLS * 2], map_h: [MAP_ROWS * 2], maps: [map.grid], test_grid: [...map.grid], map_count: 1, active_map: 0,
    chr_asset: 'TILES', map_mc_bg: COLOURS.space, map_mc_col1: COLOURS.speckle, map_mc_col2: COLOURS.rock,
    mc_bg: COLOURS.space, mc_col1: COLOURS.speckle, mc_col2: COLOURS.rock, active_char: 0 });
  // SPAWN layer (editor: open WORLD, press E): the enemy types and where they appear
  wmeta.spawn = { sprite_set: 'ACTORS', types: SPAWN_TYPES.map(t => ({ ...t })), maps: [buildSpawns(map)], sel: 0, mode: false, show: true };
  out.push(asset('WORLD', 'META_TILESET', ADDR.WORLD, stampData, wmeta));   // blob = the stamps, as in SHMUP V

  out.push(asset('MUSIC_AND_SFX', 'MUSIC_MAKER', 0, [0], buildMusic()));
  out.push(asset('STATUS', 'HUD', 0, ...buildHud()));

  const sfx = structuredClone(V_ASSETS.GAME_SFX.meta);
  sfx.instruments = [
    { release: 1, pulse_width: 2048, text: '$21,N,D2,N-12,D2,N-24,D2,---', sfx_note: 'C-6', sfx_priority: 1, name: 'LASER', attack: 0, decay: 3, sustain: 8 },
    { release: 2, pulse_width: 2048, text: '$81,N,D4,N-12,D4,N-24,D6,---', sfx_note: 'C-4', sfx_priority: 2, name: 'EXPLOSION', attack: 0, decay: 6, sustain: 10 },
    { release: 1, pulse_width: 2048, text: '$11,N,D3,N+7,D3,N+12,D4,---', sfx_note: 'C-5', sfx_priority: 1, name: 'CAPSULE', attack: 0, decay: 4, sustain: 8 },
    { release: 2, pulse_width: 1024, text: '$41,N,D2,N+4,D2,N+7,D2,N+12,D2,N+16,D4,---', sfx_note: 'C-5', sfx_priority: 2, name: 'POWER UP', attack: 0, decay: 5, sustain: 9 },
  ];
  out.push(asset('GAME_SFX', 'SFX_MAKER', 0, [0], sfx));
  return out;
}

// Title tune: a driving A-minor line over an octave-bouncing bass.
function buildMusic() {
  const m = structuredClone(V_ASSETS.MUSIC_AND_SFX.meta);
  const pat = (name, str, instr) => {
    const steps = str.trim().split(/\s+/).map(t => t === '.' ? { note: '', instr_idx: -1, empty: true }
      : t === '-' ? { note: '---', instr_idx: -1, empty: false } : { note: t, instr_idx: instr, empty: false });
    if (steps.length !== 32) throw new Error(`${name}: ${steps.length} steps`);
    return { pattern_len: 32, steps, name };
  };
  m.instruments = [
    { release: 3, pulse_width: 1024, text: '$41,D6,$40,D2,---', name: 'LEAD PULSE', attack: 0, decay: 5, sustain: 9 },
    { release: 2, pulse_width: 2048, text: '$11,D8,$10,D2,---', name: 'BASS', attack: 0, decay: 7, sustain: 8 },
  ];
  m.patterns = [
    pat('LEAD A', 'A-4 . . . E-5 . . . D-5 . C-5 . B-4 . C-5 . D-5 . . . C-5 . B-4 . A-4 . . . G-4 . . .', 0),
    pat('LEAD B', 'F-4 . A-4 . C-5 . F-5 . E-5 . . . D-5 . C-5 . B-4 . . . G#4 . B-4 . E-5 . . . - . . .', 0),
    pat('BASS A', 'A-2 . A-3 . A-2 . A-3 . A-2 . A-3 . G-2 . G-3 . F-2 . F-3 . F-2 . F-3 . G-2 . G-3 . G-2 . G-3 .', 1),
    pat('BASS B', 'F-2 . F-3 . F-2 . F-3 . D-2 . D-3 . D-2 . D-3 . E-2 . E-3 . E-2 . E-3 . E-2 . E-3 . E-2 . E-3 .', 1),
    pat('SILENT', Array(32).fill('-').join(' '), -1),
  ];
  m.songs = [{ loop: true, loop_row: 0, name: 'TITLE THEME', order: [
    { force_len: 32, v1: 0, v2: 2, repeat_short: false, v3: 4 },
    { force_len: 32, v1: 1, v2: 3, repeat_short: false, v3: 4 },
  ] }];
  m.play_speed = 5;
  return m;
}

// HUD rows 0-2: blob = 120 chars then 120 colours.
function buildHud() {
  const rows = [
    ' SCORE 000000    HI 000000     SHIPS 3  ',
    '  SPEED MISSL DOUBL LASER OPTN  SHLD    ',
    '',
  ];
  const chars = [], cols = [];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 40; c++) {
    if (r === 2) { chars.push(CH.HUD_LINE); cols.push(11); continue; }
    const ch = rows[r][c] || ' ';
    chars.push(ch.charCodeAt(0));
    cols.push(r === 1 ? 14 : /[0-9]/.test(ch) ? 1 : 15);
  }
  const meta = structuredClone(V_ASSETS.STATUS.meta);
  Object.assign(meta, { char_grid: chars, colour_grid: cols, chr_asset: 'TILES', hud_w: 40, hud_h: 3 });
  return [[...chars, ...cols], meta];
}

// ------------------------------------------------------------ node helpers
let uid = 400000;
const nuid = () => ++uid;
const HEIGHT = { ORG: 80, INIT: 80, MACRO_CODE: 100, NORMAL: 60, LABEL: 40, MACRO_IRQ_HANDLER: 100, MACRO_IRQ: 100,
  MACRO_SID_SONG: 140, MACRO_BMP: 100, MACRO_VWAIT: 60, MACRO_VIC: 120, MACRO_CHR: 120, MACRO_METASCROLL: 220,
  MACRO_SPR: 140, MACRO_SPAWNER: 140, MACRO_HUD: 120, MACRO_JOY: 140, MACRO_SFX: 140, COMMENT: 100 };
const TITLE = { ORG: 'ORG BLOCK', INIT: 'SYSTEM INIT', MACRO_CODE: 'CODE BLOCK', NORMAL: 'Opcode', LABEL: 'ADDRESS LABEL', COMMENT: 'COMMENT' };

function rawNode(type, code, x, y, extra = {}) {
  // comments are stored as paragraphs so a widened box reflows them
  if (type === 'COMMENT') code = [['Comment', reflow(code[0][1])]];
  return Object.assign({ anim_alias: '', x, helper_text: '', y, comment_w_mult: 1, comment_w: 0, comment_h: 0, x_indent: 0,
    proxy: true, collapsed: false, end_address: 0, type, pc_address: 0, height: HEIGHT[type] || 100, title: TITLE[type] || type,
    connected: type !== 'COMMENT', org_parent_x: -1, org_parent_y: -1, has_org_parent: false, code, binary_blob: '',
    custom_title: '', stable_uid: nuid(), wire_in_source: -1, wire_out_target: -1, org_uid: -1, show_only_used: false,
    code_descriptor: type === 'MACRO_CODE' ? 'Code Block' : '', scroll_alias: '', params: [] }, extra);
}
const P = (label, kind, sym, vmin, vmax, options = '', row = 0, slot = 1) => ({ label, kind, sym, row, slot, vmin, vmax, options, pin: false });
const COL_P = (label, sym) => P(label, 'COLOUR', sym, 0, 15);
const commentText = s => s.replace(/^\n/, '').replace(/\n$/, '');
const estLines = s => commentText(s).split('\n').reduce((n, l) => n + Math.max(1, Math.ceil(l.length / 30)), 0);
const commentH = s => 40 + estLines(reflow(s)) * 20;   // what the editor sizes a comment to

// A code block gets a short header naming its column and what it uses.
function codeText(colName, title, body) {
  const used = stateUsed(body);
  let head = `; ${colName.replace(/^\d+ /, '')} - ${title}\n`;
  if (used.length) {
    let line = '; State:';
    for (const n of used) { if ((line + ' ' + n).length > 64) { head += line + '\n'; line = ';       '; } line += ' ' + n; }
    head += line + '\n';
  }
  return head + ';\n' + body;
}

// ------------------------------------------------------------ the columns
// items: { k: key, t: type, title, code | body, params }
// notes: { at: key, text } - comment in the notes lane, arrowed at the node
// panels: { name, links: [keys], at: key }
const SNG = '{{SNG}}';
const joyTable = [[25, 'Unused', 0], [21, 'Unused', 0], [26, 'Unused', 0], [22, 'Unused', 0], [9, 'JoyUpRight', 1], [5, 'JoyUpLeft', 1],
  [10, 'JoyDownRight', 1], [6, 'JoyDownLeft', 1], [17, 'Unused', 0], [18, 'Unused', 0], [20, 'Unused', 0], [24, 'Unused', 0], [16, 'Unused', 0],
  [1, 'JoyUp', 1], [2, 'JoyDown', 1], [4, 'JoyLeft', 1], [8, 'JoyRight', 1], [255, 'Unused', 0]];
const TERRAIN_OPTS = 'Black=8,White=9,Red=10,Cyan=11,Purple=12,Green=13,Blue=14,Yellow=15';

const COLUMNS = [
  { name: '01 STARTUP - MAIN SPINE', org: null,
    head: 'STARTUP\nThe spine starts at SYSTEM\nINIT, banks BASIC out and\njumps to the title. The two\nraster IRQs that pin the HUD\nare set up from here too.',
    items: [
      { k: 'init', t: 'INIT', code: [['sei', 0], ['lda_imm', 0], ['sta_abs', 53280], ['sta_abs', 53281]] },
      { k: 'state', t: 'MACRO_CODE', title: 'GAME STATE MAP', raw: stateMapCode() },
      { k: 'startup', t: 'MACRO_CODE', title: 'BOOT + HUD SPLIT', body: C.startup },
      { k: 'irqh', t: 'MACRO_IRQ_HANDLER', title: 'HUD RASTER HANDLER', code: [['macro_irq_handler', 1]] },
      { t: 'NORMAL', code: [['rts', 0]] },
      { k: 'irq1', t: 'MACRO_IRQ', title: 'FIXED HUD - LINE 32', code: [['macro_irq', 32, 0, '', 'HudTop', 'HudFixed', 1, '']] },
      { t: 'MACRO_IRQ', title: 'PLAYFIELD - LINE 69', code: [['macro_irq', 69, 0, '', 'HudBottom', 'HudPlayfield', 1, '']] },
    ],
    notes: [
      { at: 'state', text: 'GAME STATE MAP\nEvery variable has a name\nhere, one page at $C000.\nOpen it to see what each\nbyte means - the rest of\nthe code only uses names.' },
      { at: 'irq1', text: 'Line 32: HUD rows, hires,\nno scroll (HudFixed).\nLine 69: the playfield,\nmulticolour and scrolled\n(HudPlayfield).' },
    ] },

  { name: '02 BOOT / TITLE', org: 0x8000,
    head: 'BOOT / TITLE\nShow the FRONT_END bitmap,\nplay the title tune, wait\nfor fire. Game over comes\nback here too.',
    items: [
      { k: 'boot', t: 'MACRO_CODE', title: 'BOOT TITLE', body: C.bootTitle },
      { k: 'sid', t: 'MACRO_SID_SONG', title: 'TITLE THEME', code: [['macro_sid_song', 'MUSIC_AND_SFX', 1, 3, 2, 0]] },
      { k: 'bmp', t: 'MACRO_BMP', title: 'BITMAP FRONT END', code: [['macro_bmp', 'FRONT_END', ADDR.FRONT_END, 1, 0]] },
      { k: 'tloop', t: 'MACRO_CODE', title: 'TITLE LOOP', body: C.titleLoop },
      { t: 'MACRO_VWAIT', title: 'VWAIT', code: [['macro_vwait', 248, 0, '']] },
      { t: 'NORMAL', code: [['jsr', `sng${SNG}_play`]] },
      { t: 'NORMAL', code: [['rts', 0]] },
    ],
    notes: [
      { at: 'sid', text: 'ASSET: MUSIC_AND_SFX\nThe title tune. Open it in\nthe Music Maker: patterns\nLEAD A/B and BASS A/B,\nsong TITLE THEME.' },
      { at: 'bmp', text: 'ASSET: FRONT_END\nThe title picture, a hires\nbitmap at $4000. Paint it\nin the bitmap editor.' },
    ] },

  { name: '03 GAME SETUP', org: 0x8C00,
    head: 'GAME SETUP\nScreen mode and charset,\nthe scrolling WORLD, the\nsprites and the HUD. Then\na new game starts.',
    items: [
      { t: 'LABEL', code: [['label', 'SetupGame']] },
      { t: 'NORMAL', code: [['jsr', 'SilenceGame']] },
      { k: 'vic', t: 'MACRO_VIC', title: 'GAME DISPLAY', code: [['macro_vic', 'MCT', 0, 1024, 8192, COLOURS.border, COLOURS.space, COLOURS.speckle, COLOURS.rock, 0]],
        params: [P('Border', 'COLOUR', '', 0, 15, '', 0, 5)] },
      { k: 'chr', t: 'MACRO_CHR', title: 'CHARSET + COLOURS', code: [['macro_chr', 'TILES', 1, 1], ['lda_imm', 27], ['sta_abs', 53265], ['lda_imm', 8], ['sta_abs', 53270],
        ['lda_imm', 25], ['sta_abs', 53272], ['lda_imm', COLOURS.space], ['sta_abs', 53281], ['lda_imm', COLOURS.speckle], ['sta_abs', 53282], ['lda_imm', COLOURS.rock], ['sta_abs', 53283]],
        params: [P('Space', 'COLOUR', '', 0, 15, '', 7, 1), P('Stars + speckle', 'COLOUR', '', 0, 15, '', 9, 1), P('Rock', 'COLOUR', '', 0, 15, '', 11, 1)] },
      { k: 'msc', t: 'MACRO_METASCROLL', title: 'WORLD SCROLLER', code: [['MACRO_METASCROLL', 'WORLD', 0, ADDR.WORLD, 0x60, 1, 0, COLOURS.terrain, 0, 0, 0, 3, 0]],
        params: [P('Grass + hatches', 'MODE', '', 8, 15, TERRAIN_OPTS, 0, 7)] },
      { k: 'spr0', t: 'MACRO_SPR', title: 'SPRITE 0 - SHIP', code: [['macro_spr', 'ACTORS', 0, 64, 144, 0, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 1 - SHOT', code: [['macro_spr', 'ACTORS', 1, 0, 0, 4, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 2 - DOUBLE', code: [['macro_spr', 'ACTORS', 2, 0, 0, 6, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 3 - MISSILE', code: [['macro_spr', 'ACTORS', 3, 0, 0, 7, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 4 - OPTION', code: [['macro_spr', 'ACTORS', 4, 0, 0, 8, 1]] },
      { k: 'spr5', t: 'MACRO_SPR', title: 'SPRITE 5 - ENEMY', code: [['macro_spr', 'ACTORS', 5, 0, 0, 10, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 6 - ENEMY', code: [['macro_spr', 'ACTORS', 6, 0, 0, 12, 1]] },
      { t: 'MACRO_SPR', title: 'SPRITE 7 - ENEMY', code: [['macro_spr', 'ACTORS', 7, 0, 0, 14, 1]] },
      { k: 'hud', t: 'MACRO_HUD', title: 'TOP STATUS', code: [['macro_hud', 'STATUS', 1024, 55296, 1, 1]] },
      { k: 'newgame', t: 'MACRO_CODE', title: 'NEW GAME', body: C.newGame, params: [P('Ships', 'RANGE', 'START_LIVES', 1, 9)] },
    ],
    notes: [
      { at: 'chr', text: 'ASSET: TILES\nThe charset: font (32-90)\nand the terrain (96-113).\nTags: T1 = rock (wall),\nT2 = hatch (target).\nRight-click a char to tag.' },
      { at: 'msc', text: 'ASSET: WORLD\nThe level: 2x2 stamps,\n116 x 11. Paint it in the\ntileset editor. The last\n20 columns must repeat\nthe first 20 - that is\nwhere the level loops\n(LOOP_COL, FRAME LOOP).' },
      { at: 'spr0', text: 'ASSET: ACTORS\n26 sprite frames, $A0 up:\n0-3 ship, 4 shot, 5 laser,\n6 double, 7 missile,\n8-9 option, 10-17 enemies\n(in pairs), 18-19 capsule,\n20-23 explosion,\n24-25 walker.' },
      { at: 'spr5', text: 'The sprites only get their\nstart frame here - every\nframe DrawActors (SPRITE\nDRAW) sets position, frame\nand colour.' },
      { at: 'hud', text: 'ASSET: STATUS\nThe HUD layout, rows 0-2.\nStatus (HUD VALUES) fills\nin the numbers and the\nmeter colours.' },
    ],
    panels: [{ name: 'SCREEN', links: ['vic', 'chr', 'msc'], at: 'vic' }] },

  { name: '04 FRAME LOOP', org: 0x9480,
    head: 'FRAME LOOP\nGame logic once a frame,\nthen wait for the border\nto draw the sprites and\nscroll the world.',
    items: [
      { k: 'loop', t: 'MACRO_CODE', title: 'GAME LOOP', body: C.gameLoop },
      { k: 'sync', t: 'MACRO_VWAIT', title: 'FRAME SYNC', code: [['macro_vwait', 248, 0, '']] },
      { k: 'scroll', t: 'MACRO_CODE', title: 'DRAW + SCROLL', body: C.scroll,
        params: [P('Scroll speed', 'MODE', 'SCROLL_SPEED', 0, 2, 'Slow=0,Normal=1,Fast=2')] },
    ],
    notes: [
      { at: 'loop', text: 'Every job of the game is\none JSR here. Comment one\nout to switch it off while\nyou work on another.' },
      { at: 'scroll', text: 'The world moves left, so\nthe camera moves RIGHT:\nJSR MSC_R from the WORLD\nSCROLLER. At LOOP_COL it\njumps back to column 0.' },
    ],
    panels: [{ name: 'SCROLL', links: ['scroll'], at: 'sync' }] },

  { name: '05 RESPAWN', org: 0x9580,
    head: 'RESPAWN\nA fresh ship on the left,\nweapons and enemies\ncleared, a moment of\nsafety.',
    items: [
      { k: 'reset', t: 'MACRO_CODE', title: 'RESET ACTORS', body: C.respawn,
        params: [P('Power-ups on death', 'MODE', 'KEEP_POWERS', 0, 1, 'Lose=0,Keep=1'), P('Safe frames', 'RANGE', 'RESPAWN_SAFE', 0, 250)] },
    ] },

  { name: '06 JOYSTICK / FIRE', org: 0x9600,
    head: 'JOYSTICK / FIRE\nPort 2. The JOYSTICK macro\ncalls a Joy... label per\ndirection; diagonals call\ntwo. Fire launches every\nfree weapon.',
    items: [
      { k: 'input', t: 'MACRO_CODE', title: 'INPUT', body: C.input, params: [P('Ship speed', 'RANGE', 'SHIP_SPEED', 1, 4)] },
      { k: 'joy', t: 'MACRO_JOY', title: 'JOYSTICK', code: [['macro_joy', 2, 248], ...joyTable] },
      { k: 'fire', t: 'MACRO_CODE', title: 'FIRE', body: C.fire, params: [P('Fire', 'MODE', 'AUTO_FIRE', 0, 1, 'Tap=0,Hold=1')] },
      { t: 'LABEL', code: [['label', 'JoyUpRight']] }, { t: 'NORMAL', code: [['jsr', 'JoyRight']] }, { t: 'NORMAL', code: [['jmp_abs', 'JoyUp']] },
      { t: 'LABEL', code: [['label', 'JoyUpLeft']] }, { t: 'NORMAL', code: [['jsr', 'JoyLeft']] }, { t: 'NORMAL', code: [['jmp_abs', 'JoyUp']] },
      { t: 'LABEL', code: [['label', 'JoyDownRight']] }, { t: 'NORMAL', code: [['jsr', 'JoyRight']] }, { t: 'NORMAL', code: [['jmp_abs', 'JoyDown']] },
      { k: 'diag', t: 'LABEL', code: [['label', 'JoyDownLeft']] }, { t: 'NORMAL', code: [['jsr', 'JoyLeft']] }, { t: 'NORMAL', code: [['jmp_abs', 'JoyDown']] },
      { k: 'left', t: 'LABEL', code: [['label', 'JoyLeft']] }, { t: 'MACRO_CODE', title: 'MOVE LEFT', body: C.joyLeft },
      { t: 'LABEL', code: [['label', 'JoyRight']] }, { t: 'MACRO_CODE', title: 'MOVE RIGHT', body: C.joyRight },
      { t: 'LABEL', code: [['label', 'JoyUp']] }, { t: 'MACRO_CODE', title: 'MOVE UP', body: C.joyUp },
      { t: 'LABEL', code: [['label', 'JoyDown']] }, { t: 'MACRO_CODE', title: 'MOVE DOWN', body: C.joyDown },
    ],
    notes: [
      { at: 'joy', text: 'Fire + direction rows are\noff, so fire never blocks\nmovement: the FIRE block\nreads fire after the move.' },
      { at: 'diag', text: 'Diagonals: one JSR for the\nside step, then JMP to the\nup/down routine, whose RTS\nreturns to the macro.' },
      { at: 'left', text: 'X is 9 bits: the screen is\n320 pixels wide, a byte\nonly reaches 255. Each\nmove clamps to the edges\n(X_MIN, X_MAX_LO, Y_MIN,\nY_MAX).' },
    ],
    panels: [{ name: 'SHIP', links: ['input', 'fire', 'reset', 'newgame'], at: 'input' }] },

  { name: '07 POWER METER', org: 0x9800,
    head: 'POWER METER\nCapsules light the next\nmeter slot. The power key\nbuys the lit one:\nSPEED MISSL DOUBL LASER\nOPTN SHLD.',
    items: [
      { k: 'pkey', t: 'MACRO_CODE', title: 'POWER KEY', body: C.powerKey,
        params: [P('Power key', 'MODE', 'POWER_KEY', 0, 2, 'Space=0,Return=1,C=2')] },
      { k: 'apply', t: 'MACRO_CODE', title: 'APPLY POWER', body: C.applyPower,
        params: [P('Max speed-ups', 'RANGE', 'MAX_SPEEDUPS', 0, 5), P('Shield hits', 'RANGE', 'SHIELD_HITS', 1, 9)] },
      { k: 'capsule', t: 'MACRO_CODE', title: 'CAPSULE', body: C.capsule },
    ],
    notes: [
      { at: 'pkey', text: 'The keyboard shares CIA 1\nwith the joystick: the row\nis selected for one read,\nthen port A goes back to\ninput for the stick.' },
      { at: 'capsule', text: 'A capsule borrows the\nsprite (5-7) of the enemy\nthat dropped it. It hides\nwhile the SPAWNER flies a\nnew enemy in that slot.' },
    ],
    panels: [{ name: 'POWER METER', links: ['pkey', 'apply'], at: 'apply' }] },

  { name: '08 ATTACK WAVES', org: 0xB000,
    head: 'ATTACK WAVES\nEnemies are placed on the\nWORLD map (SPAWN layer)\nand flown by the SPAWNER.\nThis just keeps it fed.',
    items: [
      { k: 'spawner', t: 'MACRO_SPAWNER', title: 'SPAWNER', code: [['MACRO_SPAWNER', 'WORLD', 0, 0, 3, 0, 0]] },
      { k: 'enemy', t: 'MACRO_CODE', title: 'ENEMY FLIGHT', body: C.enemy },
    ],
    notes: [
      { at: 'spawner', text: 'SPAWNER\nLaunches the WORLD map\'s\nSPAWN layer as it scrolls\nin (MODE SCROLL H), into\n3 slots = sprites 5-7.\nOpen WORLD, press E to\nplace enemies and edit\ntheir types: frame,\ncolour, movement, speed,\nHP, points, drop.' },
      { at: 'enemy', text: 'ASSET: WORLD - SPAWN LAYER\nOpen WORLD, press E. Pick\na type, L-click to place,\nR-click to delete. Each\ntype sets frame, colour,\nmovement + VALUE, speed,\nHP, points and drop.' },
      { at: 'enemy', text: 'Movements: STRAIGHT, SINE,\nCHASE, ZIGZAG, DIVE,\nWALKER (rides the ground)\nand TURRET (fixed to the\nmap, SPN_FIRE cues shots).' },
    ] },

  { name: '09 WEAPONS', org: 0x9C00,
    head: 'WEAPONS\nShot or LASER, DOUBLE,\nMISSILE and the OPTION.\nShots stop at rock and\nblow up hatches.',
    items: [
      { k: 'fw', t: 'MACRO_CODE', title: 'FIRE WEAPONS', body: C.fireWeapons },
      { k: 'weapons', t: 'MACRO_CODE', title: 'SHOT + DOUBLE', body: C.weapons,
        params: [P('Shot speed', 'RANGE', 'SHOT_SPEED', 3, 8), P('Laser speed', 'RANGE', 'LASER_SPEED', 4, 12), P('Double speed', 'RANGE', 'DOUBLE_SPEED', 2, 6)] },
      { k: 'missile', t: 'MACRO_CODE', title: 'MISSILE', body: C.missile, params: [P('Missile speed', 'RANGE', 'MISSILE_SPEED', 1, 5)] },
      { k: 'option', t: 'MACRO_CODE', title: 'OPTION', body: C.option, params: [P('Option distance', 'RANGE', 'OPTION_GAP', 4, 30)] },
    ],
    notes: [
      { at: 'weapons', text: 'Each weapon asks ProbeChar\n(COLLISIONS) what char is\nat its tip, then\nTerrainHit decides: rock\nstops it, a hatch is\nblown up.' },
      { at: 'option', text: 'All 8 sprites are in use,\nso the OPTION rams enemies\ninstead of shooting.' },
    ],
    panels: [{ name: 'WEAPONS', links: ['weapons', 'missile', 'option'], at: 'fw' }] },

  { name: '10 COLLISIONS / LIVES', org: 0x9E80,
    head: 'COLLISIONS / LIVES\nShip vs rock and enemies,\nweapons vs enemies, score,\nshield and lives.',
    items: [
      { k: 'hits', t: 'MACRO_CODE', title: 'HITS', body: C.hits,
        params: [P('Rock crash', 'MODE', 'WALLS_KILL', 0, 1, 'Off=0,On=1'), P('Capsules', 'MODE', 'DROPS', 0, 1, 'Off=0,On=1')] },
      { k: 'terrain', t: 'MACRO_CODE', title: 'TERRAIN', body: C.terrain,
        params: [P('Rock tag', 'RANGE', 'WALL_TAG', 1, 16), P('Hatch tag', 'RANGE', 'TARGET_TAG', 1, 16), P('Hatch points x100', 'RANGE', 'TARGET_POINTS', 1, 9)] },
      { k: 'box', t: 'MACRO_CODE', title: 'BOX TEST', body: C.boxTest },
      { k: 'probe', t: 'MACRO_CODE', title: 'PROBE CHAR', body: C.probe },
    ],
    notes: [
      { at: 'terrain', text: 'Tags come from TILES: rock\nchars are T1, hatch chars\nT2. Tag new chars the same\nway and they just work.' },
      { at: 'probe', text: 'ProbeChar reads the char\nunder a point straight off\nthe screen, so a blown-up\nhatch stays rubble until\nthe level loops round.' },
    ],
    panels: [{ name: 'RULES', links: ['hits', 'terrain'], at: 'hits' }] },

  { name: '11 SPRITE DRAW', org: 0xA280,
    head: 'SPRITE DRAW\nGame state into the VIC:\npositions (9-bit X),\nframes, colours, blinking\nand explosions.',
    items: [
      { k: 'draw', t: 'MACRO_CODE', title: 'DRAW ACTORS', body: C.draw,
        params: [COL_P('Ship', 'SHIP_COL'), COL_P('Ship with shield', 'SHIELD_COL'), COL_P('Shot + double', 'SHOT_COL'), COL_P('Laser', 'LASER_COL'),
          COL_P('Missile', 'MISSILE_COL'), COL_P('Option', 'OPTION_COL'), COL_P('Capsule', 'CAPSULE_COL'), COL_P('Explosion', 'BOOM_COL')] },
      { k: 'drawen', t: 'MACRO_CODE', title: 'DRAW ENEMIES', body: C.drawEnemies },
      { k: 'put', t: 'MACRO_CODE', title: 'PUT SPRITE', body: C.putSprite },
    ],
    notes: [
      { at: 'drawen', text: 'Enemy frame = its spawn\ntype FRAME + 0 or 1, swapped\nevery 8 frames, so enemy\nframes come in pairs in\nACTORS.' },
      { at: 'put', text: 'Sprites past X = 255 need\ntheir bit in $D010. SPR_MSB\ncollects them, written\nonce at the end.' },
    ],
    panels: [{ name: 'COLOURS', links: ['draw'], at: 'draw' }] },

  { name: '12 HUD VALUES', org: 0xA500,
    head: 'HUD VALUES\nScore, high score and\nships into the HUD, and\nthe meter slot colours.',
    items: [
      { k: 'status', t: 'MACRO_CODE', title: 'STATUS', body: C.status,
        params: [COL_P('Meter slot', 'METER_COL'), COL_P('Lit slot', 'METER_LIT_COL'), COL_P('Owned power', 'METER_OWNED_COL')] },
    ],
    panels: [{ name: 'HUD', links: ['status'], at: 'status' }] },

  { name: '13 FIXED HUD / RASTER', org: 0xA600,
    head: 'FIXED HUD / RASTER\nThe IRQ callbacks: HUD\nsteady and hires, then\nthe scrolling multicolour\nplayfield.',
    items: [{ k: 'raster', t: 'MACRO_CODE', title: 'HUD SPLIT', body: C.raster }] },

  { name: '14 EXPLOSIONS / SFX', org: 0xA680,
    head: 'EXPLOSIONS / SFX\nSound effects on voice 3,\nexplosion timers, and\nGAME OVER back to the\ntitle.',
    items: [
      { t: 'MACRO_CODE', title: 'SILENCE', body: C.silence },
      { k: 'sfxinit', t: 'MACRO_SFX', title: 'SFX SETUP', code: [['macro_sfx', 'GAME_SFX', 0, 3, 3]] },
      { t: 'NORMAL', code: [['rts', 0]] },
      { t: 'LABEL', code: [['label', 'FireSound']] },
      { k: 'sfxfire', t: 'MACRO_SFX', title: 'LASER SOUND', code: [['macro_sfx', 'GAME_SFX', 0, 3, 0]] },
      { t: 'MACRO_CODE', title: 'EXPLOSION SOUND', body: C.sfxExplosionEntry },
      { t: 'MACRO_SFX', title: 'EXPLOSION SOUND', code: [['macro_sfx', 'GAME_SFX', 1, 3, 0]] },
      { t: 'MACRO_CODE', title: 'CAPSULE SOUND', body: C.sfxCapsuleEntry },
      { t: 'MACRO_SFX', title: 'CAPSULE SOUND', code: [['macro_sfx', 'GAME_SFX', 2, 3, 0]] },
      { t: 'MACRO_CODE', title: 'POWER SOUND', body: C.sfxPowerEntry },
      { t: 'MACRO_SFX', title: 'POWER UP SOUND', code: [['macro_sfx', 'GAME_SFX', 3, 3, 0]] },
      { t: 'MACRO_CODE', title: 'SFX TICK', body: C.sfxTickEntry },
      { t: 'MACRO_SFX', title: 'SFX TICK', code: [['macro_sfx', 'GAME_SFX', 0, 3, 1]] },
      { k: 'effects', t: 'MACRO_CODE', title: 'EFFECTS + GAME OVER', body: C.effects },
    ],
    notes: [
      { at: 'sfxfire', text: 'ASSET: GAME_SFX\n0 LASER, 1 EXPLOSION,\n2 CAPSULE, 3 POWER UP.\nEach sound is a label, an\nSFX macro and an RTS.' },
    ] },
];

// ------------------------------------------------------------ layout
const README = `SHMUP H - READ ME
A sideways shooter in the
style of Konami's Nemesis.
The world scrolls left; you
fly right.

Each box is one job of the
game. The heading comment
says what it does, the
yellow arrows point at the
nodes that matter.

ASSETS (all editable):
TILES     charset + tags
WORLD     the level map
ACTORS    every sprite
FRONT_END title picture
STATUS    the HUD
MUSIC_AND_SFX title tune
GAME_SFX  sound effects

WORLD also holds the SPAWN
layer: press E in it to
place and edit enemies.

The CONTROL PANEL below
holds every setting (F9 =
Creator view): screen,
scroll, ship, power meter,
weapons, rules, colours
and HUD. Change a value,
rebuild with F5.

PLAY: joystick port 2.
Shoot a RED FAN for a
capsule; SPACE buys the
lit power.`;

function build() {
  const nodes = [], boxes = [];
  const byKey = {};
  let sngUid = 0, orgUid = 1;
  const PITCH = 640, X0 = 400;

  nodes.push(rawNode('COMMENT', [['Comment', README]], 20, 160, { comment_w: 300, custom_title: 'READ ME', title: 'READ ME' }));
  const controlLinks = [];

  COLUMNS.forEach((col, ci) => {
    const x = X0 + ci * PITCH;
    const nx = x + 320;
    nodes.push(rawNode('COMMENT', [['Comment', col.head]], x, 160, { custom_title: col.head.split('\n')[0], title: col.head.split('\n')[0], comment_w: 280 }));
    let y = 340, parent = null;
    if (col.org !== null) {
      const o = rawNode('ORG', [['org', 0]], x, y, { connected: false, proxy: false, pc_address: col.org, org_uid: orgUid++ });
      nodes.push(o);
      parent = [x, y];
      y += o.height;
    }
    for (const it of col.items) {
      let code = it.code;
      if (it.t === 'MACRO_CODE') code = [['code_block', it.raw || codeText(col.name, it.title, it.body)]];
      const n = rawNode(it.t, code, x, y);
      if (it.title && it.t !== 'MACRO_CODE') n.title = it.title;
      if (it.title && it.t === 'MACRO_CODE') { n.custom_title = it.title; n.title = it.title; }
      if (it.t === 'LABEL') n.title = it.code[0][1];
      if (it.params) n.params = it.params;
      if (parent) Object.assign(n, { has_org_parent: true, org_parent_x: parent[0], org_parent_y: parent[1] });
      if (it.t === 'MACRO_SID_SONG') sngUid = n.stable_uid;
      if (it.k) byKey[it.k] = n;
      nodes.push(n);
      y += n.height;
    }
    let bottom = y;
    // notes lane: notes and panels in order of the node they sit beside
    for (const p of col.panels || []) for (const k of p.links) controlLinks.push(byKey[k]);
    const lane = [...(col.notes || []).map(n => ({ ...n, kind: 'note' }))]
      .sort((a, b) => (a.kind === b.kind ? byKey[a.at].y - byKey[b.at].y : a.kind === 'note' ? -1 : 1));   // notes beside their nodes, panels under them
    let laneY = 340;
    for (const item of lane) {
      const target = byKey[item.at];
      const top = Math.max(laneY, target.y);
      if (item.kind === 'note') {
        const h = commentH(item.text);
        const c = rawNode('COMMENT', [['Comment', item.text]], nx, top, { comment_w: 280, custom_title: item.text.split('\n')[0], title: item.text.split('\n')[0] });
        // arrow from the left handle (bottom-left corner) to the node's right edge
        c.comment_arrows = [[1, x + 284, target.y + 22], [0, 0, 0], [0, 0, 0]];
        nodes.push(c);
        laneY = top + h + 30;
      } else {
        const linked = item.links.map(k => byKey[k]);
        const multi = linked.length > 1;
        let h = 36;
        for (const n of linked) {
          h += (multi ? 22 : 0) + 28;
          for (const p of n.params) h += p.kind === 'COLOUR' ? 70 : 52;
        }
        h += 10;
        boxes.push({ x: nx, y: top, panel_links: linked.map(n => n.stable_uid), is_panel: true, box_col_idx: ci % 10,
          box_name: item.name, box_h: h, box_w: 280 });
        laneY = top + h + 30;
      }
    }
    bottom = Math.max(bottom, laneY);
    boxes.push({ x: x - 20, y: 120, panel_links: [], is_panel: false, box_col_idx: ci % 10, box_name: col.name, box_h: bottom - 120 + 40, box_w: 620 });
  });

  // ONE control panel under the READ ME, left of SYSTEM INIT: every
  // node with settings, in column order
  let ph = 36;
  for (const n of controlLinks) { ph += 22 + 28; for (const p of n.params) ph += p.kind === 'COLOUR' ? 70 : 52; }
  ph += 10;
  const py = 160 + commentH(README) + 30;
  boxes.push({ x: 20, y: py, panel_links: controlLinks.map(n => n.stable_uid), is_panel: true, box_col_idx: 3,
    box_name: 'CONTROL PANEL', box_h: ph, box_w: 300 });
  boxes.push({ x: 0, y: 120, panel_links: [], is_panel: false, box_col_idx: 3, box_name: 'SHMUP H', box_h: py - 120 + ph + 30, box_w: 340 });

  // the title loop calls the song player by its macro label
  for (const n of nodes) if (n.type === 'NORMAL' && n.code[0][0] === 'jsr' && n.code[0][1].includes(SNG)) n.code[0][1] = n.code[0][1].replace(SNG, String(sngUid));
  // the GAME STATE MAP is parsed first so every block knows the names
  const state = byKey.state;
  const ordered = [state, ...nodes.filter(n => n !== state)];
  // boxes first, then panels drawn over them
  boxes.sort((a, b) => (a.is_panel ? 1 : 0) - (b.is_panel ? 1 : 0));
  return { nodes: ordered, boxes };
}

const { nodes, boxes } = build();
const project = {
  asset_groups: [GROUP], asset_sort_mode: 'ADDR', ignored_conflicts: [], next_stable_uid: uid + 10, map_tile_bank_sel: -1,
  map_tile_bank: [], code_editor_font_index: 1, map_global_mixed: 1, kernal_unlocked: true, basic_unlocked: true,
  creator_locked: false, build_target: 0, nodes, boxes, assets: buildAssets(),
};
fs.writeFileSync(OUT, JSON.stringify(project));
console.log('wrote %s: %d nodes, %d boxes, %d assets, %d bytes', OUT, nodes.length, boxes.length, project.assets.length, fs.statSync(OUT).size);
