// Tiny two-pass 6502 assembler for the CODE BLOCK syntax the Dev Machine
// accepts, plus a resolver that turns symbolic source (constants, simple
// expressions) into that plain syntax.
//
//   resolve(text, consts)  -> editor text: constants folded to hex, code
//                             labels left as labels (JSR/JMP/branches,
//                             abs/abs,X/abs,Y and #</#> on LDA/LDX/LDY only)
//   new Assembler().addBlock(text, org) ... link() -> Map(addr -> byte)

const OPS = {
  ADC: { imm: 0x69, zp: 0x65, zpx: 0x75, abs: 0x6D, abx: 0x7D, aby: 0x79, izx: 0x61, izy: 0x71 },
  AND: { imm: 0x29, zp: 0x25, zpx: 0x35, abs: 0x2D, abx: 0x3D, aby: 0x39, izx: 0x21, izy: 0x31 },
  ASL: { acc: 0x0A, zp: 0x06, zpx: 0x16, abs: 0x0E, abx: 0x1E },
  BIT: { zp: 0x24, abs: 0x2C },
  BPL: { rel: 0x10 }, BMI: { rel: 0x30 }, BVC: { rel: 0x50 }, BVS: { rel: 0x70 },
  BCC: { rel: 0x90 }, BCS: { rel: 0xB0 }, BNE: { rel: 0xD0 }, BEQ: { rel: 0xF0 },
  BRK: { imp: 0x00 },
  CMP: { imm: 0xC9, zp: 0xC5, zpx: 0xD5, abs: 0xCD, abx: 0xDD, aby: 0xD9, izx: 0xC1, izy: 0xD1 },
  CPX: { imm: 0xE0, zp: 0xE4, abs: 0xEC },
  CPY: { imm: 0xC0, zp: 0xC4, abs: 0xCC },
  DEC: { zp: 0xC6, zpx: 0xD6, abs: 0xCE, abx: 0xDE },
  EOR: { imm: 0x49, zp: 0x45, zpx: 0x55, abs: 0x4D, abx: 0x5D, aby: 0x59, izx: 0x41, izy: 0x51 },
  CLC: { imp: 0x18 }, SEC: { imp: 0x38 }, CLI: { imp: 0x58 }, SEI: { imp: 0x78 },
  CLV: { imp: 0xB8 }, CLD: { imp: 0xD8 }, SED: { imp: 0xF8 },
  INC: { zp: 0xE6, zpx: 0xF6, abs: 0xEE, abx: 0xFE },
  JMP: { abs: 0x4C, ind: 0x6C },
  JSR: { abs: 0x20 },
  LDA: { imm: 0xA9, zp: 0xA5, zpx: 0xB5, abs: 0xAD, abx: 0xBD, aby: 0xB9, izx: 0xA1, izy: 0xB1 },
  LDX: { imm: 0xA2, zp: 0xA6, zpy: 0xB6, abs: 0xAE, aby: 0xBE },
  LDY: { imm: 0xA0, zp: 0xA4, zpx: 0xB4, abs: 0xAC, abx: 0xBC },
  LSR: { acc: 0x4A, zp: 0x46, zpx: 0x56, abs: 0x4E, abx: 0x5E },
  NOP: { imp: 0xEA },
  ORA: { imm: 0x09, zp: 0x05, zpx: 0x15, abs: 0x0D, abx: 0x1D, aby: 0x19, izx: 0x01, izy: 0x11 },
  TAX: { imp: 0xAA }, TXA: { imp: 0x8A }, DEX: { imp: 0xCA }, INX: { imp: 0xE8 },
  TAY: { imp: 0xA8 }, TYA: { imp: 0x98 }, DEY: { imp: 0x88 }, INY: { imp: 0xC8 },
  ROL: { acc: 0x2A, zp: 0x26, zpx: 0x36, abs: 0x2E, abx: 0x3E },
  ROR: { acc: 0x6A, zp: 0x66, zpx: 0x76, abs: 0x6E, abx: 0x7E },
  RTI: { imp: 0x40 }, RTS: { imp: 0x60 },
  SBC: { imm: 0xE9, zp: 0xE5, zpx: 0xF5, abs: 0xED, abx: 0xFD, aby: 0xF9, izx: 0xE1, izy: 0xF1 },
  STA: { zp: 0x85, zpx: 0x95, abs: 0x8D, abx: 0x9D, aby: 0x99, izx: 0x81, izy: 0x91 },
  TXS: { imp: 0x9A }, TSX: { imp: 0xBA }, PHA: { imp: 0x48 }, PLA: { imp: 0x68 },
  PHP: { imp: 0x08 }, PLP: { imp: 0x28 },
  STX: { zp: 0x86, zpy: 0x96, abs: 0x8E },
  STY: { zp: 0x84, zpx: 0x94, abs: 0x8C },
};
const SIZE = { imp: 1, acc: 1, imm: 2, zp: 2, zpx: 2, zpy: 2, izx: 2, izy: 2, rel: 2, abs: 3, abx: 3, aby: 3, ind: 3 };
export const OPCODES = OPS;

