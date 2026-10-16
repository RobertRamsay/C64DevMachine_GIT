// ALIEN BREED 64 - builds the Dev Machine port (PORTS > GAMES) and a
// stand-alone test PRG + REU image.
//
//   node build.mjs [OUT.json] [--test script.json]
//
// OUT.json defaults to the bundled C64DMResources/TEMPLATES/ALIEN_BREED.json.
// out/alienbreed.prg is the same code with the two editor-macro columns
// (MUSIC: SID SONG, SFX: SFX Maker) stubbed out, so it is silent in SID
// mode; out/alienbreed.reu is the REU image (VICE: -reu -reuimage).
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { Assembler, resolve } from '../golazo_gen/asm.mjs';
import { CONSTS as C, MEM, SPR_PTR0, SFX } from './defs.mjs';
import { buildCharset, buildCharTypes, buildSprites, CH, SPR, CHAR_COUNT, BASE_ASSETS } from './art.mjs';
import { readKoala } from './koala.mjs';
import { buildTitleSprites, TITLE_SPR_COLS, BANDS } from './titlespr.mjs';
import { buildDecks, DT } from './levels.mjs';
import { buildHud, buildTexts, MSG_LEN, INTEX_ROWS } from './texts.mjs';
import { buildMusicMeta, buildSfxMeta, buildReuAudio, SFX_LABELS, REU_DIR } from './audio.mjs';
import * as K from './code_core.mjs';
import * as G from './code_game.mjs';
import * as V from './code_view.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.join(HERE, '..', '..');
const TEMPLATES = path.join(ROOT, 'C64DevMachine_win.yyp', 'datafiles', 'C64DMResources', 'TEMPLATES');
const OUTDIR = path.join(HERE, 'out');
const GROUP = 'ALIEN BREED';
const argv = process.argv.slice(2);
const ti = argv.indexOf('--test');
const TEST = ti >= 0 ? JSON.parse(fs.readFileSync(argv[ti + 1], 'utf8')) : null;
const outJson = argv.filter((a, i) => !a.startsWith("--") && (ti < 0 || i !== ti + 1))[0] || path.join(TEMPLATES, 'ALIEN_BREED.json');

// ------------------------------------------------------------ data
const charset = buildCharset();
const charTypes = buildCharTypes(C);
// the title picture (Koala) and its sprite text
const TITLE_KLA = path.join(HERE, 'art', 'title.kla');
const titleKla = fs.readFileSync(TITLE_KLA);
const title = readKoala(TITLE_KLA);
const tspr = buildTitleSprites();
const sprites = buildSprites();
const { decks, metaTable, metaCount } = buildDecks();
const hud = buildHud();
const reu = buildReuAudio(path.join(HERE, 'audio_src'));

// data area $8000-$9FFF
const DATA = [];
let dp = MEM.DATA;
const dput = (name, bytes, align = 1) => { dp = Math.ceil(dp / align) * align; DATA.push({ name, address: dp, bytes: Array.from(bytes) }); C[name] = dp; dp += bytes.length; };
dput('CHAR_TYPES', charTypes, 256);
const meta = [];
for (let q = 0; q < 4; q++) for (let i = 0; i < 64; i++) meta.push(metaTable[q][i] ?? CH.VOID);
dput('AB_META', meta, 256);
C.META_TL = C.AB_META; C.META_TR = C.AB_META + 64; C.META_BL = C.AB_META + 128; C.META_BR = C.AB_META + 192;
decks.forEach((d, i) => dput('DECK_TAB' + i, d.table, 16));
dput('HUD_TPL', hud.chars, 16);
dput('HUD_TCOL', hud.cols, 16);
// AB_TITLE_SPR is a SPRITE_SET (placed here, not a BYTE_DATA)
dp = Math.ceil(dp / 256) * 256;
C.AB_TITLE_SPR = dp;
const TITLE_SPR_AT = dp;
dp += 1024;
const texts = buildTexts(Math.ceil(dp / 256) * 256);
dput('TEXTS', texts.bytes, 256);
decks.forEach((d, i) => dput('DECK_RLE' + i, d.packed, 256));
if (dp > MEM.DATA_END) throw new Error('data overflows $A000: $' + dp.toString(16));
Object.assign(C, texts.C, hud.O);

