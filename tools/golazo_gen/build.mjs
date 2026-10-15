// Build GOLAZO.json (the Dev Machine project) and a stand-alone PRG.
//
//   node build.mjs [OUT.json] [OUT.prg] [--debug]
//
// The project is code blocks in ORG columns plus CHAR_SET / SPRITE_SET /
// BYTE_DATA assets, so the PRG built here should match the editor's own
// build byte for byte (compare with tools/golazo_gen/compare.mjs).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Assembler, resolve } from './asm.mjs';
import { CONSTS as C, MEM } from './defs.mjs';
import { buildCharset, MAPW, MAPH } from './pitch.mjs';
import { spriteBytes, FRAMES } from './sprites.mjs';
import { buildTables } from './tables.mjs';
import * as E from './engine.mjs';
import * as M from './match.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const TEMPLATES = path.join(ROOT, 'C64DevMachine_win.yyp', 'datafiles', 'C64DMResources', 'TEMPLATES');
const GROUP = 'GOLAZO';

// ------------------------------------------------------------ data
const cs = buildCharset();
const tables = buildTables(cs);
const charBytes = cs.charset.flat();
const sprBytes = spriteBytes();
if (MEM.SPRITES + sprBytes.length > 0x7F00) throw new Error('sprites overflow');

// ------------------------------------------------------------ code layout
const INIT_ROWS = [['sei', 0], ['lda_imm', 0], ['sta_abs', 53280], ['sta_abs', 53281]];
const INIT_BYTES = [0x78, 0xA9, 0x00, 0x8D, 0x20, 0xD0, 0x8D, 0x21, 0xD0];
const REDRAW_ORG = 0x0900;
const LOW_END = 0x3C00, HIGH_ORG = 0x6000, HIGH_END = 0x8000;   // code areas
const rd = E.redrawBlock(REDRAW_ORG);
Object.assign(C, rd.consts);

const COLUMNS = [
  { name: '01 BOOT', org: null, blocks: [['BOOT', E.BOOT]],
    note: 'GOLAZO 64 - a FIFA-style\nfootball game. BOOT: RAM+IO,\nIRQ chain on, then TITLE.' },
  { name: '02 SCREEN REDRAW', org: REDRAW_ORG, blocks: [['REDRAW', rd.text]],
    note: 'Unrolled 39x23 copy from the\npitch map to the back screen,\nin two halves (2 frames).' },
  { name: '03 IRQ + MULTIPLEXER', blocks: [['VIC', E.VIC], ['IRQ', E.IRQ]],
    note: '$FC: apply frame, 8 sprites.\n$3F: HUD split, fine Y scroll,\nthen re-use sprites down.' },
  { name: '04 SCROLL + CAMERA', blocks: [['SCROLL', E.SCROLL], ['CAMERA', E.CAMERA]],
    note: '8-way scroll, two screens.\nCamera follows the ball.' },
  { name: '05 SPRITE LIST', blocks: [['SPRITES', E.SPRITES]],
    note: '22 players, ball, shadow,\nmarkers: project, sort by Y,\nfit 8 per band (fair flicker).' },
  { name: '06 INPUT, MATHS, SOUND', blocks: [['INPUT', E.INPUT], ['MATH', E.MATH], ['SOUND', E.SOUND]],
    note: 'Joysticks, mul/div, distance,\nmovement. SID: kick, whistle,\nfiltered crowd noise.' },
  { name: '07 MATCH FLOW', blocks: [['GAMELOOP', M.GAMELOOP]],
    note: 'Main loop + match states:\nplay, restart, goal, half\ntime, full time.' },
  { name: '08 RULES + CLOCK', blocks: [['RULES', M.RULES]],
    note: 'Goals, throw-ins, corners,\ngoal kicks, kick-offs.\n45 minutes a half.' },
  { name: '09 HUD', blocks: [['HUD', M.HUD]], note: 'Score, clock and message\nline (both screens).' },
  { name: '10 PLAYERS + JOYSTICK', blocks: [['PLAYERS', M.PLAYERS]],
    note: 'Movement + frames. Human:\ntap = pass, hold = shoot,\nfire off the ball = slide.' },
  { name: '11 CPU AI + KEEPERS', blocks: [['AI', M.AI]],
    note: 'Formation 4-4-2 that shifts\nwith the ball, chasers,\ndribble / pass / shoot.' },
  { name: '12 BALL', blocks: [['BALL', M.BALL]],
    note: 'Ball physics (height, bounce,\nfriction), tackles, pick-ups,\nkeeper saves.' },
  { name: '13 KICKS', blocks: [['KICKS', M.KICKS]],
    note: 'Passes, shots, crosses,\nlong balls. Shots tell the\nkeeper where they go.' },
  { name: '14 TITLE', blocks: [['TITLE', M.TITLE]],
    note: 'Title + menu. Port 2 fire:\n1 player, port 1 fire: 2\nplayers, wait: demo match.' },
];

