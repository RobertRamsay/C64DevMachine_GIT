// node compare.mjs editor.prg mine.prg - compare memory images, list differing ranges
import fs from 'fs';
const load = f => { const b = fs.readFileSync(f), m = new Int16Array(65536).fill(-1), a = b[0] | b[1] << 8; for (let i = 2; i < b.length; i++) m[a + i - 2] = b[i]; return { m, a, end: a + b.length - 2 }; };
const [e, g] = process.argv.slice(2).map(load);
console.log('editor $%s-$%s, generator $%s-$%s', e.a.toString(16), (e.end - 1).toString(16), g.a.toString(16), (g.end - 1).toString(16));
const ranges = []; let start = -1;
for (let i = 0; i < 65536; i++) {
  const d = e.m[i] !== g.m[i] && !(e.m[i] <= 0 && g.m[i] <= 0);
  if (d && start < 0) start = i; if (!d && start >= 0) { ranges.push([start, i - 1]); start = -1; }
}
for (const [a, b] of ranges) console.log('  differ $%s-$%s (%d bytes)', a.toString(16), b.toString(16), b - a + 1);
// where does the editor's code in the macro columns end?
for (const [lo, hi, n] of [[0x1190, 0x1A00, 'SFX'], [0x1A00, 0x4000, 'MUSIC']]) { let last = -1; for (let i = lo; i < hi + 0x400 && i < 65536; i++) if (e.m[i] > 0) last = i; console.log('  %s column last non-zero byte $%s', n, last.toString(16)); }