// ------------------------------------------------------------ constants
for (const [k, v] of Object.entries(CH)) C['CH_' + k] = v;
for (const [k, v] of Object.entries(SPR)) C['SPR_' + k] = v;
for (const [k, v] of Object.entries(DT)) C['DT_' + k] = v;
Object.assign(C, {
  CAMX_MAX_LO: C.CAMX_MAX & 255, CAMX_MAX_HI: C.CAMX_MAX >> 8, CAMY_MAX_LO: C.CAMY_MAX & 255, CAMY_MAX_HI: C.CAMY_MAX >> 8,
  CAM_SPEED: 3, SPR_DX: 19, SPR_DY: 0x2C, SPR_YMAX: 0xE0,
  MARINE_COL: 5, BULLET_COL: 7, GOO_COL: 13, BOOM_COL: 8,
  START_AMMO_L: 0x50, START_AMMO_H: 0x02, CLIP_ROUNDS: 0x50, ENERGY_MAX: 64, MEDKIT_ENERGY: 24, CREDIT_PICKUP: 0x10,
  DEATH_FRAMES: 64, RESPAWN_SAFE: 100, BITE_SAFE: 40, BITE_DAMAGE: 6, PBOX: 5, ABOX: 5, HIT_RANGE: 10,
  SPEED_INT: 1, SPEED_FRAC: 0x80, FIRE_RATE: 7, BULLET_LIFE: 22,
  SPAWN_FAR_X: 24, SPAWN_FAR_Y: 18, SPAWN_NEAR: 5, SPAWN_FRAMES: 32, DIE_FRAMES: 16, CORE_HITS: 12,
  SD_START_MIN: 0x01, SD_START_SEC: 0x30, MSG_LEN, MSG_TIME: 150, PAGE_WAIT: 50, DECKS: decks.length,
  INTEX_ITEMS: INTEX_ROWS.length, INTEX_CURSOR_COL: 1, INTEX_COL: 3, INTEX_SEL_COL: 1,
});
// title: picture background, sprite text colours, frames (pointer = frame,
// the text is copied to $C000 = pointer 0) and the two bands
const msb = xs => xs.reduce((m, x, i) => m | (x > 255 ? 1 << i : 0), 0);
Object.assign(C, {
  TITLE_BG: title.bg, TSPR_IND: TITLE_SPR_COLS.individual, TSPR_DIM: TITLE_SPR_COLS.dim, TSPR_MC1: TITLE_SPR_COLS.mc1, TSPR_MC2: TITLE_SPR_COLS.mc2,
  TF_C64: tspr.W.C64.first, TF_C64D: tspr.W.C64D.first, TF_C64U: tspr.W.C64U.first, TF_C64UD: tspr.W.C64UD.first,
  TTOP_Y: BANDS.TOP_Y, TTOP_MSB: msb(tspr.top), TLO_Y: BANDS.LOW_Y, TLO_MSB: msb(tspr.low),
  TLO_N: tspr.low.length, TLO_EN: (1 << tspr.low.length) - 1,
});
if (tspr.top.length !== 4) throw new Error('the C64 | C64U band must be 4 sprites');
const hexList = a => a.map(v => '$' + (v & 255).toString(16).toUpperCase().padStart(2, '0')).join(',');
const lowPtr = [...Array(tspr.W.PRESS.n).keys()].map(k => tspr.W.PRESS.first + k).concat([...Array(tspr.W.PLAY.n).keys()].map(k => tspr.W.PLAY.first + k));
const fillTitle = s => s.replace('{{TTOP_X}}', hexList(tspr.top))
  .replace('{{TLO_X}}', hexList([...tspr.low, ...Array(8 - tspr.low.length).fill(0)]))
  .replace('{{TLO_PTR}}', hexList(lowPtr));