function assembleAll(columns) {
  const a = new Assembler();
  const sizes = [];
  for (const col of columns) {
    let pc;
    if (col.org === null) {
      pc = 0x080E + INIT_BYTES.length;
      a.pc = pc;
      a.addBlock(INIT_BYTES.map(b => '.byte $' + b.toString(16)).join('\n'), 0x080E, 'INIT');
    } else {
      pc = col.org;
      a.pc = pc;
    }
    const start = col.org === null ? 0x080E : col.org;
    for (const [name, src] of col.blocks) a.addBlock(col.resolved[name], null, name);
    sizes.push([col.name, start, a.pc]);
    col.end = a.pc;
  }
  return { a, sizes };
}

// Test builds (GOLAZO_TEST=script.json): the joystick reads come from a
// script of [frames, port2 bits, port1 bits] (up 1 down 2 left 4 right 8
// fire 16) instead of the CIAs. Same code layout: JSR replaces LDA abs.
const TEST = process.env.GOLAZO_TEST ? JSON.parse(fs.readFileSync(process.env.GOLAZO_TEST, 'utf8')) : null;
if (TEST) {
  const bytes = [];
  for (const [n, b1, b2] of TEST) {
    let left = n;
    while (left > 0) { const k = Math.min(255, left); bytes.push(k, b1, b2); left -= k; }
  }
  bytes.push(0);
  if (bytes.length > 0x900) throw new Error('test script too long');
  Object.assign(C, { T_REM: 0x0340, T_B1: 0x0341, T_B2: 0x0342, T_PTR: 0x0343, T_PTRH: 0x0344, T_SCRIPT: 0x3700, T_LV: 0x0345, T_LF: 0x0346, T_LOGL: 0x0347, T_LOGH: 0x0348 });
  const INPUT_TEST = `
TestJoy1:
 LDA T_PTRH
 BNE TjGo
 LDA #<TScript
 STA T_PTR
 LDA #>TScript
 STA T_PTRH
TjGo:
 LDA T_REM
 BNE TjHold
 LDA T_PTR
 STA Z_PTR2
 LDA T_PTRH
 STA Z_PTR2H
 LDY #$00
 LDA (Z_PTR2),Y
 BEQ TjEnd
 STA T_REM
 INY
 LDA (Z_PTR2),Y
 STA T_B1
 INY
 LDA (Z_PTR2),Y
 STA T_B2
 CLC
 LDA T_PTR
 ADC #$03
 STA T_PTR
 BCC TjHold
 INC T_PTRH
TjHold:
 DEC T_REM
TjOut:
 LDA T_B1
 EOR #$FF
 RTS
TjEnd:
 LDA #$00
 STA T_B1
 STA T_B2
 LDA #$01
 STA T_REM
 JMP TjOut
// frame timing log at $E000: raster line at Commit (lo, hi|late|redraw)
TestLog:
 LDA $D012
 STA T_LV
 LDA $D011
 AND #$80
 STA T_LF
 LDA RD_BUSY
 BEQ TlNr
 LDA T_LF
 ORA #$01
 STA T_LF
TlNr:
 LDA FRAMECNT
 CMP ITER_FC
 BEQ TlOk
 LDA T_LF
 ORA #$40
 STA T_LF
TlOk:
 LDA T_LOGH
 BNE TlGo
 LDA #$E0
 STA T_LOGH
TlGo:
 CMP #$F0
 BCS TlRts
 STA Z_PTR2H
 LDA T_LOGL
 STA Z_PTR2
 LDY #$00
 LDA T_LV
 STA (Z_PTR2),Y
 INY
 LDA T_LF
 STA (Z_PTR2),Y
 CLC
 LDA T_LOGL
 ADC #$02
 STA T_LOGL
 BCC TlRts
 INC T_LOGH
TlRts:
 RTS
TestJoy2:
 LDA T_B2
 EOR #$FF
 RTS
${bytes.map((b, i) => (i === 0 ? 'TScript:\n' : '') + '.byte $' + b.toString(16)).join('\n')}
`;
  COLUMNS.push({ name: '99 TEST INPUT', org: 0x3C00, fixed: true, blocks: [["INPUT_TEST", INPUT_TEST]], note: 'test' });
}

