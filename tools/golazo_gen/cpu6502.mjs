// Small NMOS 6502 core (official opcodes) with cycle counting, for unit
// tests and headless match simulation. Memory is a flat 64K array; I/O is
// whatever the test pokes into it.
const MODES = {};   // opcode -> [mnemonic, mode, cycles]
const T = (mn, list) => { for (const [op, mode, cyc] of list) MODES[op] = [mn, mode, cyc]; };
T('ADC', [[0x69, 'imm', 2], [0x65, 'zp', 3], [0x75, 'zpx', 4], [0x6D, 'abs', 4], [0x7D, 'abx', 4], [0x79, 'aby', 4], [0x61, 'izx', 6], [0x71, 'izy', 5]]);
T('AND', [[0x29, 'imm', 2], [0x25, 'zp', 3], [0x35, 'zpx', 4], [0x2D, 'abs', 4], [0x3D, 'abx', 4], [0x39, 'aby', 4], [0x21, 'izx', 6], [0x31, 'izy', 5]]);
T('ASL', [[0x0A, 'acc', 2], [0x06, 'zp', 5], [0x16, 'zpx', 6], [0x0E, 'abs', 6], [0x1E, 'abxw', 7]]);
T('BIT', [[0x24, 'zp', 3], [0x2C, 'abs', 4]]);
for (const [mn, op] of [['BPL', 0x10], ['BMI', 0x30], ['BVC', 0x50], ['BVS', 0x70], ['BCC', 0x90], ['BCS', 0xB0], ['BNE', 0xD0], ['BEQ', 0xF0]]) T(mn, [[op, 'rel', 2]]);
T('BRK', [[0x00, 'imp', 7]]);
T('CMP', [[0xC9, 'imm', 2], [0xC5, 'zp', 3], [0xD5, 'zpx', 4], [0xCD, 'abs', 4], [0xDD, 'abx', 4], [0xD9, 'aby', 4], [0xC1, 'izx', 6], [0xD1, 'izy', 5]]);
T('CPX', [[0xE0, 'imm', 2], [0xE4, 'zp', 3], [0xEC, 'abs', 4]]);
T('CPY', [[0xC0, 'imm', 2], [0xC4, 'zp', 3], [0xCC, 'abs', 4]]);
T('DEC', [[0xC6, 'zp', 5], [0xD6, 'zpx', 6], [0xCE, 'abs', 6], [0xDE, 'abxw', 7]]);
T('EOR', [[0x49, 'imm', 2], [0x45, 'zp', 3], [0x55, 'zpx', 4], [0x4D, 'abs', 4], [0x5D, 'abx', 4], [0x59, 'aby', 4], [0x41, 'izx', 6], [0x51, 'izy', 5]]);
for (const [mn, op] of [['CLC', 0x18], ['SEC', 0x38], ['CLI', 0x58], ['SEI', 0x78], ['CLV', 0xB8], ['CLD', 0xD8], ['SED', 0xF8],
  ['TAX', 0xAA], ['TXA', 0x8A], ['DEX', 0xCA], ['INX', 0xE8], ['TAY', 0xA8], ['TYA', 0x98], ['DEY', 0x88], ['INY', 0xC8],
  ['TXS', 0x9A], ['TSX', 0xBA], ['NOP', 0xEA]]) T(mn, [[op, 'imp', 2]]);