// ------------------------------------------------------------ columns
// area: 'spine' (after INIT), 'low' $0900-$1FFF, 'high' $6000-$77FF
// ($E000 holds the title bitmap). MusicInit (AUDIO) and the IRQ stay below
// $E000 anyway: the Music Maker init / play may page the KERNAL in.
const INTEX_ROWS_TXT = INTEX_ROWS.map(r => '$' + r.toString(16).toUpperCase().padStart(2, '0')).join(',');
const COLUMNS = [
  { name: '01 BOOT', area: 'spine', blocks: [['BOOT', K.BOOT]],
    note: 'BOOT\nRAM + I/O only ($01 = $35),\nVIC bank 1, raster IRQ and\nNMI vectors, REU check,\nthen the TITLE.' },
  { name: '02 IRQ + AUDIO', area: 'low', blocks: [['IRQ', fillTitle(K.IRQ)], ['AUDIO', K.AUDIO]],
    note: 'IRQ + AUDIO\nLine $FA: apply the frame,\ntick music / SFX / REU.\nLine $D4: HUD FLD split\n(title: line $A0 band).\nNMI: one REU byte into\n$D418 (the REU stream).' },
  { name: '03 HELPERS', area: 'low', blocks: [['UTIL', K.UTIL]],
    note: 'HELPERS\nMap pointer, char under a\nbox, tiles to map + screen,\nBCD score, joystick.' },
  { name: '04 TITLE', area: 'low', blocks: [['TITLE', fillTitle(G.TITLE)]],
    note: 'TITLE\nAB_TITLE_BMP (bank 3) with\nsprite text in two bands.\nLEFT = C64 (SID), RIGHT =\nC64U (REU stream).' },
  { name: '05 GAME STATES', area: 'low', blocks: [['STATES', G.STATES]],
    note: 'GAME STATES\nNew game, deck load (RLE\nmetatiles -> 128 x 96 map),\nthe frame loop, death,\nself-destruct clock.' },
  { name: '06 SCROLL', area: 'high', blocks: [['SCROLL', V.SCROLL]],
    note: 'SCROLL\n8-way, double buffered:\na new char cell redraws the\nback screen (unrolled),\nshown with the new fine\nscroll at the next frame.' },
  { name: '07 MARINE', area: 'high', blocks: [['PLAYER', G.PLAYER]],
    note: 'MARINE\n8-way at 1.5 px a frame,\nwalls per axis, keys open\ndoors, terminals open the\nIntex network, pickups.' },
  { name: '08 WEAPONS', area: 'high', blocks: [['WEAPONS', G.WEAPONS]],
    note: 'WEAPONS\nTwo shots at a time, one\nround each. Walls stop\nthem, cores take hits,\naliens die.' },
  { name: '09 ALIENS', area: 'high', blocks: [['ALIENS', G.ALIENS]],
    note: 'ALIENS\nOut of the vents near you,\nchase along the walls,\nbite on contact.' },
  { name: '10 SPRITES', area: 'high', blocks: [['SPRITES', V.SPRITES]],
    note: 'SPRITES\nWorld to screen: marine,\n2 bullets, 5 aliens into\nthe shadow the IRQ applies.' },
  { name: '11 HUD', area: 'high', blocks: [['HUD', V.HUD]],
    note: 'HUD\nRows 22-24 of both\nscreens: energy, lives,\nammo, keys, credits, score\nand the message line.' },
  { name: '12 INTEX + PAGES', area: 'high', blocks: [['PAGES', V.PAGES], ['INTEX', V.INTEX.replace('{{INTEX_ROWS}}', INTEX_ROWS_TXT)]],
    note: 'INTEX + PAGES\nThe Intex terminal shop,\ndeck complete, victory and\ngame over screens.' },
];
const AREAS = { low: [0x0900, MEM.LOW_END], high: [MEM.HIGH_ORG, MEM.HIGH_END] };
const INIT_ROWS = [['sei', 0], ['lda_imm', 0], ['sta_abs', 53280], ['sta_abs', 53281]];
const INIT_BYTES = [0x78, 0xA9, 0x00, 0x8D, 0x20, 0xD0, 0x8D, 0x21, 0xD0];

