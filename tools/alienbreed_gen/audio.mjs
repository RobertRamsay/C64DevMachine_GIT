// ALIEN BREED 64 audio.
//
// STOCK C64: the title theme is a MUSIC_MAKER asset (edit it in the Music
// Maker), the effects a SFX_MAKER asset on voice 3.
//
// C64 ULTIMATE / REU: the same theme and effects as 4-bit sample streams in
// the REU, played into $D418 by an NMI (one REU DMA byte per sample). The
// converter takes audio_src/<clip>.wav when it is there (drop the original
// Amiga audio in to replace a clip) and otherwise renders its own version:
// the Music Maker song through a sample-style synth (choir pad, resonant
// bass, real drums, echo) and synthesised effects.
import fs from 'fs';
import path from 'path';
import { BASE_ASSETS } from './art.mjs';
import { SFX } from './defs.mjs';

// ------------------------------------------------------------ the song
// tokens: '.' hold, '-' note off, 'C-4' note (pattern instrument),
// 'n:C-4' note with instrument n
export const INSTR = [
  { name: 'LEAD', text: '$41&V$24,D2,L1', attack: 1, decay: 8, sustain: 10, release: 6, pulse_width: 1400 },
  { name: 'RESOBASS', text: '$21,D4,$20,---', attack: 0, decay: 7, sustain: 6, release: 3, pulse_width: 2048 },
  { name: 'KICK', text: '$11&N+12,N+5,N,N-7,N-12,$10,---', attack: 0, decay: 6, sustain: 0, release: 2, pulse_width: 2048 },
  { name: 'SNARE', text: '$81&N+24,$41&N+2,$81&N+22,D2,$80,---', attack: 0, decay: 7, sustain: 0, release: 4, pulse_width: 2048 },
  { name: 'HIHAT', text: '$81&N+40,D1,$80,---', attack: 0, decay: 3, sustain: 0, release: 1, pulse_width: 2048 },
  { name: 'CHOIR PAD', text: '$41&V$12,D2,L1', attack: 7, decay: 9, sustain: 10, release: 8, pulse_width: 1800 },
  { name: 'ARP MINOR', text: '$41&N,N+3,N+7,N,L1', attack: 0, decay: 9, sustain: 5, release: 3, pulse_width: 2048 },
  { name: 'ARP MAJOR', text: '$41&N,N+4,N+7,N,L1', attack: 0, decay: 9, sustain: 5, release: 3, pulse_width: 2048 },
];
const bassPat = (r) => {
  const n1 = r + '1', n2 = r + '2';
  const bar = [n1, '.', n2, '.', '.', n1, n2, '.', n1, '.', n2, n1, '.', n2, '.', n2];
  return [...bar, ...bar].join(' ');
};
const drum = bar => (bar + ' ' + bar);
export const PATTERNS = [
  ['LEAD A1', 0, 'E-5 . . . . . A-4 . C-5 . . . B-4 . A-4 . E-5 . . . . . . . D-5 . C-5 . B-4 . G-4 .'],
  ['LEAD A2', 0, 'A-4 . . . . . . . . . . . - . . . C-5 . D-5 . E-5 . . . G-5 . . . E-5 . . .'],
  ['LEAD F', 0, 'F-5 . . . E-5 . . . C-5 . . . A-4 . . . C-5 . . . . . . . A-4 . G-4 . F-4 . . .'],
  ['LEAD G', 0, 'G-4 . . . . . B-4 . D-5 . . . G-5 . . . F-5 . . . E-5 . . . D-5 . . . B-4 . . .'],
  ['LEAD E', 0, 'E-5 . . . . . . . G#4 . . . B-4 . . . E-5 . . . D-5 . . . B-4 . . . G#4 . . .'],
  ['BASS A', 1, bassPat('A-')],
  ['BASS F', 1, bassPat('F-')],
  ['BASS G', 1, bassPat('G-')],
  ['BASS E', 1, bassPat('E-')],
  ['DRUMS', 2, drum('2:C-3 . 4:C-5 . 3:C-3 . 4:C-5 . 2:C-3 2:C-3 4:C-5 . 3:C-3 . 4:C-5 4:C-5')],
  ['DRUMS INTRO', 2, drum('2:C-3 . . . 4:C-5 . . . 2:C-3 . . . 4:C-5 . . .')],
  ['CHOIR A', 5, 'A-4 . . . . . . . . . . . . . . . C-5 . . . . . . . . . . . . . . .'],
  ['CHOIR F', 5, 'F-4 . . . . . . . . . . . . . . . G-4 . . . . . . . . . . . . . . .'],
  ['ARP A', 6, 'A-4 . . . A-4 . . . A-5 . . . A-4 . . . A-4 . . . A-4 . . . A-5 . . . A-4 . . .'],
  ['ARP F', 7, 'F-4 . . . F-4 . . . F-5 . . . F-4 . . . G-4 . . . G-4 . . . G-5 . . . G-4 . . .'],
];
const R = (v1, v2, v3) => ({ v1, v2, v3 });
export const ORDER = [
  R(-1, 5, 10), R(-1, 5, 10), R(-1, 6, 10), R(-1, 7, 9),
  R(0, 5, 9), R(1, 5, 9), R(2, 6, 9), R(3, 7, 9), R(0, 5, 9), R(1, 5, 9), R(2, 6, 9), R(4, 8, 9),
  R(11, 5, 13), R(11, 5, 13), R(12, 6, 14), R(12, 7, 14),
];
export const PLAY_SPEED = 6;