// resolve every block once (constants -> hex)
for (const col of COLUMNS) {
  col.resolved = {};
  for (const [name, src] of col.blocks) col.resolved[name] = resolve(src, C, name);
}
if (TEST) {
  const col = COLUMNS.find(c => c.blocks.some(([n]) => n === 'INPUT'));
  col.resolved.INPUT = col.resolved.INPUT.replace('LDA $DC00', 'JSR TestJoy1').replace('LDA $DC01', 'JSR TestJoy2');
  for (const c of COLUMNS) for (const k of Object.keys(c.resolved)) if (c.resolved[k].includes('\nCommit:\n')) c.resolved[k] = c.resolved[k].replace('\nCommit:\n', '\nCommit:\n JSR TestLog\n');
}
// branch relaxation: a branch that cannot reach becomes an inverted branch
// over a JMP (the text stays plain CODE BLOCK syntax)
const INV = { BNE: 'BEQ', BEQ: 'BNE', BCC: 'BCS', BCS: 'BCC', BPL: 'BMI', BMI: 'BPL', BVC: 'BVS', BVS: 'BVC' };
let relaxN = 0;
function layoutAndLink() {
  for (;;) {
    // columns fill $0900-$3BFF, then continue at $6000 (above the sprites)
    let pc = rd.end, high = false;
    let meas = new Assembler();
    for (const col of COLUMNS) {
      if (col.org === null || col.org === REDRAW_ORG || col.fixed) continue;
      col.org = (pc + 15) & ~15;
      meas.pc = col.org;
      for (const [name] of col.blocks) meas.addBlock(col.resolved[name], null, name);
      if (!high && meas.pc > LOW_END) {
        high = true;
        col.org = HIGH_ORG;
        meas = new Assembler();
        meas.pc = col.org;
        for (const [name] of col.blocks) meas.addBlock(col.resolved[name], null, name);
      }
      pc = meas.pc;
    }
    const r = assembleAll(COLUMNS);
    try {
      return { ...r, code: r.a.link() };
    } catch (e) {
      const m = String(e.message).match(/^(\w+):(\d+) branch out of range/);
      if (!m) throw e;
      const col = COLUMNS.find(c => c.blocks.some(([n]) => n === m[1]));
      const lines = col.resolved[m[1]].split('\n');
      const i = +m[2] - 1;
      const mm = lines[i].match(/^(\w+:)?(B[A-Z]{2}) (\w+)$/);
      if (!mm) throw e;
      const skip = 'Rlx' + (++relaxN);
      lines.splice(i, 1, (mm[1] || '') + INV[mm[2]] + ' ' + skip, 'JMP ' + mm[3], skip + ':');
      col.resolved[m[1]] = lines.join('\n');
    }
  }
}
const { a, sizes, code } = layoutAndLink();
if (relaxN) console.log('  relaxed %d long branches', relaxN);
for (const [name, s, e] of sizes) console.log('  %s  $%s-$%s  %d bytes', name.padEnd(26), s.toString(16), (e - 1).toString(16), e - s);
const boot = sizes[0];
if (boot[2] > REDRAW_ORG) throw new Error('BOOT runs into the redraw column');
const lowEnd = Math.max(...sizes.filter(s => s[1] < LOW_END).map(s => s[2]));
const highEnd = Math.max(HIGH_ORG, ...sizes.filter(s => s[1] >= HIGH_ORG).map(s => s[2]));
if (lowEnd > LOW_END) throw new Error('code overflows $3C00: $' + lowEnd.toString(16));
if (highEnd > HIGH_END) throw new Error('code overflows $8000: $' + highEnd.toString(16));
if (MEM.SPRITES + sprBytes.length > HIGH_ORG) throw new Error('sprites run into the high code area');
const codeEnd = lowEnd;
console.log('  code ends at $%s (%d bytes free below $3C00), high code $6000-$%s', lowEnd.toString(16), LOW_END - lowEnd, (highEnd - 1).toString(16));