T('PHA', [[0x48, 'imp', 3]]); T('PHP', [[0x08, 'imp', 3]]); T('PLA', [[0x68, 'imp', 4]]); T('PLP', [[0x28, 'imp', 4]]);
T('INC', [[0xE6, 'zp', 5], [0xF6, 'zpx', 6], [0xEE, 'abs', 6], [0xFE, 'abxw', 7]]);
T('JMP', [[0x4C, 'abs', 3], [0x6C, 'ind', 5]]);
T('JSR', [[0x20, 'abs', 6]]);
T('LDA', [[0xA9, 'imm', 2], [0xA5, 'zp', 3], [0xB5, 'zpx', 4], [0xAD, 'abs', 4], [0xBD, 'abx', 4], [0xB9, 'aby', 4], [0xA1, 'izx', 6], [0xB1, 'izy', 5]]);
T('LDX', [[0xA2, 'imm', 2], [0xA6, 'zp', 3], [0xB6, 'zpy', 4], [0xAE, 'abs', 4], [0xBE, 'aby', 4]]);
T('LDY', [[0xA0, 'imm', 2], [0xA4, 'zp', 3], [0xB4, 'zpx', 4], [0xAC, 'abs', 4], [0xBC, 'abx', 4]]);
T('LSR', [[0x4A, 'acc', 2], [0x46, 'zp', 5], [0x56, 'zpx', 6], [0x4E, 'abs', 6], [0x5E, 'abxw', 7]]);
T('ORA', [[0x09, 'imm', 2], [0x05, 'zp', 3], [0x15, 'zpx', 4], [0x0D, 'abs', 4], [0x1D, 'abx', 4], [0x19, 'aby', 4], [0x01, 'izx', 6], [0x11, 'izy', 5]]);
T('ROL', [[0x2A, 'acc', 2], [0x26, 'zp', 5], [0x36, 'zpx', 6], [0x2E, 'abs', 6], [0x3E, 'abxw', 7]]);
T('ROR', [[0x6A, 'acc', 2], [0x66, 'zp', 5], [0x76, 'zpx', 6], [0x6E, 'abs', 6], [0x7E, 'abxw', 7]]);
T('RTI', [[0x40, 'imp', 6]]); T('RTS', [[0x60, 'imp', 6]]);
T('SBC', [[0xE9, 'imm', 2], [0xE5, 'zp', 3], [0xF5, 'zpx', 4], [0xED, 'abs', 4], [0xFD, 'abx', 4], [0xF9, 'aby', 4], [0xE1, 'izx', 6], [0xF1, 'izy', 5]]);
T('STA', [[0x85, 'zp', 3], [0x95, 'zpx', 4], [0x8D, 'abs', 4], [0x9D, 'abxw', 5], [0x99, 'abyw', 5], [0x81, 'izx', 6], [0x91, 'izyw', 6]]);
T('STX', [[0x86, 'zp', 3], [0x96, 'zpy', 4], [0x8E, 'abs', 4]]);
T('STY', [[0x84, 'zp', 3], [0x94, 'zpx', 4], [0x8C, 'abs', 4]]);

