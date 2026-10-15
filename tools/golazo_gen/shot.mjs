// node shot.mjs script.json label hits out.png [dump.bin]  (build test PRG, screenshot at the Nth hit)
import { execSync } from 'child_process';
import fs from 'fs';
import { atBreak } from './vicemon.mjs';
const [script, label, hits, png, dump] = process.argv.slice(2);
const prg = 'out/t_' + Date.now() + '.prg';
execSync(`node build.mjs`, { env: { ...process.env, GOLAZO_TEST: script, GOLAZO_TEST_OUT: prg }, stdio: 'ignore' });
process.on('exit', () => execSync('node build.mjs', { stdio: 'ignore' }));   // labels back to the normal build
const L = JSON.parse(fs.readFileSync('out/labels.json', 'utf8'));
const addr = L.labels[label] ?? parseInt(label, 16);
const r = await atBreak({ prg, addr, hits: +hits, shot: png, dump: dump || null });
fs.unlinkSync(prg);
console.log(r.ok ? 'ok ' + png : 'TIMEOUT');
