// node soak.mjs PRG seconds [seed] [--reu img] - title -> game, then a random
// walker holding fire; prints game state each 5 s and checks the loop runs
import fs from 'fs';
import { Machine } from './machine.mjs';
const a = process.argv.slice(2), C = JSON.parse(fs.readFileSync('out/labels.json', 'utf8')).consts;
const ri = a.indexOf('--reu');
const M = new Machine(a[0], { reu: ri >= 0 ? a[ri + 1] : null });
let seed = +(a[2] || 7) || 7; const rnd = () => (seed = (seed * 1103515245 + 12345) >>> 0) / 4294967296;
const g = n => M.mem[C[n]], w = n => M.mem[C[n]] | M.mem[C[n] + 1] << 8;
let v3 = 0; const ow = M.cpu.onWrite; M.cpu.onWrite = (ad, v) => { if (ad === 0xD412 && (v & 1)) v3++; return ow(ad, v); };
M.cpu.pc = 0x080E; M.mem[1] = 0x37;
M.run(985248 * 2); M.joy = 16; M.run(20000 * 3); M.joy = 0; M.run(985248);
const dirs = [1, 2, 4, 8, 5, 6, 9, 10];
let d = 8, lastFc = g('FRAMECNT'), stall = 0;
for (let s = 0; s < +a[1]; s++) {
  for (let f = 0; f < 50; f++) { if (rnd() < 0.03) d = dirs[Math.floor(rnd() * 8)]; M.joy = d | 16; M.run(19656); }
  const fc = g('FRAMECNT'); if (fc === lastFc) stall++; lastFc = fc;
  const aliens = [2, 3, 4, 5, 6].filter(i => M.mem[C.AST + i]).length;
  if ((s + 1) % 5 === 0) console.log(`t${s + 1}s state ${g('GSTATE')} deck ${g('LEVEL')} pos ${w('PX')},${w('PY')} energy ${g('ENERGY')} lives ${g('LIVES')} ammo ${g('AMMOH').toString(16)}${g('AMMOL').toString(16).padStart(2, '0')} keys ${g('KEYS')} aliens ${aliens} score ${g('SCORE') ? '' : ''}${[2, 1, 0].map(i => M.mem[C.SCORE + i].toString(16).padStart(2, '0')).join('')} v3gates ${v3} pc $${M.cpu.pc.toString(16)}`);
}
console.log(stall ? `FRAME COUNTER STALLED ${stall} times` : 'frame loop alive throughout', '| SP', M.cpu.sp.toString(16));