// stand-alone stubs for the editor macro columns
const STUB_SFX = ['SfxInit', 'SfxTick', ...SFX_LABELS].map(l => l + ':\n RTS').join('\n');
const STUB_MUSIC = `MusicStart:\n RTS\n${K.SNG_PLAY}:\n RTS`;

// test builds: joystick from a script [frames, bits] (up 1 down 2 left 4 right 8 fire 16)
let testBlock = null;
if (TEST) {
  const bytes = [];
  for (const [n, b] of TEST) { let left = n; while (left > 0) { const k = Math.min(255, left); bytes.push(k, b); left -= k; } }
  bytes.push(0);
  Object.assign(C, { T_REM: 0x03F0, T_B: 0x03F1, T_PTR: 0x03F2, T_PTRH: 0x03F3 });
  testBlock = `TestJoy:
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
 STA T_B
 CLC
 LDA T_PTR
 ADC #$02
 STA T_PTR
 BCC TjHold
 INC T_PTRH
TjHold:
 DEC T_REM
 LDA T_B
 EOR #$FF
 RTS
TjEnd:
 LDA #$00
 STA T_B
 LDA #$01
 STA T_REM
 LDA #$FF
 RTS
${bytes.map((b, i) => (i === 0 ? 'TScript:\n' : '') + '.byte $' + b.toString(16)).join('\n')}`;
  if (bytes.length > 0x300) throw new Error('test script too long');
}

for (const col of COLUMNS) {
  col.resolved = {};
  for (const [name, src] of col.blocks) col.resolved[name] = resolve(src, C, name);
}
if (TEST) {
  const col = COLUMNS.find(c => c.blocks.some(([n]) => n === 'UTIL'));
  const t = col.resolved.UTIL;
  if (!t.includes('LDA $DC00')) throw new Error('no joystick read to patch');
  col.resolved.UTIL = t.replace('LDA $DC00', 'JSR TestJoy');
}
// keep the Z_ trap away: no constant may resolve to a 2-digit zero page
// operand unless it is named Z_ (resolve() guarantees that), and nothing
// may name a built-in HW_/UV_ location
for (const col of COLUMNS) for (const k of Object.keys(col.resolved))
  if (/\b(HW|UV)_/.test(col.resolved[k])) throw new Error(k + ': uses a reserved HW_/UV_ name');