function parsePat([name, instr, str]) {
  const toks = str.trim().split(/\s+/);
  if (toks.length !== 32) throw new Error(`${name}: ${toks.length} steps`);
  return toks.map(t => {
    if (t === '.') return { note: '', instr_idx: -1, empty: true };
    if (t === '-') return { note: '---', instr_idx: -1, empty: false };
    const m = t.match(/^(?:(\d+):)?([A-G][-#]\d)$/);
    if (!m) throw new Error(`${name}: bad token ${t}`);
    return { note: m[2], instr_idx: m[1] !== undefined ? +m[1] : instr, empty: false };
  });
}

export function buildMusicMeta() {
  const m = structuredClone(BASE_ASSETS.MUSIC_AND_SFX.meta);
  m.instruments = INSTR.map(i => ({ ...i }));
  m.patterns = PATTERNS.map(p => ({ name: p[0], pattern_len: 32, steps: parsePat(p) }));
  m.songs = [{ loop: true, loop_row: 0, name: 'ALIEN BREED THEME', order: ORDER.map(o => ({ force_len: 32, v1: o.v1, v2: o.v2, v3: o.v3, repeat_short: false })) }];
  m.play_speed = PLAY_SPEED;
  m.voice_mask = 7;            // all three voices: no SFX run on the title
  return m;
}

// ------------------------------------------------------------ SFX Maker
const SFX_DEF = {
  GUN: { text: '$81,N+12,D1,$41&N,D1,N-5,D1,$80,---', sfx_note: 'C-5', sfx_priority: 1, attack: 0, decay: 4, sustain: 0, release: 1 },
  ALIEN_DIE: { text: '$81,N,D2,N-3,D2,N-6,D2,N-9,D3,---', sfx_note: 'C-4', sfx_priority: 2, attack: 0, decay: 7, sustain: 4, release: 3 },
  HURT: { text: '$21,N,D2,N-4,D2,N-8,D3,---', sfx_note: 'E-4', sfx_priority: 3, attack: 0, decay: 6, sustain: 6, release: 2 },
  PICKUP: { text: '$11,N,D2,N+4,D2,N+7,D2,N+12,D4,---', sfx_note: 'C-5', sfx_priority: 2, attack: 0, decay: 5, sustain: 8, release: 2 },
  DOOR: { text: '$81,N,D3,N-2,D3,N-4,D4,N-6,D6,---', sfx_note: 'C-2', sfx_priority: 2, attack: 1, decay: 8, sustain: 6, release: 5 },
  KEY: { text: '$41,N,D2,N+12,D2,N+7,D2,N+19,D5,---', sfx_note: 'C-5', sfx_priority: 2, attack: 0, decay: 6, sustain: 8, release: 3 },
  TERMINAL: { text: '$41,N,D3,N+5,D3,N,D3,N+5,D4,---', sfx_note: 'C-5', sfx_priority: 2, attack: 0, decay: 4, sustain: 8, release: 2 },
  ALARM: { text: '$41,N,D6,N+5,D6,N,D6,N+5,D6,---', sfx_note: 'A-4', sfx_priority: 3, attack: 0, decay: 4, sustain: 10, release: 3 },
  CORE_HIT: { text: '$81,N,D2,$21&N-12,D3,---', sfx_note: 'C-3', sfx_priority: 2, attack: 0, decay: 6, sustain: 3, release: 3 },
  EXPLODE: { text: '$81,N,D4,N-2,D4,N-4,D6,N-6,D8,N-8,D10,---', sfx_note: 'C-3', sfx_priority: 3, attack: 0, decay: 10, sustain: 8, release: 8 },
};
export const SFX_LABELS = ['SfxGun', 'SfxAlienDie', 'SfxHurt', 'SfxPickup', 'SfxDoor', 'SfxKey', 'SfxTerminal', 'SfxAlarm', 'SfxCoreHit', 'SfxExplode'];
export function buildSfxMeta() {
  const m = structuredClone(BASE_ASSETS.GAME_SFX.meta);
  m.instruments = SFX.map(n => ({ name: n.replace('_', ' '), pulse_width: 2048, ...SFX_DEF[n] }));
  return m;
}

// ------------------------------------------------------------ renderer
const NOTE = { C: 0, 'C#': 1, D: 2, 'D#': 3, E: 4, F: 5, 'F#': 6, G: 7, 'G#': 8, A: 9, 'A#': 10, B: 11 };
const freqOf = n => { const m = n.match(/^([A-G])([-#])(\d)$/); const k = NOTE[m[1] + (m[2] === '#' ? '#' : '')] + 12 * +m[3]; return 440 * Math.pow(2, (k - 57) / 12); };
const FRAME_S = 1 / 50.125;

function makeRng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296 * 2 - 1; }; }

// The theme as a studio track: one pass of the song order.
export function renderTheme(SR) {
  const rowS = PLAY_SPEED * FRAME_S;
  const total = Math.ceil(ORDER.length * 32 * rowS * SR);
  const mix = new Float32Array(total);
  const pats = PATTERNS.map(parsePat);
  const noise = makeRng(17);
  const events = [];   // {voice, t, dur, instr, f}
  for (const [voice, key] of [[0, 'v1'], [1, 'v2'], [2, 'v3']]) {
    let open = null;
    ORDER.forEach((o, oi) => {
      const p = o[key];
      for (let s = 0; s < 32; s++) {
        const t = (oi * 32 + s) * rowS;
        const st = p < 0 ? { note: '---', empty: false } : pats[p][s];
        if (st.empty) continue;
        if (open) { open.dur = t - open.t; events.push(open); open = null; }
        if (st.note !== '---') open = { voice, t, instr: st.instr_idx, f: freqOf(st.note) };
      }
    });
    if (open) { open.dur = ORDER.length * 32 * rowS - open.t; events.push(open); }
  }
  for (const e of events) {
    const i0 = Math.floor(e.t * SR);
    const name = INSTR[e.instr].name;
    const len = name === 'KICK' ? 0.35 : name === 'SNARE' ? 0.3 : name === 'HIHAT' ? 0.06 : name === 'RESOBASS' ? Math.min(e.dur, 0.28) : e.dur + 0.25;
    const n = Math.min(Math.floor(len * SR), total - i0);
    let ph = [0, 0, 0, 0, 0], lp = 0, bp = 0;
    for (let k = 0; k < n; k++) {
      const t = k / SR;
      let v = 0;
      if (name === 'KICK') {
        const f = 45 + 110 * Math.exp(-t * 30); ph[0] += f / SR;
        v = Math.sin(2 * Math.PI * ph[0]) * Math.exp(-t * 9) * 1.1;
      } else if (name === 'SNARE') {
        ph[0] += 185 / SR;
        v = (noise() * 0.8 * Math.exp(-t * 18) + Math.sin(2 * Math.PI * ph[0]) * 0.5 * Math.exp(-t * 30)) * 0.9;
      } else if (name === 'HIHAT') {
        const x = noise(); v = (x - lp) * Math.exp(-t * 60) * 0.35; lp = x;
      } else if (name === 'RESOBASS') {
        ph[0] = (ph[0] + e.f / SR) % 1;
        const saw = ph[0] * 2 - 1;
        const cut = 0.04 + 0.25 * Math.exp(-t * 14);       // resonant filter sweep
        bp += cut * (saw - lp - 0.6 * bp); lp += cut * bp;
        v = (lp * 0.9 + bp * 0.5) * Math.exp(-t * 3) * 0.9;
      } else if (name === 'CHOIR PAD') {
        for (let d = 0; d < 5; d++) ph[d] = (ph[d] + e.f * (1 + (d - 2) * 0.006) / SR) % 1;
        const s = ph.reduce((a, p) => a + (p * 2 - 1), 0) / 5;
        lp += 0.08 * (s - lp);
        const env = Math.min(1, t / 0.6) * (t > e.dur ? Math.exp(-(t - e.dur) * 5) : 1);
        v = lp * env * 0.55;
      } else if (name.startsWith('ARP')) {
        const steps = name === 'ARP MINOR' ? [0, 3, 7, 0] : [0, 4, 7, 0];
        const f = e.f * Math.pow(2, steps[Math.floor(t / FRAME_S) % 4] / 12);
        ph[0] = (ph[0] + f / SR) % 1;
        v = (ph[0] < 0.5 ? 0.3 : -0.3) * Math.exp(-t * 2.5) * (t > e.dur ? Math.exp(-(t - e.dur) * 12) : 1);
      } else {   // LEAD: detuned pulse + saw with vibrato
        const vib = 1 + 0.006 * Math.sin(2 * Math.PI * 5.5 * t) * Math.min(1, t / 0.3);
        ph[0] = (ph[0] + e.f * vib / SR) % 1; ph[1] = (ph[1] + e.f * vib * 1.004 / SR) % 1;
        const s = (ph[0] < 0.35 ? 1 : -1) * 0.5 + (ph[1] * 2 - 1) * 0.5;
        lp += 0.18 * (s - lp);
        const env = Math.min(1, t / 0.02) * (t > e.dur ? Math.exp(-(t - e.dur) * 8) : 0.75 + 0.25 * Math.exp(-t * 3));
        v = lp * env * 0.5;
      }
      mix[i0 + k] += v;
    }
  }
  // echo (the Amiga menu tune is drenched in it)
  const d = Math.floor(0.36 * SR);
  for (let i = d; i < total; i++) mix[i] += mix[i - d] * 0.32;
  return mix;
}

export function renderSfx(name, SR) {
  const rnd = makeRng(name.length * 977);
  const dur = { GUN: 0.11, ALIEN_DIE: 0.45, HURT: 0.3, PICKUP: 0.32, DOOR: 0.7, KEY: 0.4, TERMINAL: 0.45, ALARM: 0.9, CORE_HIT: 0.3, EXPLODE: 1.3 }[name];
  const n = Math.floor(dur * SR), out = new Float32Array(n);
  let ph = 0, ph2 = 0, lp = 0, lp2 = 0;
  for (let k = 0; k < n; k++) {
    const t = k / SR; let v = 0;
    switch (name) {
      case 'GUN': { const x = rnd(); lp += 0.5 * (x - lp); ph += (180 - 500 * t) / SR; v = lp * Math.exp(-t * 28) + Math.sin(2 * Math.PI * ph) * Math.exp(-t * 35) * 0.8; break; }
      case 'ALIEN_DIE': { ph += (700 * Math.exp(-t * 5) + 90) / SR; const fm = Math.sin(2 * Math.PI * ph * 2.7); v = Math.sin(2 * Math.PI * ph + 3 * fm) * Math.exp(-t * 5) * 0.8 + rnd() * 0.3 * Math.exp(-t * 10); break; }
      case 'HURT': { ph = (ph + (220 - 200 * t) / SR) % 1; lp += 0.2 * ((ph * 2 - 1) - lp); v = lp * Math.exp(-t * 6) * 1.2; break; }
      case 'PICKUP': { const f = 660 * Math.pow(2, [0, 4, 7, 12][Math.min(3, Math.floor(t / 0.07))] / 12); ph += f / SR; v = Math.sin(2 * Math.PI * ph) * 0.8 * Math.exp(-t * 4); break; }
      case 'DOOR': { const x = rnd(); const c = 0.02 + 0.3 * Math.exp(-t * 4); lp += c * (x - lp); lp2 += 0.05 * (lp - lp2); ph += 55 / SR; v = (lp * 1.4 + Math.sin(2 * Math.PI * ph) * 0.4) * Math.min(1, t / 0.03) * Math.exp(-t * 3.5); break; }
      case 'KEY': { ph += 1320 / SR; ph2 += 1980 / SR; v = (Math.sin(2 * Math.PI * ph) + 0.6 * Math.sin(2 * Math.PI * ph2) * (t > 0.1 ? 1 : 0)) * 0.5 * Math.exp(-t * 6); break; }
      case 'TERMINAL': { const on = Math.floor(t / 0.06) % 2 === 0; ph += (on ? 1200 : 900) / SR; v = (Math.sin(2 * Math.PI * ph) > 0 ? 0.5 : -0.5) * Math.exp(-t * 3); break; }
      case 'ALARM': { const f = 520 + 260 * (0.5 + 0.5 * Math.sin(2 * Math.PI * 2.2 * t)); ph = (ph + f / SR) % 1; v = (ph * 2 - 1) * 0.6 * Math.min(1, (dur - t) / 0.1); break; }
      case 'CORE_HIT': { ph += 310 / SR; ph2 += 777 / SR; v = (Math.sin(2 * Math.PI * ph) * 0.6 + Math.sin(2 * Math.PI * ph2) * 0.4 + rnd() * 0.4 * Math.exp(-t * 40)) * Math.exp(-t * 9); break; }
      case 'EXPLODE': { const x = rnd(); const c = 0.03 + 0.4 * Math.exp(-t * 3); lp += c * (x - lp); lp2 += 0.1 * (lp - lp2); v = (lp * 0.9 + lp2 * 1.5) * Math.min(1, t / 0.01) * Math.exp(-t * 2.4) * 1.3; break; }
    }
    out[k] = v;
  }
  return out;
}

// ------------------------------------------------------------ WAV in
export function readWav(file) {
  const b = fs.readFileSync(file);
  if (b.toString('latin1', 0, 4) !== 'RIFF' || b.toString('latin1', 8, 12) !== 'WAVE') throw new Error(file + ': not a WAV');
  let o = 12, fmt = null, data = null;
  while (o + 8 <= b.length) {
    const id = b.toString('latin1', o, o + 4), len = b.readUInt32LE(o + 4);
    if (id === 'fmt ') fmt = { tag: b.readUInt16LE(o + 8), ch: b.readUInt16LE(o + 10), rate: b.readUInt32LE(o + 12), bits: b.readUInt16LE(o + 22) };
    if (id === 'data') data = b.subarray(o + 8, o + 8 + len);
    o += 8 + len + (len & 1);
  }
  if (!fmt || !data) throw new Error(file + ': no fmt/data');
  const bps = fmt.bits / 8, frames = Math.floor(data.length / (bps * fmt.ch)), out = new Float32Array(frames);
  for (let i = 0; i < frames; i++) {
    let s = 0;
    for (let c = 0; c < fmt.ch; c++) {
      const p = (i * fmt.ch + c) * bps;
      s += fmt.tag === 3 && bps === 4 ? data.readFloatLE(p) : bps === 1 ? (data[p] - 128) / 128 : bps === 2 ? data.readInt16LE(p) / 32768 : bps === 3 ? data.readIntLE(p, 3) / 8388608 : data.readInt32LE(p) / 2147483648;
    }
    out[i] = s / fmt.ch;
  }
  return { rate: fmt.rate, pcm: out };
}
function resample(pcm, from, to) {
  if (from === to) return pcm;
  const n = Math.floor(pcm.length * to / from), out = new Float32Array(n), r = from / to;
  // box-filter down to avoid aliasing, then linear interpolation
  for (let i = 0; i < n; i++) {
    const a = i * r, b = a + r; let s = 0, c = 0;
    for (let j = Math.floor(a); j < Math.max(Math.floor(a) + 1, Math.floor(b)); j++) { if (j < pcm.length) { s += pcm[j]; c++; } }
    out[i] = c ? s / c : 0;
  }
  return out;
}

// float PCM -> 4-bit $D418 values (0-15), normalised, softly limited, dithered
function toNibbles(pcm, seed = 1) {
  let peak = 1e-6; for (const v of pcm) peak = Math.max(peak, Math.abs(v));
  const rnd = makeRng(seed), out = new Uint8Array(pcm.length);
  for (let i = 0; i < pcm.length; i++) {
    const x = Math.tanh(1.6 * pcm[i] / peak) / Math.tanh(1.6);
    const q = Math.round(7.5 + x * 7.4 + (rnd() + rnd()) * 0.35);
    out[i] = Math.max(0, Math.min(15, q));
  }
  return out;
}

// ------------------------------------------------------------ REU image
export const RATE_MUSIC = 7884, RATE_SFX = 5512;
export const REU_DIR = 0x000100, REU_CLIPS = 0x000200;
const CLIP_FILES = ['title', ...SFX.map(s => s.toLowerCase())];
export function buildReuAudio(srcDir) {
  const clips = [];
  CLIP_FILES.forEach((name, i) => {
    const rate = i === 0 ? RATE_MUSIC : RATE_SFX;
    const wav = path.join(srcDir, name + '.wav');
    let pcm, source;
    if (fs.existsSync(wav)) { const w = readWav(wav); pcm = resample(w.pcm, w.rate, rate); source = 'audio_src/' + name + '.wav'; }
    else if (i === 0) { const hi = renderTheme(rate * 4); pcm = resample(hi, rate * 4, rate); source = 'rendered theme'; }
    else { const hi = renderSfx(SFX[i - 1], rate * 4); pcm = resample(hi, rate * 4, rate); source = 'synthesised'; }
    clips.push({ name, rate, nib: toNibbles(pcm, i + 3), loop: i === 0 ? 1 : 0, source });
  });
  // layout: clips one after the other, each followed by 256 bytes of silence
  let at = REU_CLIPS;
  const dir = [0x41, 0x42, 0x52, 0x45, 0x55, 0x31, clips.length, 0];   // "ABREU1"
  const image = [];
  for (const c of clips) {
    c.start = at;
    const frames = Math.floor(c.nib.length * 50.125 / c.rate) - 1;
    const latch = Math.round(985248 / c.rate) - 1;
    dir.push(at & 255, (at >> 8) & 255, at >> 16, frames & 255, frames >> 8, latch & 255, latch >> 8, c.loop);
    const padded = new Uint8Array(Math.ceil((c.nib.length + 256) / 256) * 256).fill(8);
    padded.set(c.nib);
    c.bytes = padded;
    at += padded.length;
  }
  if (dir.length > 128) throw new Error('REU directory too big');
  while (dir.length < 256) dir.push(0);
  const total = at;
  return { clips, dir, total };
}
