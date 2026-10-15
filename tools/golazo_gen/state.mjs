// print game state from a RAM dump: node state.mjs dump.bin
import fs from 'fs';
const m = fs.readFileSync(process.argv[2]);
const { consts: C } = JSON.parse(fs.readFileSync('out/labels.json', 'utf8'));
const g = n => m[C[n]];
const w = (l, h) => m[C[l]] | (m[C[h]] << 8);
console.log('GSTATE', g('GSTATE'), 'RS_TYPE', g('RS_TYPE'), 'OWNER', g('OWNER'), 'CTRL1', g('CTRL1'), 'CTRL2', g('CTRL2'),
  'SCORE', g('SCORE0') + '-' + g('SCORE1'), 'CLK', g('CLK_MIN') + ':' + g('CLK_SEC'), 'HALF', g('HALF'), 'ATT0', g('ATT0'),
  'WAITMIN', g('WAITMIN'), 'FRAMECNT', g('FRAMECNT'), 'MODE', g('MODE'), 'HUMANS', g('HUMANS'));
console.log('overruns', m[C.OVRCNT] | m[C.OVRCNT + 1] << 8, 'of', m[C.ITERCNT] | m[C.ITERCNT + 1] << 8);
console.log('CAM1', m[C.CAM1X] | m[C.CAM1X + 1] << 8, m[C.CAM1Y], 'FRONT', g('FRONTC'), g('FRONTR'), 'PRE', g('PRE_ON'), g('PRE_C'), g('PRE_R'), g('PRE_ST'), 'CHASE', g('CHASE0'), g('CHASE1'), 'PASS_TO', g('PASS_TO'), 'LAST', g('LASTTOUCH'));
const P = i => ({ x: m[C.PXL + i] | m[C.PXH + i] << 8, y: m[C.PYL + i] | m[C.PYH + i] << 8, st: m[C.PSTATE + i], dir: m[C.PDIR + i], mv: m[C.PMOVE + i], fr: m[C.PFRAME + i] });
console.log('ball', P(22), 'z', m[C.BZH]);
for (let i = 0; i < 22; i++) { const p = P(i); process.stdout.write(`${i}:${p.x},${p.y} s${p.st} d${p.dir}${i % 6 === 5 ? '\n' : '  '}`); }
console.log();
let dl = ''; const base = m[C.FRONT_DL];
for (let j = base; j < base + 32 && m[C.DLY + j] !== 255; j++) dl += m[C.DLY + j].toString(16) + ' ';
console.log('front DL Y:', dl);
