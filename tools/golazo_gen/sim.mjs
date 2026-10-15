// Headless match simulation on the 6502 core: runs the real game code
// (MatchInit + GameFrame per frame, IrqBottom as the frame interrupt) and
// reports cycles per frame and match events.
//
//   node sim.mjs [frames] [humans] [--script file.json] [--trace]
import fs from 'fs';
import { CPU } from './cpu6502.mjs';

export function loadGame(prgFile = (process.env.GOLAZO_SNAP ? process.env.GOLAZO_SNAP + '/golazo.prg' : 'out/golazo.prg')) {
  const prg = fs.readFileSync(prgFile);
  const mem = new Uint8Array(65536);
  const load = prg[0] | (prg[1] << 8);
  mem.set(prg.slice(2), load);
  const L = JSON.parse(fs.readFileSync(process.env.GOLAZO_SNAP ? process.env.GOLAZO_SNAP + '/labels.json' : 'out/labels.json', 'utf8'));
  return { mem, labels: L.labels, C: L.consts };
}

export class Sim {
  static RATE = 44;
  static BUDGET = 50 * 63 + 51 * 63 + 201 * Sim.RATE;
  constructor({ prg = (process.env.GOLAZO_SNAP ? process.env.GOLAZO_SNAP + '/golazo.prg' : 'out/golazo.prg'), humans = 0, script = null, seed = 0x5A } = {}) {
    const { mem, labels, C } = loadGame(prg);
    this.mem = mem; this.L = labels; this.C = C;
    this.cpu = new CPU(mem);
    this.joy = [0, 0];                         // active-high bits per port index (0 = port 2)
    this.script = script; this.sp = 0; this.sleft = 0;
    // raster model for the main loop: an iteration starts at line 262 (after
    // the $FC IRQ); border lines give 63 cycles, playfield lines about 40
    // (badlines, sprite DMA, multiplexer IRQs). BUDGET cycles reach line $FC.
    this.f0 = 0; this.debt = 0; this.commitAt = -1;
    const line = () => {
      let c = this.cpu.cycles - this.f0 + this.debt;
      if (c < 50 * 63) return 262 + Math.floor(c / 63);
      c -= 50 * 63;
      if (c < 51 * 63) return Math.floor(c / 63);
      c -= 51 * 63;
      return Math.min(251, 51 + Math.floor(c / Sim.RATE));
    };
    this.cpu.onRead = a => {
      if (a === 0xDC00) return (~this.joy[0]) & 0xFF;
      if (a === 0xDC01) return (~this.joy[1]) & 0xFF;
      if (a === 0xD012) return line() & 0xFF;
      if (a === 0xD011) return (mem[a] & 0x7F) | ((line() & 0x100) >> 1);
      return mem[a];
    };
    this.cpu.onWrite = (a, v) => {
      if (a === C.READY && v === 1) this.commitAt = this.cpu.cycles - this.f0 + this.debt;
      return false;
    };
    // boot pieces (no IRQ chain: we call IrqBottom ourselves)
    mem[1] = 0x35;
    this.cpu.call(labels.VicInit);
    this.cpu.call(labels.SoundInit);
    mem[C.RNG] = seed;
    this.cpu.a = humans;
    this.cpu.call(labels.MatchInit);
    this.frame = 0;
    this.events = [];
  }
  irq() {
    const c = this.cpu, m = this.mem;
    // push PC=$FFFF-ish return and P, run handler until RTI lands at $FFFF
    c.push(0xFF); c.push(0xFF); c.push(c.getP());
    c.pc = this.L.IrqBottom;
    const c0 = c.cycles;
    while (c.pc !== 0xFFFF) { c.step(); if (c.cycles - c0 > 100000) throw new Error('irq runaway'); }
    return c.cycles - c0;
  }
  stepScript() {
    if (!this.script) return;
    while (this.sleft === 0 && this.sp < this.script.length) { const [n, b1, b2] = this.script[this.sp++]; this.sleft = n; this.joy = [b1, b2]; }
    if (this.sleft === 0) this.joy = [0, 0]; else this.sleft--;
  }
  step() {
    this.stepScript();
    const before = this.snapshot();
    this.mem[this.C.ITER_FC] = this.mem[this.C.FRAMECNT];
    this.f0 = this.cpu.cycles; this.commitAt = -1;
    const debt0 = this.debt;
    const cyc = this.cpu.call(this.L.GameFrame);
    const commit = this.commitAt, late = commit > Sim.BUDGET;
    const end = debt0 + cyc;
    this.debt = Math.max(0, end - (late ? 2 : 1) * Sim.BUDGET);
    const irq = this.irq();
    this.frame++;
    const after = this.snapshot();
    this.diff(before, after);
    return { cyc, irq, commit, late, debt: debt0 };
  }
  g(n) { return this.mem[this.C[n]]; }
  snapshot() {
    const g = n => this.g(n);
    return { gs: g('GSTATE'), rs: g('RS_TYPE'), s0: g('SCORE0'), s1: g('SCORE1'), owner: g('OWNER'), min: g('CLK_MIN'), half: g('HALF'), mode: g('MODE') };
  }
  diff(a, b) {
    const t = `${String(b.min).padStart(2, '0')}m f${this.frame}`;
    if (a.gs !== b.gs) this.events.push(`${t} state ${['PLAY', 'RESTART', 'GOAL', 'BREAK', 'FULL'][b.gs]}${b.gs === 1 ? ' ' + ['THROW', 'CORNER', 'GOALKICK', 'KICKOFF'][b.rs] : ''}`);
    if (a.s0 !== b.s0 || a.s1 !== b.s1) this.events.push(`${t} SCORE ${b.s0}-${b.s1}`);
    if (a.mode !== b.mode) this.events.push(`${t} MODE ${b.mode}`);
  }
  pos(i) { const m = this.mem, C = this.C; return { x: m[C.PXL + i] | m[C.PXH + i] << 8, y: m[C.PYL + i] | m[C.PYH + i] << 8 }; }
}

