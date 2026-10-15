// frame timing in the headless demo: commit time (main-loop cycles incl.
// carried-over lateness), late frames, redraw slices drawn
//   node perf.mjs [frames] [humans] [seeds]
import { Sim } from './sim.mjs';
const frames = +(process.argv[2] || 4000), humans = +(process.argv[3] || 0), seeds = +(process.argv[4] || 3);
const cm = [];
let late = 0, lateDebt = 0, forced = 0, cross = 0, slices = 0, n = 0;
for (let s = 0; s < seeds; s++) {
  const sim = new Sim({ humans, seed: 0x5A + s * 37 });
  let fc0 = sim.g('FRONTC'), fr0 = sim.g('FRONTR');
  const draw = sim.L.DrawPart;
  sim.cpu.trace = (c, pc) => { if (pc === draw) slices++; };
  for (let f = 0; f < frames; f++) {
    const r = sim.step(); n++;
    cm.push(r.commit); if (r.late) { late++; if (r.debt) lateDebt++; }
    if (sim.g('RD_BUSY')) forced++;
    const fc = sim.g('FRONTC'), fr = sim.g('FRONTR');
    if (fc !== fc0 || fr !== fr0) cross++;
    fc0 = fc; fr0 = fr;
  }
}
const st = a => { a = [...a].sort((x, y) => x - y); const p = q => a[Math.min(a.length - 1, Math.floor(a.length * q))]; return `med ${p(.5)} p90 ${p(.9)} p95 ${p(.95)} p99 ${p(.99)} max ${a[a.length - 1]}`; };
console.log('commit cycles', st(cm), ' budget', Sim.BUDGET);
console.log(`late ${late} ${(late / n * 100).toFixed(1)}% (after a spill ${lateDebt})  urgent ${forced}  cell changes ${cross}  slices ${slices} (${(slices / Math.max(1, cross)).toFixed(1)} per change)`);
