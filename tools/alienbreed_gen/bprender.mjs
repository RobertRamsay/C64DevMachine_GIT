// Render a Brian Postma SoundMon v2 module (Alien Breed's ALIENMENU) to PCM,
// using its own samples and synth waveforms. An approximation of the Amiga
// replay - samples, synth waves + ADSR tables, speed, volume, autoslide -
// close enough to hear the tune; EG/LFO/FX modulation is left out.
//
//   node bprender.mjs DISK OFFSET out.wav [seconds]
import fs from 'fs';
import { readBpsm } from './bpsm.mjs';

// Amiga periods; note n plays PERIODS[n + 35] (note 1 = ProTracker C-1, 856)
export const PERIODS = [6848, 6464, 6080, 5760, 5440, 5120, 4832, 4576, 4320, 4064, 3840, 3616,
  3424, 3232, 3040, 2880, 2720, 2560, 2416, 2288, 2160, 2032, 1920, 1808,
  1712, 1616, 1520, 1440, 1360, 1280, 1208, 1144, 1080, 1016, 960, 904,
  856, 808, 760, 720, 680, 640, 604, 572, 540, 508, 480, 452,
  428, 404, 380, 360, 340, 320, 302, 286, 270, 254, 240, 226,
  214, 202, 190, 180, 170, 160, 151, 143, 135, 127, 120, 113,
  107, 101, 95, 90, 85, 80, 76, 72, 68, 64, 60, 57];
const PAL = 3546895;

export function synthInfo(raw) {
  return { table: raw[1], len: ((raw[2] << 8) | raw[3]) * 2, adsrCtl: raw[4], adsrTable: raw[5], adsrLen: (raw[6] << 8) | raw[7],
    adsrSpeed: raw[8] || 1, vol: raw[25] || 64 };
}

export function renderBpsm(buf, base, outRate = 22050, maxSeconds = 1e9) {
  const m = readBpsm(buf, base);
  const d = buf.subarray(base);
  // sample data, in instrument order
  let so = m.sbase;
  const smp = m.instruments.map(x => {
    if (x.synth || !x.len) return null;
    const s = new Int8Array(d.buffer, d.byteOffset + so, x.len); so += x.len; return s;
  });
  const table = k => new Int8Array(d.buffer, d.byteOffset + m.tbase + k * 64, 64);
  const voices = [0, 1, 2, 3].map(() => ({ ins: 0, period: 0, pos: 0, vol: 0, on: false, slide: 0, adsr: 0, adsrT: 0 }));
  let speed = 6;
  const total = Math.min(m.songLen * 16 * 8 * 882 * 2, Math.floor(maxSeconds * outRate));
  const out = new Float32Array(total);
  let o = 0, ticks = 0;
  const tickLen = outRate / 50;
  outer:
  for (let s = 0; s < m.songLen; s++) {
    for (let row = 0; row < 16; row++) {
      // row events
      m.seq[s].forEach((c, v) => {
        const r = m.patterns[c.pat] && m.patterns[c.pat][row];
        if (!r) return;
        const V = voices[v];
        if (r.cmd === 2 && r.param > 0) speed = r.param;
        if (r.note) {
          let ins = r.instr ? r.instr + c.st : V.ins;
          if (ins < 1 || ins > 15) ins = V.ins;
          V.ins = ins;
          const idx = Math.max(0, Math.min(83, r.note + c.tr + 35));
          V.period = PERIODS[idx]; V.pos = 0; V.on = true; V.slide = 0; V.adsr = 0; V.adsrT = 0;
          const I = m.instruments[ins - 1];
          V.vol = I ? (I.synth ? synthInfo(I.raw).vol : I.vol) : 0;
        }
        if (r.cmd === 1) V.vol = Math.max(0, Math.min(64, r.param));
        if (r.cmd === 8) V.slide = r.param;
      });
      for (let t = 0; t < speed; t++) {
        // whole samples to the end of this 50 Hz tick (a tick is not a whole
        // number of samples at every rate, so count ticks, not samples)
        ticks++;
        const n = Math.round(ticks * tickLen) - o;
        for (const V of voices) {
          if (!V.on || !V.ins) continue;
          const I = m.instruments[V.ins - 1];
          if (!I) continue;
          let wave, loopStart = 0, loopLen = 0, env = 1;
          if (I.synth) {
            const si = synthInfo(I.raw);
            wave = table(si.table).subarray(0, Math.max(2, Math.min(64, si.len)));
            loopStart = 0; loopLen = wave.length;
            if (si.adsrCtl) {
              const at = table(si.adsrTable);
              env = (at[Math.min(63, V.adsr)] + 128) / 255;
              if (++V.adsrT >= si.adsrSpeed) { V.adsrT = 0; if (V.adsr < Math.min(63, si.adsrLen - 1)) V.adsr++; }
            }
          } else {
            wave = smp[V.ins - 1];
            if (!wave) continue;
            if (I.loopLen > 2) { loopStart = I.loop; loopLen = I.loopLen; }
          }
          const step = PAL / Math.max(57, V.period) / outRate;
          const g = V.vol / 64 * env / 128 * 0.5;
          for (let k = 0; k < n && o + k < total; k++) {
            let p = V.pos | 0;
            if (p >= wave.length) {
              if (loopLen) { V.pos = loopStart + ((V.pos - loopStart) % loopLen); p = V.pos | 0; } else { V.on = false; break; }
            }
            out[o + k] += wave[p] * g;
            V.pos += step;
          }
          V.period += V.slide;
        }
        o += n;
        if (o >= total) break outer;
      }
    }
  }
  return { pcm: out.subarray(0, o), module: m };
}

export function writeWav(file, pcm, rate) {
  let peak = 1e-6; for (const v of pcm) peak = Math.max(peak, Math.abs(v));
  const b = Buffer.alloc(44 + pcm.length * 2);
  b.write('RIFF', 0); b.writeUInt32LE(36 + pcm.length * 2, 4); b.write('WAVE', 8); b.write('fmt ', 12);
  b.writeUInt32LE(16, 16); b.writeUInt16LE(1, 20); b.writeUInt16LE(1, 22); b.writeUInt32LE(rate, 24); b.writeUInt32LE(rate * 2, 28);
  b.writeUInt16LE(2, 32); b.writeUInt16LE(16, 34); b.write('data', 36); b.writeUInt32LE(pcm.length * 2, 40);
  for (let i = 0; i < pcm.length; i++) b.writeInt16LE(Math.round(pcm[i] / peak * 30000), 44 + i * 2);
  fs.writeFileSync(file, b);
}

if (process.argv[1] && process.argv[1].endsWith('bprender.mjs')) {
  const [disk, off, wav, secs] = process.argv.slice(2);
  const { pcm, module: m } = renderBpsm(fs.readFileSync(disk), parseInt(off, 16), 22050, secs ? +secs : 1e9);
  writeWav(wav, pcm, 22050);
  console.log(`"${m.title}": ${(pcm.length / 22050).toFixed(1)} s -> ${wav}`);
}
