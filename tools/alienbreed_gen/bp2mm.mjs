// Alien Breed's title tune (SoundMon v2 module "ALIENMENU", 4 Amiga voices)
// into the Dev Machine Music Maker (3 SID voices).
//
// - The 52 module patterns stay 16-row patterns, note for note; each SID
//   instrument sits in its own octave (per-instrument offsets below).
// - The 175-step sequence becomes the song order, with the module's
//   per-voice transposes in t1..t3.
// - Four voices onto three: each step drops the voice that matters least
//   there (empty patterns first, then drums before bass before melody).
// - Speed changes (module command 2) become Fxx tempo commands.
// - Instrument 1 (DEEPVOICEBASS) is the alien gargle that opens the tune:
//   a sawtooth with a fast warble, stepping down in pitch.
import fs from 'fs';
import { readBpsm } from './bpsm.mjs';

// SID instruments, by module instrument number. oct = octave offset from the
// module's own pitch (note 1 = C-3 in Music Maker terms).
export const BP_INSTR = {
  1: { name: 'ALIEN GARGLE', oct: -1, attack: 0, decay: 11, sustain: 0, release: 8, pulse_width: 2048,
    text: '$21&V$C2,D3,N-1,D3,N-2,D3,N-3,D4,N-4,D4,N-5,D4,N-6,D5,N-7,D5,N-8,D6,N-9,D6,N-10,D8,N-11,D8,N-12,D10,$20,---' },
  2: { name: 'RESOBASS', oct: -1, attack: 0, decay: 9, sustain: 0, release: 6, pulse_width: 2048, text: '$21,D40,$20,---' },
  3: { name: 'SLAPREV', oct: 0, attack: 0, decay: 8, sustain: 0, release: 6, pulse_width: 1024, text: '$41&N+12,N,D3,$40,---' },
  4: { name: 'SYNTH SWELL', oct: 0, attack: 14, decay: 13, sustain: 0, release: 10, pulse_width: 1600, text: '$15&V$13,D2,L1' },
  5: { name: 'SYNTH BRIGHT', oct: 1, attack: 0, decay: 9, sustain: 0, release: 6, pulse_width: 800, text: '$41&V$24,D2,L1' },
  6: { name: 'KICK', fixed: true, attack: 0, decay: 6, sustain: 0, release: 2, pulse_width: 2048, text: '$41&N=50,$11&N=36,N=31,N=27,N=24,N=21,$10,---' },
  7: { name: 'SNARE', fixed: true, attack: 0, decay: 7, sustain: 0, release: 4, pulse_width: 2048, text: '$81&N=74,$41&N=43,$81&N=70,D2,$80,---' },
  8: { name: 'HIHAT', fixed: true, attack: 0, decay: 3, sustain: 0, release: 1, pulse_width: 2048, text: '$81&N=92,D1,$80,---' },
  9: { name: 'MINCHOIR', oct: 1, attack: 7, decay: 12, sustain: 0, release: 9, pulse_width: 1800, text: '$41&V$12,D2,L1' },
  10: { name: 'SYNTH LEAD', oct: 1, attack: 0, decay: 10, sustain: 0, release: 6, pulse_width: 1400, text: '$41&V$23,D2,L1' },
  13: { name: 'SAW LEAD', oct: 0, attack: 1, decay: 10, sustain: 0, release: 6, pulse_width: 2048, text: '$21&V$22,D2,L1' },
  14: { name: 'SYNTH PAD', oct: 0, attack: 2, decay: 10, sustain: 0, release: 6, pulse_width: 2000, text: '$41&V$12,D2,L1' },
};
// how much a voice matters in a step, per note of each instrument
const WEIGHT = { 1: 6, 2: 4, 3: 3, 4: 4, 5: 5, 6: 2.5, 7: 2.5, 8: 1, 9: 4, 10: 5, 13: 5, 14: 4 };
const NAMES = ['C-', 'C#', 'D-', 'D#', 'E-', 'F-', 'F#', 'G-', 'G#', 'A-', 'A#', 'B-'];
const noteName = i => NAMES[i % 12] + Math.floor(i / 12);

