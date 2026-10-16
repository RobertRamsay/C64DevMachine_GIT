// node hybrid.mjs SCRIPT.json OUT.prg - the editor's build (C:\C64Temp\program.prg)
// with the scripted joystick of a --test build spliced in, so the real
// Music Maker / SFX Maker code runs under a test script in VICE
import fs from 'fs'; import { execFileSync } from 'child_process';
const [script, out] = process.argv.slice(2);
const load = f => { const b = fs.readFileSync(f), m = new Uint8Array(65536); m.set(b.subarray(2), b[0] | b[1] << 8); return { m, end: (b[0] | b[1] << 8) + b.length - 2 }; };
execFileSync(process.execPath, ['build.mjs', 'out/test.json', '--test', script], { stdio: 'ignore' });
const plain = load('out/alienbreed.prg'), test = load('out/alienbreed_test.prg'), ed = load('C:/C64Temp/program.prg');
let n = 0;
for (let i = 0; i < 65536; i++) if (test.m[i] !== plain.m[i]) { ed.m[i] = test.m[i]; n++; }
const end = Math.max(ed.end, test.end);
fs.writeFileSync(out, Buffer.concat([Buffer.from([1, 8]), Buffer.from(ed.m.subarray(0x801, end))]));
console.log('spliced %d bytes into the editor build -> %s', n, out);
