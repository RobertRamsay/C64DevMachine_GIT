// inclusive cycle profile per subroutine over N frames of a demo match
import { Sim } from './sim.mjs';
const frames = +(process.argv[2] || 1500);
const humans = +(process.argv[3] || 0);
const sim = new Sim({ humans });
const names = Object.fromEntries(Object.entries(sim.L).map(([k, v]) => [v, k]));
const incl = {}, calls = {};
const stack = [];
sim.cpu.trace = (c, pc, mn) => {
  if (mn === 'JSR') { const t = c.rd(pc + 1) | (c.rd(pc + 2) << 8); stack.push([t, c.cycles]); }
  else if (mn === 'RTS' && stack.length) { const [t, c0] = stack.pop(); const n = names[t] || t.toString(16); incl[n] = (incl[n] || 0) + (c.cycles - c0 + 6); calls[n] = (calls[n] || 0) + 1; }
};
let total = 0;
for (let f = 0; f < frames; f++) { stack.length = 0; total += sim.step().cyc; }
const rows = Object.entries(incl).sort((a, b) => b[1] - a[1]).slice(0, 40);
console.log('avg per frame', Math.round(total / frames));
for (const [n, c] of rows) console.log(n.padEnd(18), String(Math.round(c / frames)).padStart(7), ' calls/frame', (calls[n] / frames).toFixed(2), ' per call', Math.round(c / calls[n]));