// ------------------------------------------------------------ memory image
const mem = new Map();
const place = (addr, bytes, what) => bytes.forEach((b, i) => {
  if (mem.has(addr + i)) throw new Error(`${what} overlaps at $${(addr + i).toString(16)}`);
  mem.set(addr + i, b);
});
for (const [k, v] of code) mem.set(k, v);
place(MEM.CHARSET, charBytes, 'charset');
place(MEM.SPRITES, sprBytes, 'sprites');
place(MEM.MAP, Array.from(cs.map), 'map');
for (const t of tables) place(t.address, t.bytes, t.name);
if (C.VARS_END > 0xD000) throw new Error('vars overflow');

function writePrg(file) {
  const top = Math.max(...mem.keys());
  const img = new Uint8Array(top + 1 - 0x0801);
  img.set([0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x20, 0x32, 0x30, 0x36, 0x32, 0x00, 0x00, 0x00], 0);   // 10 SYS 2062 (as the editor writes it)
  for (const [k, v] of mem) if (k >= 0x0801) img[k - 0x0801] = v;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0x01, 0x08]), Buffer.from(img)]));
  console.log('wrote %s (%d bytes, $0801-$%s)', file, img.length + 2, top.toString(16));
}

// ------------------------------------------------------------ project JSON
const b64 = d => 'b64:' + Buffer.from(d).toString('base64');
const byteString = d => d.map(b => '$' + b.toString(16).toUpperCase().padStart(2, '0')).join(', ');
function asset(name, type, address, blob, meta) {
  return { name, type, address, blob: b64(blob), meta, group: GROUP, linked_assets: [], file: '', load_later: false,
    d64_filename: '', reu_used: 0, reu_size: 0, reu_filename: '' };
}
function buildProject() {
  const pol = JSON.parse(fs.readFileSync(path.join(TEMPLATES, 'POLARITY.json'), 'utf8'));
  const PA = Object.fromEntries(pol.assets.map(x => [x.name, x]));
  const assets = [];
  const cmeta = structuredClone(PA.CHARS_HOUSE.meta);
  Object.assign(cmeta, { format: 'RAW', char_count: 256, total_size: 2048, mc_mode: 1, mc_fg: 1, mc_bg: 0,
    mc_col1: 5, mc_col2: 13, bmp_mode: 'MC', tile_types: Array(256).fill(0) });
  assets.push(asset('GOLAZO_CHARS', 'CHAR_SET', MEM.CHARSET, charBytes, cmeta));
  const smeta = structuredClone(PA.POL_SPRITES.meta);
  Object.assign(smeta, { used_count: FRAMES.length, format: 'RAW', bg_col: 5, mc1_col: 10, mc2_col: 0,
    mc_mode: 1, mc_col1: 10, mc_col2: 0,
    sprite_mcs: FRAMES.map(() => 1), sprite_ucs: FRAMES.map(([n]) => n.startsWith('BALL') ? 1 : n === 'MARKER' ? 7 : 14) });
  smeta.compositor = { active_layer: 0, active_frame: 0, active_cell: -1, frames: [{ cells: [] }] };
  assets.push(asset('GOLAZO_SPRITES', 'SPRITE_SET', MEM.SPRITES, sprBytes, smeta));
  const bmeta = d => ({ byte_string: byteString(d), is_save_file: false, save_file_size: 256, tone_sorted: false, ecm_bg1: 6, ecm_bg2: 14 });
  assets.push(asset('PITCH_MAP', 'BYTE_DATA', MEM.MAP, Array.from(cs.map), bmeta(Array.from(cs.map))));
  for (const t of tables) assets.push(asset(t.name, 'BYTE_DATA', t.address, t.bytes, bmeta(t.bytes)));

  let uid = 700000;
  const nuid = () => ++uid;
  const HEIGHT = { ORG: 80, INIT: 80, MACRO_CODE: 100, COMMENT: 100 };
  function node(type, title, code, x, y, parent, custom = '') {
    const n = { binary_blob: '', x, y, type, params: [], custom_title: custom, stable_uid: nuid(),
      wire_in_source: -1, wire_out_target: -1, org_uid: -1, show_only_used: false, code_descriptor: '',
      scroll_alias: '', anim_alias: '', helper_text: '', comment_h: 0, comment_w: 0, comment_w_mult: 1, x_indent: 0,
      proxy: false, collapsed: false, end_address: 0, pc_address: 0, height: HEIGHT[type] || 100, title,
      connected: type !== 'COMMENT', org_parent_x: -1, org_parent_y: -1, has_org_parent: false, code };
    if (parent) { n.has_org_parent = true; n.org_parent_x = parent[0]; n.org_parent_y = parent[1]; }
    return n;
  }
  const nodes = [], orgs = [], boxes = [];
  let orgUid = 1;
  COLUMNS.forEach((col, ci) => {
    const x = 360 + ci * 320;
    let y = 340;
    nodes.push(node('COMMENT', 'COMMENT', [['Comment', col.note]], x, 160));
    let parent = null;
    if (col.org === null) {
      nodes.push(node('INIT', 'SYSTEM INIT', INIT_ROWS, x, y));
      y += 80;
    } else {
      const o = node('ORG', 'ORG BLOCK', [['org', 0]], x, y);
      o.pc_address = col.org; o.org_uid = orgUid++; o.connected = false;
      orgs.push(o);
      parent = [x, y];
      y += 80;
    }
    for (const [name] of col.blocks) {
      const n = node('MACRO_CODE', 'CODE BLOCK', [['code_block', col.resolved[name]]], x, y, parent, name.replace(/_/g, ' '));
      nodes.push(n);
      y += n.height;
    }
    boxes.push({ x: x - 20, y: 120, panel_links: [], is_panel: false, box_col_idx: ci % 8, box_name: col.name,
      box_h: y - 120 + 40, box_w: 280 });
  });
  return {
    ignored_conflicts: [], asset_groups: [GROUP], next_stable_uid: uid + 10, map_tile_bank_sel: -1, map_tile_bank: [],
    code_editor_font_index: 1, creator_locked: false, build_target: 0, kernal_unlocked: true, basic_unlocked: true,
    asset_sort_mode: 'ADDR', nodes: [...orgs, ...nodes], boxes, assets, map_global_mixed: 1,
  };
}