export class AsmError extends Error {}

function num(s) {
  s = s.trim();
  if (/^\$[0-9a-fA-F]+$/.test(s)) return parseInt(s.slice(1), 16);
  if (/^%[01]+$/.test(s)) return parseInt(s.slice(1), 2);
  if (/^[0-9]+$/.test(s)) return parseInt(s, 10);
  return null;
}

export function stripComment(line) {
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') inStr = !inStr;
    if (!inStr && (ch === ';' || line.startsWith('//', i))) return line.slice(0, i);
  }
  return line;
}

// ---------------------------------------------------------------- resolver
// Evaluate an expression of numbers and constants: + - * / & | << >> and
// parentheses, unary < > (lo/hi) and -. Returns null if it names anything
// that is not a constant.
function evalConst(expr, consts) {
  const toks = expr.match(/\$[0-9a-fA-F]+|%[01]+|[0-9]+|[A-Za-z_][A-Za-z0-9_]*|<<|>>|[-+*/&|()<>^]/g);
  if (!toks || toks.join('') !== expr.replace(/\s+/g, '')) return null;
  let i = 0;
  const peek = () => toks[i];
  function prim() {
    const t = toks[i++];
    if (t === undefined) throw new AsmError('bad expression ' + expr);
    if (t === '(') { const v = or(); if (toks[i++] !== ')') throw new AsmError('missing ) in ' + expr); return v; }
    if (t === '-') return -prim();
    if (t === '<') return prim() & 255;
    if (t === '>') return (prim() >> 8) & 255;
    const n = num(t);
    if (n !== null) return n;
    if (Object.prototype.hasOwnProperty.call(consts, t)) return consts[t];
    throw { notConst: t };
  }
  function mul() { let v = prim(); while (peek() === '*' || peek() === '/') { const o = toks[i++]; const r = prim(); v = o === '*' ? v * r : Math.floor(v / r); } return v; }
  function add() { let v = mul(); while (peek() === '+' || peek() === '-') { const o = toks[i++]; const r = mul(); v = o === '+' ? v + r : v - r; } return v; }
  function sh() { let v = add(); while (peek() === '<<' || peek() === '>>') { const o = toks[i++]; const r = add(); v = o === '<<' ? v << r : v >> r; } return v; }
  function and() { let v = sh(); while (peek() === '&') { i++; v &= sh(); } return v; }
  function or() { let v = and(); while (peek() === '|' || peek() === '^') { const o = toks[i++]; const r = and(); v = o === '|' ? v | r : v ^ r; } return v; }
  try {
    const v = or();
    if (i !== toks.length) throw new AsmError('trailing tokens in ' + expr);
    return v;
  } catch (e) {
    if (e && e.notConst) return null;
    throw e;
  }
}

const hex2 = v => '$' + (v & 255).toString(16).toUpperCase().padStart(2, '0');
const hex4 = v => '$' + (v & 0xffff).toString(16).toUpperCase().padStart(4, '0');
const isLabel = s => /^[A-Za-z_][A-Za-z0-9_]*$/.test(s);

// ZP constants are the ones whose name starts with Z_ (or the value is
// written as a 2-digit literal); everything else resolves to 4 digits.
function fmtAddr(expr, v, consts) {
  if (v < 0 || v > 0xffff) throw new AsmError('address out of range: ' + expr + ' = ' + v);
  const zpName = /^Z_[A-Z0-9_]+$/.test(expr.trim()) || /^Z_[A-Z0-9_]+\s*\+\s*[0-9$]+$/.test(expr.trim());
  const lit2 = /^\$[0-9a-fA-F]{1,2}$/.test(expr.trim());
  if ((zpName || lit2) && v < 256) return hex2(v);
  return hex4(v);
}

