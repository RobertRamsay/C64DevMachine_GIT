// A small C64 for headless tests: GOLAZO's 6502 core plus the parts the
// game leans on - raster line counter + raster IRQ, CIA 2 timer A NMI, a
// 17xx REU (DMA), joystick port 2 - and a log of SID writes.
//
//   node machine.mjs PRG seconds [--reu image] [--script joy.json]
// prints SID activity per second: $D418 writes (digi samples), gate-on
// notes per voice, and whether the frame IRQ kept running.
import fs from 'fs';
import { CPU } from '../golazo_gen/cpu6502.mjs';

const CYC_LINE = 63, LINES = 312, CYC_FRAME = CYC_LINE * LINES;

export class Machine {
  constructor(prgFile, { reu = null, script = null } = {}) {
    const prg = fs.readFileSync(prgFile);
    this.mem = new Uint8Array(65536);
    this.mem.set(prg.subarray(2), prg[0] | prg[1] << 8);
    this.cpu = new CPU(this.mem);
    this.cpu.decimal = true;
    this.reu = reu ? new Uint8Array(fs.readFileSync(reu)) : null;
    this.r = new Uint8Array(16);           // REU registers $DF00-$DF0F
    this.rasterCmp = 0; this.irqOn = 0; this.irqFlag = 0;
    this.nmiLatch = 0xFFFF; this.nmiRun = false; this.nmiNext = 0; this.nmiMask = 0; this.nmiFlag = 0;
    this.log = { d418: 0, notes: [0, 0, 0], frames: 0, nmi: 0, dma: 0 };
    this.script = script; this.sp = 0; this.left = 0; this.joy = 0;
    const m = this.mem;
    this.cpu.onRead = a => {
      if (a === 0xD012) return this.line() & 255;
      if (a === 0xD011) return (m[a] & 0x7F) | ((this.line() & 0x100) >> 1);
      if (a === 0xD019) return this.irqFlag | (this.irqFlag ? 0x80 : 0);
      if (a === 0xDC00) return (~this.joy) & 0xFF;
      if (a === 0xDD0D) { const v = this.nmiFlag ? 0x81 : 0; this.nmiFlag = 0; return v; }
      if (a >= 0xDF00 && a <= 0xDF0F) return this.reu ? (a === 0xDF00 ? 0x10 : this.r[a - 0xDF00]) : 0xFF;
      return m[a];
    };
    this.cpu.onWrite = (a, v) => {
      if (a === 0xD012) { this.rasterCmp = (this.rasterCmp & 0x100) | v; return false; }
      if (a === 0xD011) { this.rasterCmp = (this.rasterCmp & 0xFF) | ((v & 0x80) << 1); }
      if (a === 0xD01A) this.irqOn = v & 1;
      if (a === 0xD019) { this.irqFlag &= ~v & 1; return true; }
      if (a === 0xD418) this.log.d418++;
      if (a >= 0xD400 && a <= 0xD414 && (a - 0xD400) % 7 === 4 && (v & 1) && !(m[a] & 1)) this.log.notes[(a - 0xD400) / 7]++;
      if (a === 0xDD04) this.nmiLatch = (this.nmiLatch & 0xFF00) | v;
      if (a === 0xDD05) this.nmiLatch = (this.nmiLatch & 0xFF) | (v << 8);
      if (a === 0xDD0D) { if (v & 0x80) this.nmiMask |= v & 0x7F; else this.nmiMask &= ~v; }
      if (a === 0xDD0E) { this.nmiRun = !!(v & 1); if (v & 0x10) this.nmiNext = this.cpu.cycles + this.nmiLatch + 1; }
      if (this.reu && a >= 0xDF00 && a <= 0xDF0F) { this.r[a - 0xDF00] = v; if (a === 0xDF01 && (v & 0x80)) this.dma(v); return true; }
      return false;
    };
  }
  line() { return Math.floor((this.cpu.cycles % CYC_FRAME) / CYC_LINE); }
  dma(cmd) {
    const r = this.r;
    let c = r[2] | r[3] << 8, e = r[4] | r[5] << 8 | r[6] << 16, len = (r[7] | r[8] << 8) || 0x10000;
    const fixC = r[0x0A] & 0x80, fixR = r[0x0A] & 0x40;
    for (let i = 0; i < len; i++) {
      if ((cmd & 3) === 1) this.cpu.onWrite(c, this.reu[e % this.reu.length]) || (this.mem[c] = this.reu[e % this.reu.length]);
      else if ((cmd & 3) === 0) this.reu[e % this.reu.length] = this.cpu.onRead(c);
      if (!fixC) c = (c + 1) & 0xFFFF;
      if (!fixR) e = (e + 1) & 0xFFFFFF;
    }
    this.log.dma++;
    if (!(cmd & 0x20)) { r[2] = c & 255; r[3] = c >> 8; r[4] = e & 255; r[5] = (e >> 8) & 255; r[6] = e >> 16; r[7] = 1; r[8] = 0; }
  }
  interrupt(vec) {
    const c = this.cpu;
    c.push(c.pc >> 8); c.push(c.pc & 255); c.push(c.getP() & ~0x10);
    c.i = 1; c.pc = this.mem[vec] | this.mem[vec + 1] << 8; c.cycles += 7;
  }
  run(cycles) {
    const c = this.cpu, end = c.cycles + cycles;
    let lastLine = this.line();
    while (c.cycles < end) {
      c.step();
      const ln = this.line();
      if (ln !== lastLine) {
        if (ln === 0) { this.log.frames++; this.stepScript(); }
        if (ln === this.rasterCmp) this.irqFlag = 1;
        lastLine = ln;
      }
      if (this.nmiRun && c.cycles >= this.nmiNext) {
        this.nmiNext += this.nmiLatch + 1;
        if (this.nmiMask & 1 && !this.nmiFlag) { this.nmiFlag = 1; this.log.nmi++; this.interrupt(0xFFFA); continue; }
      }
      if (this.irqFlag && this.irqOn && !c.i) this.interrupt(0xFFFE);
    }
  }
  stepScript() {
    if (!this.script) return;
    while (this.left === 0 && this.sp < this.script.length) { [this.left, this.joy] = this.script[this.sp++]; }
    if (this.left > 0) this.left--; else this.joy = 0;
  }
}

if (process.argv[1] && process.argv[1].endsWith('machine.mjs')) {
  const a = process.argv.slice(2);
  const opt = k => { const i = a.indexOf(k); return i >= 0 ? a[i + 1] : null; };
  const reu = opt('--reu'), sf = opt('--script');
  const M = new Machine(a[0], { reu, script: sf ? JSON.parse(fs.readFileSync(sf, 'utf8')) : null });
  M.cpu.pc = 0x080E;
  M.mem[1] = 0x37;
  for (let s = 0; s < +a[1]; s++) {
    const before = { ...M.log, notes: [...M.log.notes] };
    M.run(985248);
    console.log(`s${s + 1}: frames ${M.log.frames - before.frames}  $D418 writes ${M.log.d418 - before.d418}  NMIs ${M.log.nmi - before.nmi}  notes v1 ${M.log.notes[0] - before.notes[0]} v2 ${M.log.notes[1] - before.notes[1]} v3 ${M.log.notes[2] - before.notes[2]}  pc $${M.cpu.pc.toString(16)}`);
  }
}
