// analyse the $E000 frame timing log of a test dump: commit raster line vs the $FC frame start
import fs from 'fs';
const m = fs.readFileSync(process.argv[2]);
const skip = +(process.argv[3] || 0);
const rows = [];
for (let a = 0xE000 + skip * 2; a < 0xF000; a += 2) {
  const lo = m[a], f = m[a + 1];
  if (lo === 0 && f === 0 && m[a + 2] === 0 && m[a + 3] === 0) break;
  const line = lo | ((f & 0x80) << 1);
  const late = !!(f & 0x40), rd = !!(f & 1);
  // lines elapsed since the $FC IRQ that started the iteration
  let el = (line - 0xFC + 312) % 312;
  if (late) el += 312;
  rows.push({ el, late, rd });
}
const st = (a, n) => { a = a.map(r => r.el).sort((x, y) => x - y); const p = q => a[Math.min(a.length - 1, Math.floor(a.length * q))]; return `${n} n=${a.length} med ${p(.5)} p90 ${p(.9)} p99 ${p(.99)} max ${a[a.length - 1]} late ${(rows.filter(r => r.late && (n === 'all' || (n === 'rd') === r.rd)).length)}`; };
console.log(st(rows, 'all'));
console.log(st(rows.filter(r => r.rd), 'rd'));
console.log(st(rows.filter(r => !r.rd), 'nrd'));
const h = {}; for (const r of rows) { const b = Math.floor(r.el / 20) * 20; h[b] = (h[b] || 0) + 1; }
console.log(Object.entries(h).map(([k, v]) => `${k}:${v}`).join(' '));
