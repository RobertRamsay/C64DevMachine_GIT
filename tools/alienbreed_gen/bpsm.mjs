// Brian Postma SoundMon v2 module reader (the format of Alien Breed's
// "ALIENMENU" title tune on the Amiga disk).
//   node bpsm.mjs FILE OFFSET  - dump header, instruments, sequence, patterns
//
// Layout (offsets from the module start):
//   0   title (26)            26 "V.2"           29 synth tables (byte)
//   30  song length (word)    32 15 instruments x 32 bytes
//   512 sequence: length x 4 voices x [pattern (word), sound transpose, transpose]
//   then patterns x 16 rows x [note (signed), instr << 4 | cmd, param]
//   then synth tables x 64, then the samples
import fs from 'fs';

export function readBpsm(buf, base = 0) {
  const d = buf.subarray(base);
  const title = d.toString('latin1', 0, 26).replace(/\0.*$/s, '');
  const id = d.toString('latin1', 26, 29);
  if (id !== 'V.2' && id !== 'V.3') throw new Error('not a SoundMon V.2/V.3 module: ' + JSON.stringify(id));
  const tables = d[29], songLen = d.readUInt16BE(30);
  const instruments = [];
  for (let i = 0; i < 15; i++) {
    const o = 32 + i * 32;
    if (d[o] === 0xFF) instruments.push({ synth: true, table: d[o + 1], len: d.readUInt16BE(o + 2) * 2, vol: d.readUInt16BE(o + 6), raw: [...d.subarray(o, o + 32)] });
    else instruments.push({ synth: false, name: d.toString('latin1', o, o + 24).replace(/\0.*$/s, ''), len: d.readUInt16BE(o + 24) * 2, loop: d.readUInt16BE(o + 26), loopLen: d.readUInt16BE(o + 28) * 2, vol: d.readUInt16BE(o + 30) });
  }
  const seq = [];
  let maxPat = 0;
  for (let s = 0; s < songLen; s++) {
    const row = [];
    for (let v = 0; v < 4; v++) {
      const o = 512 + (s * 4 + v) * 4;
      const p = d.readUInt16BE(o);
      row.push({ pat: p, st: d.readInt8(o + 2), tr: d.readInt8(o + 3) });
      maxPat = Math.max(maxPat, p);
    }
    seq.push(row);
  }
  const pbase = 512 + songLen * 16;
  const patterns = [null];
  for (let p = 1; p <= maxPat; p++) {
    const rows = [];
    for (let r = 0; r < 16; r++) {
      const o = pbase + ((p - 1) * 16 + r) * 3;
      rows.push({ note: d.readInt8(o), instr: d[o + 1] >> 4, cmd: d[o + 1] & 15, param: d.readInt8(o + 2) });
    }
    patterns.push(rows);
  }
  const tbase = pbase + maxPat * 48;
  const sbase = tbase + tables * 64;
  return { title, id, tables, songLen, instruments, seq, patterns, maxPat, pbase, tbase, sbase };
}

const NAMES = ['C-', 'C#', 'D-', 'D#', 'E-', 'E#'.slice(0, 0) || 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'];
export const noteName = n => NAMES[((n % 12) + 12) % 12] + Math.floor(n / 12);

if (process.argv[1] && process.argv[1].endsWith('bpsm.mjs')) {
  const [file, off] = process.argv.slice(2);
  const m = readBpsm(fs.readFileSync(file), parseInt(off || '0', 16));
  console.log(`"${m.title}" ${m.id} tables ${m.tables} song length ${m.songLen} patterns ${m.maxPat} patterns@+${m.pbase.toString(16)} tables@+${m.tbase.toString(16)} samples@+${m.sbase.toString(16)}`);
  m.instruments.forEach((x, i) => console.log(' instr', i + 1, x.synth ? `SYNTH table ${x.table} len ${x.len} vol ${x.vol}` : `${x.name} len ${x.len} loop ${x.loop}/${x.loopLen} vol ${x.vol}`));
  console.log(' sequence (pattern/st/tr per voice):');
  m.seq.slice(0, 40).forEach((r, s) => console.log('  ', String(s).padStart(3), r.map(c => `${String(c.pat).padStart(3)}/${c.st}/${c.tr}`.padEnd(12)).join(' ')));
  for (const p of [1, 2, 3, 4, 5, 6]) {
    console.log(' pattern', p);
    m.patterns[p].forEach((r, i) => console.log('   ', i.toString(16), r.note ? `${String(r.note).padStart(4)} i${r.instr} c${r.cmd} ${r.param}` : '   .'));
  }
}