export class CPU {
  constructor(mem) {
    this.m = mem || new Uint8Array(65536);
    this.a = this.x = this.y = 0; this.sp = 0xFF; this.pc = 0;
    this.c = this.z = this.i = this.d = this.v = this.n = 0;
    this.cycles = 0; this.onRead = null; this.onWrite = null; this.trace = null;
  }
  rd(a) { return this.onRead ? this.onRead(a & 0xffff) : this.m[a & 0xffff]; }
  wr(a, v) { if (this.onWrite && this.onWrite(a & 0xffff, v & 255)) return; this.m[a & 0xffff] = v & 255; }
  w16(a) { return this.rd(a) | (this.rd(a + 1) << 8); }
  push(v) { this.m[0x100 + this.sp] = v & 255; this.sp = (this.sp - 1) & 255; }
  pop() { this.sp = (this.sp + 1) & 255; return this.m[0x100 + this.sp]; }
  nz(v) { v &= 255; this.z = v === 0 ? 1 : 0; this.n = v >> 7; return v; }
  getP() { return this.c | (this.z << 1) | (this.i << 2) | (this.d << 3) | 0x30 | (this.v << 6) | (this.n << 7); }
  setP(p) { this.c = p & 1; this.z = (p >> 1) & 1; this.i = (p >> 2) & 1; this.d = (p >> 3) & 1; this.v = (p >> 6) & 1; this.n = (p >> 7) & 1; }
  // run a subroutine until it returns; returns cycles used
  call(addr, maxCycles = 2e6) {
    const c0 = this.cycles;
    this.push(0xFF); this.push(0xFE);       // return to $FFFF
    this.pc = addr;
    while (this.pc !== 0xFFFF) {
      this.step();
      if (this.cycles - c0 > maxCycles) throw new Error('runaway at $' + this.pc.toString(16));
    }
    return this.cycles - c0;
  }
  step() {
    const pc0 = this.pc;
    const op = this.rd(this.pc);
    const e = MODES[op];
    if (!e) throw new Error(`illegal opcode $${op.toString(16)} at $${pc0.toString(16)}`);
    if (this.trace) this.trace(this, pc0, e[0]);
    const [mn, mode, cyc] = e;
    this.pc = (this.pc + 1) & 0xffff;
    let addr = 0, extra = 0;
    const b = () => { const v = this.rd(this.pc); this.pc = (this.pc + 1) & 0xffff; return v; };
    const w = () => { const v = this.w16(this.pc); this.pc = (this.pc + 2) & 0xffff; return v; };
    switch (mode) {
      case 'imm': addr = this.pc; this.pc = (this.pc + 1) & 0xffff; break;
      case 'zp': addr = b(); break;
      case 'zpx': addr = (b() + this.x) & 255; break;
      case 'zpy': addr = (b() + this.y) & 255; break;
      case 'abs': addr = w(); break;
      case 'abx': { const base = w(); addr = (base + this.x) & 0xffff; if ((base & 0xff00) !== (addr & 0xff00)) extra = 1; break; }
      case 'aby': { const base = w(); addr = (base + this.y) & 0xffff; if ((base & 0xff00) !== (addr & 0xff00)) extra = 1; break; }
      case 'abxw': addr = (w() + this.x) & 0xffff; break;
      case 'abyw': addr = (w() + this.y) & 0xffff; break;
      case 'izx': { const zp = (b() + this.x) & 255; addr = this.m[zp] | (this.m[(zp + 1) & 255] << 8); break; }
      case 'izy': { const zp = b(); const base = this.m[zp] | (this.m[(zp + 1) & 255] << 8); addr = (base + this.y) & 0xffff; if ((base & 0xff00) !== (addr & 0xff00)) extra = 1; break; }
      case 'izyw': { const zp = b(); addr = ((this.m[zp] | (this.m[(zp + 1) & 255] << 8)) + this.y) & 0xffff; break; }
      case 'ind': { const p = w(); addr = this.rd(p) | (this.rd((p & 0xff00) | ((p + 1) & 255)) << 8); break; }
      case 'rel': { let d = b(); if (d > 127) d -= 256; addr = (this.pc + d) & 0xffff; break; }
    }
    this.cycles += cyc + extra;
    const rmw = f => { if (mode === 'acc') { this.a = this.nz(f(this.a)); } else { const v = f(this.rd(addr)); this.wr(addr, v); this.nz(v); } };
    const br = cond => { if (cond) { this.cycles += 1 + ((addr & 0xff00) !== (this.pc & 0xff00) ? 1 : 0); this.pc = addr; } };
    switch (mn) {
      case 'LDA': this.a = this.nz(this.rd(addr)); break;
      case 'LDX': this.x = this.nz(this.rd(addr)); break;
      case 'LDY': this.y = this.nz(this.rd(addr)); break;
      case 'STA': this.wr(addr, this.a); break;
      case 'STX': this.wr(addr, this.x); break;
      case 'STY': this.wr(addr, this.y); break;
      case 'ADC': { const v = this.rd(addr); const r = this.a + v + this.c; this.v = (~(this.a ^ v) & (this.a ^ r) & 0x80) ? 1 : 0; this.c = r > 255 ? 1 : 0; this.a = this.nz(r); break; }
      case 'SBC': { const v = this.rd(addr); const r = this.a - v - (1 - this.c); this.v = ((this.a ^ v) & (this.a ^ r) & 0x80) ? 1 : 0; this.c = r >= 0 ? 1 : 0; this.a = this.nz(r); break; }
      case 'AND': this.a = this.nz(this.a & this.rd(addr)); break;
      case 'ORA': this.a = this.nz(this.a | this.rd(addr)); break;
      case 'EOR': this.a = this.nz(this.a ^ this.rd(addr)); break;
      case 'CMP': { const v = this.rd(addr); this.c = this.a >= v ? 1 : 0; this.nz(this.a - v); break; }
      case 'CPX': { const v = this.rd(addr); this.c = this.x >= v ? 1 : 0; this.nz(this.x - v); break; }
      case 'CPY': { const v = this.rd(addr); this.c = this.y >= v ? 1 : 0; this.nz(this.y - v); break; }
      case 'BIT': { const v = this.rd(addr); this.z = (this.a & v) === 0 ? 1 : 0; this.n = v >> 7; this.v = (v >> 6) & 1; break; }
      case 'ASL': rmw(v => { this.c = v >> 7; return (v << 1) & 255; }); break;
      case 'LSR': rmw(v => { this.c = v & 1; return v >> 1; }); break;
      case 'ROL': rmw(v => { const c = this.c; this.c = v >> 7; return ((v << 1) | c) & 255; }); break;
      case 'ROR': rmw(v => { const c = this.c; this.c = v & 1; return (v >> 1) | (c << 7); }); break;
      case 'INC': rmw(v => (v + 1) & 255); break;
      case 'DEC': rmw(v => (v - 1) & 255); break;
      case 'INX': this.x = this.nz(this.x + 1); break;
      case 'INY': this.y = this.nz(this.y + 1); break;
      case 'DEX': this.x = this.nz(this.x - 1); break;
      case 'DEY': this.y = this.nz(this.y - 1); break;
      case 'TAX': this.x = this.nz(this.a); break;
      case 'TAY': this.y = this.nz(this.a); break;
      case 'TXA': this.a = this.nz(this.x); break;
      case 'TYA': this.a = this.nz(this.y); break;
      case 'TSX': this.x = this.nz(this.sp); break;
      case 'TXS': this.sp = this.x; break;
      case 'PHA': this.push(this.a); break;
      case 'PHP': this.push(this.getP()); break;
      case 'PLA': this.a = this.nz(this.pop()); break;
      case 'PLP': this.setP(this.pop()); break;
      case 'CLC': this.c = 0; break; case 'SEC': this.c = 1; break;
      case 'CLI': this.i = 0; break; case 'SEI': this.i = 1; break;
      case 'CLV': this.v = 0; break; case 'CLD': this.d = 0; break; case 'SED': this.d = 1; break;
      case 'NOP': break;
      case 'JMP': this.pc = addr; break;
      case 'JSR': { const r = (this.pc - 1) & 0xffff; this.push(r >> 8); this.push(r & 255); this.pc = addr; break; }
      case 'RTS': { const lo = this.pop(), hi = this.pop(); this.pc = ((hi << 8) | lo) + 1 & 0xffff; break; }
      case 'RTI': { this.setP(this.pop()); const lo = this.pop(), hi = this.pop(); this.pc = (hi << 8) | lo; break; }
      case 'BPL': br(!this.n); break; case 'BMI': br(this.n); break;
      case 'BVC': br(!this.v); break; case 'BVS': br(this.v); break;
      case 'BCC': br(!this.c); break; case 'BCS': br(this.c); break;
      case 'BNE': br(!this.z); break; case 'BEQ': br(this.z); break;
      case 'BRK': throw new Error('BRK at $' + pc0.toString(16));
    }
    if (this.d && (mn === 'ADC' || mn === 'SBC')) throw new Error('decimal mode used at $' + pc0.toString(16));
  }
}