// ------------------------------------------------------------ main
const args = process.argv.slice(2).filter(s => !s.startsWith('--'));
const outJson = args[0] || path.join(HERE, 'out', 'GOLAZO.json');
const outPrg = process.env.GOLAZO_TEST_OUT || args[1] || path.join(HERE, 'out', 'golazo.prg');
fs.mkdirSync(path.dirname(outPrg), { recursive: true });
writePrg(outPrg);
if (!TEST) {
  fs.writeFileSync(outJson, JSON.stringify(buildProject()));
  console.log('wrote %s', outJson);
}
// symbols for debugging in VICE (monitor "ll" format)
const sym = [...Object.entries(a.labels).map(([k, v]) => `al C:${v.toString(16)} .${k}`),
  ...Object.entries(C).filter(([, v]) => typeof v === 'number' && v >= 0x100 && v <= 0xffff && !/^(F_|ST_|GS_|RS_|FX_|MSG_|P_)/.test(String(v))).map(([k, v]) => `al C:${v.toString(16)} .${k}`)];
fs.writeFileSync(path.join(path.dirname(outPrg), 'golazo.sym'), sym.join('\n'));
fs.writeFileSync(path.join(path.dirname(outPrg), 'labels.json'), JSON.stringify({ labels: a.labels, consts: C }, null, 1));
