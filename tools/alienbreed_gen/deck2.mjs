// node deck2.mjs PRG - deck 2 scripted: shoot the 4 cores from below,
// check the self-destruct starts and counts, step into the lift
import fs from 'fs';
import { Machine } from './machine.mjs';
import { buildDecks } from './levels.mjs';
const L = JSON.parse(fs.readFileSync('out/labels.json', 'utf8')), C = L.consts;
const M = new Machine(process.argv[2]);
const g = n => M.mem[C[n]], set16 = (n, v) => { M.mem[C[n]] = v & 255; M.mem[C[n] + 1] = v >> 8; };
const frames = n => M.run(19656 * n);
M.cpu.pc = 0x080E; M.mem[1] = 0x37;
frames(100); M.joy = 16; frames(3); M.joy = 0; frames(60);
// jump to deck 2: LEVEL = 1, then the deck-complete path (fire on the page)
M.mem[C.LEVEL] = 1; M.mem[C.GSTATE] = 3; M.mem[C.GTIMER] = 0; M.mem[C.LEVEL] = 0;
M.joy = 16; frames(3); M.joy = 0; frames(30);
console.log('deck', g('LEVEL'), 'state', g('GSTATE'), 'cores', g('CORES'), 'vents', g('NVENTS'));
const deck = buildDecks().decks[1];
const cores = deck.T.flatMap((r, y) => r.map((c, x) => c === 'R' ? [x, y] : null)).filter(Boolean);
for (const [tx, ty] of cores) {
  set16('PX', tx * 16 + 8); set16('PY', ty * 16 + 8 + 26); M.mem[C.P_INV] = 200;
  M.joy = 1; frames(2); M.joy = 16; frames(150); M.joy = 0; frames(5);
  M.mem[C.ENERGY] = 64;
  console.log(`core at ${tx},${ty}: cores left ${g('CORES')}, state ${g('GSTATE')}, self-destruct ${g('SD_ON')} ${g('SD_MIN')}:${g('SD_SEC').toString(16)}`);
}
frames(200);
console.log('after 4 s: self-destruct', g('SD_ON'), `${g('SD_MIN')}:${g('SD_SEC').toString(16)}`, 'border', M.mem[C.CUR_D020]);
const lift = deck.T.flatMap((r, y) => r.map((c, x) => c === 'E' ? [x, y] : null)).filter(Boolean)[0];
set16('PX', lift[0] * 16 + 16); set16('PY', lift[1] * 16 + 40); M.mem[C.P_INV] = 200;
M.joy = 1; frames(40); M.joy = 0; frames(10);
console.log('at the lift: state', g('GSTATE'), '(5 = mission complete)', 'score', [2, 1, 0].map(i => M.mem[C.SCORE + i].toString(16).padStart(2, '0')).join(''));
M.joy = 16; frames(80); M.joy = 0; frames(5); M.joy = 16; frames(3); M.joy = 0; frames(30);
console.log('after fire: pc $' + M.cpu.pc.toString(16), 'music on', g('MUSIC_ON'), '(back on the title)');