// ------------------------------------------------------------ layout + link
const INV = { BNE: 'BEQ', BEQ: 'BNE', BCC: 'BCS', BCS: 'BCC', BPL: 'BMI', BMI: 'BPL', BVC: 'BVS', BVS: 'BVC' };
let relaxN = 0;
function layout() {
  for (;;) {
    const a = new Assembler();
    a.pc = 0x080E;
    a.addBlock(INIT_BYTES.map(b => '.byte $' + b.toString(16)).join('\n'), 0x080E, 'INIT');
    const sizes = [];
    const fill = { low: null, high: AREAS.high[0] };
    for (const col of COLUMNS) {
      if (col.area === 'spine') {
        for (const [name] of col.blocks) a.addBlock(col.resolved[name], null, name);
        col.org = null; col.start = 0x080E; col.end = a.pc;
        fill.low = Math.max(AREAS.low[0], (a.pc + 15) & ~15);
        sizes.push(col);
        continue;
      }
      col.org = (fill[col.area] + 15) & ~15;
      a.pc = col.org;
      for (const [name] of col.blocks) a.addBlock(col.resolved[name], null, name);
      col.start = col.org; col.end = a.pc;
      fill[col.area] = a.pc;
      if (a.pc > AREAS[col.area][1]) throw new Error(`${col.name} overflows the ${col.area} area: $${a.pc.toString(16)}`);
      sizes.push(col);
    }
    // stubs (test PRG only; the JSON has the real macro columns here)
    a.addBlock(STUB_SFX, MEM.SFX_ORG, 'STUB_SFX');
    a.addBlock(STUB_MUSIC, MEM.MUSIC_ORG, 'STUB_MUSIC');
    if (testBlock) a.addBlock(resolve(testBlock, C, 'TEST'), 0x5C00, 'TEST');
    try {
      return { a, code: a.link(), sizes, fill };
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
const { a, code, sizes, fill } = layout();
if (relaxN) console.log('  relaxed %d long branches', relaxN);
for (const s of sizes) console.log('  %s $%s-$%s  %d bytes', s.name.padEnd(20), s.start.toString(16), (s.end - 1).toString(16), s.end - s.start);
console.log('  free: low %d, high %d bytes', AREAS.low[1] - fill.low, AREAS.high[1] - fill.high);
console.log('  data $8000-$%s (%d free), metatiles %d, chars %d, sprites %d, title text sprites %d', (dp - 1).toString(16), MEM.DATA_END - dp, metaCount, CHAR_COUNT, sprites.count, tspr.count);
decks.forEach(d => console.log('  %s: %d bytes RLE, %d vents, %d cores, %d keys', d.deck.name, d.packed.length, d.vents, d.cores, d.keysFound));
console.log('  REU audio: %d KB, clips %s', Math.round(reu.total / 1024), reu.clips.map(c => `${c.name}(${c.source})`).join(' '));

// ------------------------------------------------------------ memory image / PRG
const mem = new Map();
const place = (addr, bytes, what) => bytes.forEach((b, i) => { if (mem.has(addr + i)) throw new Error(`${what} overlaps at $${(addr + i).toString(16)}`); mem.set(addr + i, b & 255); });
for (const [k, v] of code) mem.set(k, v);
place(MEM.CHARSET, charset, 'charset');
// the Koala as the editor emits a bank-3 BITMAP: bitmap, screen at bank + $400, colour after it
place(MEM.TITLE_BMP, title.bitmap, 'title bitmap');
place(MEM.TITLE_VSCR, title.screen, 'title screen');
place(MEM.TITLE_VCOL, title.colour, 'title colour');
place(TITLE_SPR_AT, tspr.bytes, 'title sprite text');
place(MEM.SPRITES, sprites.bytes, 'sprites');
for (const d of DATA) place(d.address, d.bytes, d.name);
fs.mkdirSync(OUTDIR, { recursive: true });
function writePrg(file) {
  const top = Math.max(...mem.keys());
  const img = new Uint8Array(top + 1 - 0x0801);
  img.set([0x0B, 0x08, 0x0A, 0x00, 0x9E, 0x20, 0x32, 0x30, 0x36, 0x32, 0x00, 0x00, 0x00], 0);
  for (const [k, v] of mem) if (k >= 0x0801) img[k - 0x0801] = v;
  fs.writeFileSync(file, Buffer.concat([Buffer.from([0x01, 0x08]), Buffer.from(img)]));
  console.log('wrote %s (%d bytes)', file, img.length + 2);
}
writePrg(path.join(OUTDIR, TEST ? 'alienbreed_test.prg' : 'alienbreed.prg'));
const reuImg = Buffer.alloc(Math.max(0x20000, Math.ceil(reu.total / 0x10000) * 0x10000));
Buffer.from(reu.dir).copy(reuImg, REU_DIR);
for (const c of reu.clips) Buffer.from(c.bytes).copy(reuImg, c.start);
fs.writeFileSync(path.join(OUTDIR, 'alienbreed.reu'), reuImg);
fs.writeFileSync(path.join(OUTDIR, 'labels.json'), JSON.stringify({ labels: a.labels, consts: C }, null, 1));
fs.writeFileSync(path.join(OUTDIR, 'alienbreed.sym'), Object.entries(a.labels).map(([k, v]) => `al C:${v.toString(16)} .${k}`).join('\n'));
if (TEST) process.exit(0);

// ------------------------------------------------------------ project JSON
const b64 = d => 'b64:' + Buffer.from(d).toString('base64');
const byteString = d => d.map(b => '$' + b.toString(16).toUpperCase().padStart(2, '0')).join(', ');
function asset(name, type, address, blob, metaObj, extra = {}) {
  return { name, type, address, blob: b64(blob), meta: metaObj, group: GROUP, linked_assets: [], file: '', load_later: false,
    d64_filename: '', reu_used: 0, reu_size: 0, reu_filename: '', reu_base_file: '', order: -1, ...extra };
}
const bmeta = d => ({ byte_string: byteString(d), is_save_file: false, save_file_size: 256, tone_sorted: false, ecm_bg1: 6, ecm_bg2: 14 });
const rawMeta = n => ({ byte_string: '', is_save_file: true, save_file_size: n, tone_sorted: false, ecm_bg1: 6, ecm_bg2: 14 });
function buildAssets() {
  const out = [];
  const cmeta = structuredClone(BASE_ASSETS.TILES.meta);
  Object.assign(cmeta, { format: 'RAW', char_count: 256, total_size: 2048, mc_mode: 1, mc_fg: 6, mc_bg: 0, mc_col1: 11, mc_col2: 15,
    bmp_mode: 'MC', tile_types: Array(256).fill(0) });
  out.push(asset('AB_CHARS', 'CHAR_SET', MEM.CHARSET, charset, cmeta));
  // the title picture: a Koala BITMAP in bank 3 (edit it in the bitmap editor)
  const bm = structuredClone(BASE_ASSETS.FRONT_END.meta);
  Object.assign(bm, { bmp_mode: 'MC', bg_col: title.bg, mc_bg: title.bg });
  out.push(asset('AB_TITLE_BMP', 'BITMAP', MEM.TITLE_BMP, [...titleKla], bm));
  // the title's sprite text (TITLE copies it to $C000)
  const tm = structuredClone(BASE_ASSETS.ACTORS.meta);
  Object.assign(tm, { used_count: tspr.count, format: 'RAW', bg_col: title.bg, mc1_col: TITLE_SPR_COLS.mc1, mc2_col: TITLE_SPR_COLS.mc2,
    mc_mode: 1, mc_col1: TITLE_SPR_COLS.mc1, mc_col2: TITLE_SPR_COLS.mc2,
    sprite_mcs: Array(tspr.count).fill(1), sprite_ucs: Array(tspr.count).fill(TITLE_SPR_COLS.individual) });
  if (tm.compositor) tm.compositor = { active_layer: 0, active_frame: 0, active_cell: -1, frames: [{ cells: [] }] };
  out.push(asset('AB_TITLE_SPR', 'SPRITE_SET', TITLE_SPR_AT, tspr.bytes, tm));
  const smeta = structuredClone(BASE_ASSETS.ACTORS.meta);
  Object.assign(smeta, { used_count: sprites.count, format: 'RAW', bg_col: 0, mc1_col: 0, mc2_col: 15, mc_mode: 1, mc_col1: 0, mc_col2: 15,
    sprite_mcs: sprites.mcs, sprite_ucs: sprites.mcs.map((m, i) => i < SPR.ALIEN ? 5 : i < SPR.BOOM ? 10 : i < SPR.BULLET ? 8 : i < SPR.GOO ? 7 : 13) });
  if (smeta.compositor) smeta.compositor = { active_layer: 0, active_frame: 0, active_cell: -1, frames: [{ cells: [] }] };
  out.push(asset('AB_SPRITES', 'SPRITE_SET', MEM.SPRITES, sprites.bytes, smeta));
  for (const d of DATA) out.push(asset(d.name, 'BYTE_DATA', d.address, d.bytes, bmeta(d.bytes)));
  out.push(asset('AB_MUSIC', 'MUSIC_MAKER', 0, [0], buildMusicMeta()));
  out.push(asset('AB_SFX', 'SFX_MAKER', 0, [0], buildSfxMeta()));
  // REU audio: directory + clips (<= 32 KB per asset), at fixed REU addresses
  const links = [];
  out.push(asset('REU_DIR', 'BYTE_DATA', 0xC000, reu.dir, rawMeta(reu.dir.length)));
  links.push({ asset_name: 'REU_DIR', reu_address: REU_DIR, auto_pack: false });
  for (const c of reu.clips) {
    for (let o = 0, part = 0; o < c.bytes.length; o += 0x8000, part++) {
      const chunk = Array.from(c.bytes.subarray(o, o + 0x8000));
      const name = `REU_${c.name.toUpperCase()}_${String(part).padStart(2, '0')}`;
      out.push(asset(name, 'BYTE_DATA', 0xC000, chunk, rawMeta(chunk.length)));
      links.push({ asset_name: name, reu_address: c.start + o, auto_pack: false });
    }
  }
  out.push(asset('AB_REU', 'LOAD_REU', 0, [0], {}, { reu_filename: 'ALIEN_BREED.reu', reu_size: 0x1000000, reu_used: reu.total, linked_assets: links }));
  return out;
}

// nodes: GOLAZO-style ORG columns of CODE BLOCKs + the two macro columns
let uid = 720000;
const nuid = () => ++uid;
const HEIGHT = { ORG: 80, INIT: 80, MACRO_CODE: 100, NORMAL: 60, LABEL: 40, COMMENT: 100, MACRO_SID_SONG: 140, MACRO_SFX: 140 };
const TITLES = { ORG: 'ORG BLOCK', INIT: 'SYSTEM INIT', MACRO_CODE: 'CODE BLOCK', NORMAL: 'Opcode', LABEL: 'ADDRESS LABEL', COMMENT: 'COMMENT' };
function node(type, codeRows, x, y, parent, extra = {}) {
  const n = { binary_blob: '', x, y, type, params: [], custom_title: '', stable_uid: nuid(), wire_in_source: -1, wire_out_target: -1,
    org_uid: -1, show_only_used: false, code_descriptor: type === 'MACRO_CODE' ? 'Code Block' : '', scroll_alias: '', anim_alias: '',
    helper_text: '', comment_h: 0, comment_w: 0, comment_w_mult: 1, x_indent: 0, proxy: false, collapsed: false, end_address: 0,
    pc_address: 0, height: HEIGHT[type] || 100, title: TITLES[type] || type, connected: type !== 'COMMENT', org_parent_x: -1,
    org_parent_y: -1, has_org_parent: false, code: codeRows, ...extra };
  if (parent) Object.assign(n, { has_org_parent: true, org_parent_x: parent[0], org_parent_y: parent[1] });
  return n;
}
const README = `ALIEN BREED 64 - READ ME
An unofficial C64 conversion
pitch of Team17's Alien
Breed (Amiga, 1991), built
in C64 Dev Machine. One
project, two machines:

STOCK C64: SID music from
the Music Maker (AB_MUSIC),
SFX Maker effects (AB_SFX).

C64 ULTIMATE (or any REU):
RUN ON ULTIMATE uploads the
AB_REU image; the title tune
and every effect stream from
the REU as 4-bit samples.
RIGHT on the title (C64U)
picks it.

ASSETS
AB_CHARS   station tiles+font
AB_SPRITES marine, aliens
AB_TITLE_BMP  title picture
AB_TITLE_SPR  its sprite text
DECK_RLE0/1 the two decks
AB_MUSIC / AB_SFX  SID audio
AB_REU     REU audio streams

Rebuild it all with
tools/alienbreed_gen
(node build.mjs).

PLAY: joystick port 2.
Find keys, open doors, use
the Intex terminals, find
the lift. Deck 2: shoot the
4 reactor cores and run.`;
function buildNodes() {
  const nodes = [], orgs = [], boxes = [];
  let orgUid = 1;
  const PITCH = 340, X0 = 700;
  nodes.push(node('COMMENT', [['Comment', README]], X0 - 380, 160, null, { comment_w: 300, custom_title: 'READ ME', title: 'READ ME' }));
  const all = [...COLUMNS.map(c => ({ ...c, kind: 'code' })),
    { name: '13 SFX (SFX MAKER)', kind: 'sfx', org: MEM.SFX_ORG, note: 'SFX - SFX MAKER\nAB_SFX on voice 3 (stock\nC64). One label per effect,\nthe SFX node, RTS. SfxTick\nruns every frame.' },
    { name: '14 MUSIC (MUSIC MAKER)', kind: 'music', org: MEM.MUSIC_ORG, note: 'MUSIC - MUSIC MAKER\nAB_MUSIC: the title theme.\nMusicStart = init (auto),\nthe IRQ calls its play\nlabel every frame.' }];
  all.forEach((col, ci) => {
    const x = X0 + ci * PITCH;
    let y = 340;
    nodes.push(node('COMMENT', [['Comment', col.note]], x, 160, null, { custom_title: col.note.split('\n')[0], title: col.note.split('\n')[0] }));
    let parent = null;
    if (col.org === null) {
      nodes.push(node('INIT', INIT_ROWS, x, y));
      y += 80;
    } else {
      const o = node('ORG', [['org', 0]], x, y, null, { pc_address: col.org, org_uid: orgUid++, connected: false });
      orgs.push(o); parent = [x, y]; y += 80;
    }
    const add = (n) => { nodes.push(n); y += n.height; };
    if (col.kind === 'code') {
      for (const [name] of col.blocks)
        add(node('MACRO_CODE', [['code_block', col.resolved[name]]], x, y, parent, { custom_title: name, title: name }));
    } else if (col.kind === 'sfx') {
      const seq = [['SfxInit', 0, 3], ['SfxTick', 0, 1], ...SFX_LABELS.map((l, i) => [l, i, 0])];
      for (const [label, idx, mode] of seq) {
        add(node('LABEL', [['label', label]], x, y, parent, { title: label }));
        add(node('MACRO_SFX', [['macro_sfx', 'AB_SFX', idx, 3, mode]], x, y, parent, { title: label.replace(/^Sfx/, 'SFX ').toUpperCase() }));
        add(node('NORMAL', [['rts', 0]], x, y, parent));
      }
    } else {
      add(node('LABEL', [['label', 'MusicStart']], x, y, parent, { title: 'MusicStart' }));
      const s = node('MACRO_SID_SONG', [['macro_sid_song', 'AB_MUSIC', 1, 3, 2, 0]], x, y, parent, { title: 'TITLE THEME' });
      s.stable_uid = K.SONG_UID;
      add(s);
      add(node('NORMAL', [['rts', 0]], x, y, parent));
    }
    boxes.push({ x: x - 20, y: 120, panel_links: [], is_panel: false, box_col_idx: ci % 10, box_name: col.name, box_h: y - 120 + 40, box_w: 300 });
  });
  boxes.push({ x: X0 - 400, y: 120, panel_links: [], is_panel: false, box_col_idx: 3, box_name: 'ALIEN BREED 64', box_h: 760, box_w: 340 });
  return { nodes: [...orgs, ...nodes], boxes };
}
const { nodes, boxes } = buildNodes();
if (uid >= K.SONG_UID && uid < K.SONG_UID + 100) throw new Error('uid clash');
const project = {
  asset_groups: [GROUP], asset_sort_mode: 'ADDR', ignored_conflicts: [], next_stable_uid: uid + 10, map_tile_bank_sel: -1,
  map_tile_bank: [], code_editor_font_index: 1, map_global_mixed: 1, kernal_unlocked: true, basic_unlocked: true,
  creator_locked: false, build_target: 0, nodes, boxes, assets: buildAssets(),
};
fs.writeFileSync(outJson, JSON.stringify(project));
console.log('wrote %s: %d nodes, %d assets, %d KB', outJson, nodes.length, project.assets.length, Math.round(fs.statSync(outJson).size / 1024));
void SPR_PTR0;
