// profile restricted to frames above a cycle threshold
import { Sim } from './sim.mjs';
const frames = +(process.argv[2] || 3000), lim = +(process.argv[3] || 15000);
const sim = new Sim({ humans: 0 });
const names = Object.fromEntries(Object.entries(sim.L).map(([k, v]) => [v, k]));
let cur = {}; const stack = [];
sim.cpu.trace = (c, pc, mn) => {
  if (mn === 'JSR') { const t = c.rd(pc + 1) | (c.rd(pc + 2) << 8); stack.push([t, c.cycles]); }
  else if (mn === 'RTS' && stack.length) { const [t, c0] = stack.pop(); const n = names[t] || t.toString(16); cur[n] = (cur[n] || 0) + (c.cycles - c0 + 6); }
};
const acc = {}; let n = 0, all = {}, na = 0;
for (let f = 0; f < frames; f++) {
  cur = {}; stack.length = 0;
  const r = sim.step();
  for (const [k, v] of Object.entries(cur)) all[k] = (all[k] || 0) + v; na++;
  if (lim ? r.cyc > lim : r.late) { n++; for (const [k, v] of Object.entries(cur)) acc[k] = (acc[k] || 0) + v; }
}
console.log('frames over', lim, ':', n, 'of', frames);
const rows = Object.entries(acc).sort((a, b) => b[1] - a[1]).slice(0, 30);
for (const [k, v] of rows) console.log(k.padEnd(16), String(Math.round(v / n)).padStart(6), '  avg all', String(Math.round((all[k] || 0) / na)).padStart(6));