if (process.argv[1] && process.argv[1].endsWith('sim.mjs')) {
  const args = process.argv.slice(2);
  const frames = +(args.find(a => /^\d+$/.test(a)) || 3000);
  const humans = +(args.filter(a => /^\d+$/.test(a))[1] || 0);
  const si = args.indexOf('--script');
  const script = si >= 0 ? JSON.parse(fs.readFileSync(args[si + 1], 'utf8')) : null;
  const sim = new Sim({ humans, script });
  const cyc = [];
  let maxIrq = 0, owners = new Set(), stuck = 0, lastBall = '';
  for (let f = 0; f < frames; f++) {
    const r = sim.step();
    cyc.push(r.cyc); maxIrq = Math.max(maxIrq, r.irq);
    owners.add(sim.g('OWNER'));
    const b = JSON.stringify(sim.pos(22));
    if (b === lastBall && sim.g('GSTATE') === 0) stuck++; else stuck = 0;
    lastBall = b;
    if (stuck === 600) sim.events.push(`f${sim.frame} ball not moving for 600 frames`);
    if (sim.g('MODE') === 0) { sim.events.push('match over'); break; }
  }
  cyc.sort((a, b) => a - b);
  const pct = p => cyc[Math.min(cyc.length - 1, Math.floor(cyc.length * p))];
  console.log(`frames ${cyc.length}  cycles: median ${pct(0.5)}  p90 ${pct(0.9)}  p99 ${pct(0.99)}  max ${cyc[cyc.length - 1]}  irqmax ${maxIrq}`);
  console.log('over 13000:', cyc.filter(c => c > 13000).length, ' over 15000:', cyc.filter(c => c > 15000).length);
  console.log(sim.events.join('\n'));
  console.log('owners seen', [...owners].sort((a, b) => a - b).join(','));
}