export function convertBpsm(buf, base) {
  const m = readBpsm(buf, base);
  const used = Object.keys(BP_INSTR).map(Number);
  const mmIndex = Object.fromEntries(used.map((n, i) => [n, i]));
  const instruments = used.map(n => {
    const { name, text, attack, decay, sustain, release, pulse_width } = BP_INSTR[n];
    return { name, text, attack, decay, sustain, release, pulse_width };
  });
  // pattern variants: module pattern + sound transpose (+ gate off on row 0,
  // + a tempo command on row 0), made on demand
  const patterns = [], made = new Map();
  const stats = { clamped: 0, droppedNotes: 0 };
  function variant(pat, st, cut, tempo) {
    const key = `${pat}/${st}/${cut}/${tempo}`;
    if (made.has(key)) return made.get(key);
    const rows = m.patterns[pat] || Array(16).fill({ note: 0 });
    let ins = 0;
    const steps = rows.map((r, i) => {
      const step = { note: '', instr_idx: -1, empty: true };
      if (r.note) {
        ins = r.instr ? r.instr + st : ins;
        const def = BP_INSTR[ins];
        if (def) {
          let idx = def.fixed ? 48 : r.note + 35 + 12 * (def.oct || 0);
          if (idx < 0 || idx > 95) { stats.clamped++; idx = Math.max(0, Math.min(95, idx)); }
          Object.assign(step, { note: noteName(idx), instr_idx: mmIndex[ins], empty: false });
        } else stats.droppedNotes++;
      }
      if (i === 0 && cut && step.empty) Object.assign(step, { note: '---', empty: false });
      if (i === 0 && tempo) Object.assign(step, { cmd: 15, cmd_val: tempo });
      return step;
    });
    patterns.push({ name: `M${pat}${st ? ' S' + st : ''}${cut ? ' X' : ''}${tempo ? ' F' + tempo : ''}`, pattern_len: 16, steps });
    made.set(key, patterns.length - 1);
    return patterns.length - 1;
  }
  // speed changes per step
  const tempoAt = {};
  let speed = 6;
  m.seq.forEach((row, s) => row.forEach(c => (m.patterns[c.pat] || []).forEach(r => { if (r.cmd === 2 && r.param > 0) { tempoAt[s] = r.param; } })));
  if (tempoAt[0]) speed = tempoAt[0];
  const order = [];
  let prevMap = [-1, -1, -1];
  m.seq.forEach((row, s) => {
    const weight = row.map(c => (m.patterns[c.pat] || []).reduce((w, r) => w + (r.note ? (WEIGHT[(r.instr || 0) + c.st] || WEIGHT[r.instr] || 1) : 0), 0));
    // a voice doubling another (same pattern, transposes) adds nothing on the SID
    row.forEach((c, v) => { if (row.slice(0, v).some(p => p.pat === c.pat && p.st === c.st && p.tr === c.tr)) weight[v] = -1; });
    let drop = 0;
    for (let v = 1; v < 4; v++) if (weight[v] < weight[drop]) drop = v;
    const kept = [0, 1, 2, 3].filter(v => v !== drop);
    const o = { force_len: 16, repeat_short: false };
    kept.forEach((v, k) => {
      const c = row[v];
      const cut = prevMap[k] !== v;
      const tempo = k === 0 && s > 0 && tempoAt[s] ? tempoAt[s] : 0;
      o['v' + (k + 1)] = variant(c.pat, c.st, cut, tempo);
      o['t' + (k + 1)] = c.tr;
    });
    prevMap = kept;
    order.push(o);
  });
  return { instruments, patterns, order, speed, stats, module: m };
}

if (process.argv[1] && process.argv[1].endsWith('bp2mm.mjs')) {
  const [file, off] = process.argv.slice(2);
  const r = convertBpsm(fs.readFileSync(file), parseInt(off || '0', 16));
  console.log(`instruments ${r.instruments.length}, patterns ${r.patterns.length}, order rows ${r.order.length}, start speed ${r.speed}`, r.stats);
  console.log(r.order.slice(0, 12).map((o, i) => `${i}: ${o.v1}/${o.t1} ${o.v2}/${o.t2} ${o.v3}/${o.t3}`).join('\n'));
}