export function resolve(text, consts, where = '') {
  const out = [];
  const lines = text.split('\n');
  for (let ln = 0; ln < lines.length; ln++) {
    const raw = lines[ln];
    // asset dependency lines are kept: the editor emits assets they name
    if (/^\s*\/\/\s*@asset\s+\S+/.test(raw)) { out.push('// @asset ' + raw.split('@asset')[1].trim()); continue; }
    let line = stripComment(raw).trim();
    if (!line) continue;
    let label = '';
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
    if (m) { label = m[1] + ':'; line = m[2].trim(); if (!line) { out.push(label); continue; } }
    if (/^\.byte\b/i.test(line)) {
      const vals = line.slice(5).split(',').map(s => s.trim()).filter(Boolean).map(s => {
        const v = evalConst(s, consts);
        if (v === null) throw new AsmError(`${where}:${ln + 1} .byte needs constants: ${raw}`);
        return hex2(v);
      });
      for (let i = 0; i < vals.length; i += 16)
        out.push((i === 0 ? label : '') + '.byte ' + vals.slice(i, i + 16).join(','));
      continue;
    }
    const parts = line.split(/\s+/);
    const mn = parts[0].toUpperCase();
    if (!OPS[mn]) throw new AsmError(`${where}:${ln + 1} unknown mnemonic: ${raw}`);
    let op = parts.slice(1).join('').trim();
    let res = '';
    if (op === '' || op.toUpperCase() === 'A') res = '';
    else if (OPS[mn].rel || mn === 'JSR' || (mn === 'JMP' && !op.startsWith('('))) {
      const v = evalConst(op, consts);
      if (v === null) {
        if (!isLabel(op)) throw new AsmError(`${where}:${ln + 1} label arithmetic not allowed: ${raw}`);
        res = op;
      } else res = hex4(v);
    } else if (op.startsWith('#')) {
      let e = op.slice(1);
      const v = evalConst(e, consts);
      if (v === null) {
        const lh = e.match(/^([<>])([A-Za-z_][A-Za-z0-9_]*)$/);
        if (!lh || !['LDA', 'LDX', 'LDY'].includes(mn))
          throw new AsmError(`${where}:${ln + 1} immediate must be constant (or #</#> label on LDA/LDX/LDY): ${raw}`);
        res = '#' + e;
      } else {
        if (v < -128 || v > 255) throw new AsmError(`${where}:${ln + 1} immediate out of range: ${raw} (${v})`);
        res = '#' + hex2(v & 255);
      }
    } else {
      let pre = '', post = '', e = op;
      let mm;
      if ((mm = op.match(/^\((.*)\),Y$/i))) { pre = '('; post = '),Y'; e = mm[1]; }
      else if ((mm = op.match(/^\((.*),X\)$/i))) { pre = '('; post = ',X)'; e = mm[1]; }
      else if ((mm = op.match(/^\((.*)\)$/))) { pre = '('; post = ')'; e = mm[1]; }
      else if ((mm = op.match(/^(.*),([XY])$/i))) { post = ',' + mm[2].toUpperCase(); e = mm[1]; }
      const v = evalConst(e, consts);
      if (v === null) {
        if (!isLabel(e)) throw new AsmError(`${where}:${ln + 1} label arithmetic not allowed: ${raw}`);
        res = pre + e + post;
      } else if (pre) {
        if (post === ')') res = pre + hex4(v) + post;
        else { if (v > 255) throw new AsmError(`${where}:${ln + 1} indirect needs zp: ${raw}`); res = pre + hex2(v) + post; }
      } else res = fmtAddr(e, v, consts) + post;
    }
    out.push(label + mn + (res ? ' ' + res : ''));
  }
  return out.join('\n');
}

// ---------------------------------------------------------------- assembler
export class Assembler {
  constructor() { this.labels = {}; this.items = []; this.pc = 0; }

