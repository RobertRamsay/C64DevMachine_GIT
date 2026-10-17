// node deckcheck.mjs PRG - load each deck in the game and compare the
// 128 x 96 char map at $A000 with the generator's map for it
import fs from 'fs';
import { Machine } from './machine.mjs';
import { buildDecks } from './levels.mjs';
const C = JSON.parse(fs.readFileSync('out/labels.json', 'utf8')).consts;
const M = new Machine(process.argv[2]);
const frames = n => M.run(19656 * n);
const { decks } = buildDecks();
const compare = n => {
  let bad = 0, first = -1;
  decks[n].map.forEach((c, i) => { if (M.mem[C.MAP + i] !== c) { bad++; if (first < 0) first = i; } });
  const d = decks[n], C2 = C, g16 = a => M.mem[C2[a]] | M.mem[C2[a] + 1] << 8;
  const sx = d.startChar.x * 8 + 8, sy = d.startChar.y * 8 + 8;
  const nv = M.mem[C.NVENTS], nc = M.mem[C.NCORES];
  if (nv !== d.vents || nc !== d.cores) { console.log(`deck ${n + 1}: ${nv} vents / ${nc} cores found, ${d.vents} / ${d.cores} placed`); bad++; }
  if (g16('START_X') !== sx || (M.mem[C.START_Y] | M.mem[C.START_YH] << 8) !== sy) { console.log(`deck ${n + 1}: start ${g16('START_X')},${M.mem[C.START_Y] | M.mem[C.START_YH] << 8} vs ${sx},${sy}`); bad++; }
  console.log(`deck ${n + 1}: ${nv} vents, ${nc} cores, start ${sx},${sy} -`, bad ? "MISMATCH" : "ok");
  console.log(`deck ${n + 1}: ${bad ? bad + ' chars differ, first at ' + (first % 128) + ',' + (first >> 7) + ` ($${M.mem[C.MAP + first].toString(16)} vs $${decks[n].map[first].toString(16)})` : 'map matches'}`);
  return bad;
};
M.cpu.pc = 0x080E; M.mem[1] = 0x37;
frames(100); M.joy = 16; frames(3); M.joy = 0; frames(60);
let bad = compare(0);
M.mem[C.LEVEL] = 1; M.mem[C.GSTATE] = 3; M.mem[C.GTIMER] = 0; M.mem[C.LEVEL] = 0;
M.joy = 16; frames(3); M.joy = 0; frames(60);
bad += compare(1);
process.exit(bad ? 1 : 0);