  parse(text, where) {
    const out = [];
    text.split('\n').forEach((raw, ln) => {
      let line = stripComment(raw).trim();
      if (!line) return;
      const m = line.match(/^\.?([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$/);
      if (m) { out.push(['label', m[1], where, ln]); line = m[2].trim(); if (!line) return; }
      if (/^\.byte/i.test(line)) {
        out.push(['byte', line.slice(5).split(',').map(s => s.trim()).filter(Boolean), where, ln]);
        return;
      }
      const parts = line.split(/\s+/);
      const mn = parts[0].toUpperCase();
      const op = parts.slice(1).join('');
      if (!OPS[mn]) throw new AsmError(`${where}:${ln + 1} unknown mnemonic ${raw}`);
      out.push(['ins', mn, op, where, ln]);
    });
    return out;
  }

  mode(mn, op) {
    const modes = OPS[mn];
    if (op === '' || op.toUpperCase() === 'A') return [modes.acc !== undefined ? 'acc' : 'imp', null];
    if (modes.rel !== undefined) return ['rel', op];
    if (op.startsWith('#')) return ['imm', op.slice(1)];
    const U = op.toUpperCase();
    if (op.startsWith('(') && U.endsWith('),Y')) return ['izy', op.slice(1, -3)];
    if (op.startsWith('(') && U.endsWith(',X)')) return ['izx', op.slice(1, -3)];
    if (op.startsWith('(') && op.endsWith(')')) return ['ind', op.slice(1, -1)];
    let idx = null;
    if (U.endsWith(',X')) { idx = 'x'; op = op.slice(0, -2); }
    else if (U.endsWith(',Y')) { idx = 'y'; op = op.slice(0, -2); }
    const v = num(op);
    const zp = v !== null && v <= 255 && op.startsWith('$') && op.length <= 3;
    let m;
    if (idx === null) m = zp && modes.zp !== undefined ? 'zp' : 'abs';
    else if (idx === 'x') m = zp && modes.zpx !== undefined ? 'zpx' : 'abx';
    else m = zp && modes.zpy !== undefined ? 'zpy' : 'aby';
    return [m, op];
  }

  addBlock(text, org = null, where = '') {
    if (org !== null) this.pc = org;
    for (const it of this.parse(text, where)) {
      if (it[0] === 'label') {
        const name = it[1];
        if (name in this.labels && this.labels[name] !== this.pc) throw new AsmError(`duplicate label ${name} (${where})`);
        this.labels[name] = this.pc;
      } else if (it[0] === 'byte') {
        this.items.push([this.pc, 'byte', it[1], it[2], it[3]]);
        this.pc += it[1].length;
      } else {
        const [, mn, op, w, ln] = it;
        const [m, arg] = this.mode(mn, op);
        if (OPS[mn][m] === undefined) throw new AsmError(`${w}:${ln + 1} bad mode ${mn} ${op}`);
        this.items.push([this.pc, 'ins', [mn, m, arg], w, ln]);
        this.pc += SIZE[m];
      }
    }
  }

  value(expr, w, ln) {
    expr = expr.trim();
    let lohi = null;
    if (expr[0] === '<' || expr[0] === '>') { lohi = expr[0]; expr = expr.slice(1); }
    let total = 0, sign = 1;
    for (const tok of expr.match(/[+-]|[^+-]+/g)) {
      if (tok === '+') { sign = 1; continue; }
      if (tok === '-') { sign = -1; continue; }
      let v = num(tok);
      if (v === null) {
        if (!(tok in this.labels)) throw new AsmError(`${w}:${ln + 1} unresolved label ${tok}`);
        v = this.labels[tok];
      }
      total += sign * v;
    }
    if (lohi === '<') return total & 255;
    if (lohi === '>') return (total >> 8) & 255;
    return total;
  }

  link() {
    const mem = new Map();
    const put = (a, v) => { if (mem.has(a)) throw new AsmError('code overlaps itself at $' + a.toString(16)); mem.set(a, v & 255); };
    for (const [addr, kind, data, w, ln] of this.items) {
      if (kind === 'byte') { data.forEach((v, i) => put(addr + i, this.value(v, w, ln))); continue; }
      const [mn, m, arg] = data;
      put(addr, OPS[mn][m]);
      if (SIZE[m] === 1) continue;
      const v = this.value(arg, w, ln);
      if (m === 'rel') {
        const d = v - (addr + 2);
        if (d < -128 || d > 127) throw new AsmError(`${w}:${ln + 1} branch out of range (${d}) to ${arg}`);
        put(addr + 1, d);
      } else if (SIZE[m] === 2) {
        if (m !== 'imm' && v > 255) throw new AsmError(`${w}:${ln + 1} zp operand > 255`);
        put(addr + 1, v);
      } else { put(addr + 1, v); put(addr + 2, v >> 8); }
    }
    return mem;
  }
}
