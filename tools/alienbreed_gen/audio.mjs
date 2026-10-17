// ALIEN BREED 64 audio.
//
// STOCK C64: the title theme is the original tune converted into a
// MUSIC_MAKER asset (edit it in the Music Maker), the effects a SFX_MAKER
// asset on voice 3.
//
// C64 ULTIMATE / REU: the theme and effects as 4-bit sample streams in the
// REU, played into $D418 by an NMI (one REU DMA byte per sample). The title
// clip is the original Amiga module rendered with its own samples
// (bprender.mjs); effects are synthesised. audio_src/<clip>.wav replaces a clip.
import fs from 'fs';
import path from 'path';
import { BASE_ASSETS } from './art.mjs';
import { SFX } from './defs.mjs';
import { convertBpsm } from './bp2mm.mjs';
import { renderBpsm } from './bprender.mjs';

// ------------------------------------------------------------ the song
// The original title tune: Brian Postma SoundMon module ALIENMENU from the
// Amiga disk (audio_src/alienmenu.bp), converted note for note by bp2mm.mjs.
export const MODULE = new URL('./audio_src/alienmenu.bp', import.meta.url);
export function buildMusicMeta() {
  const r = convertBpsm(fs.readFileSync(MODULE), 0);
  const m = structuredClone(BASE_ASSETS.MUSIC_AND_SFX.meta);
  m.instruments = r.instruments;
  m.patterns = r.patterns;
  m.songs = [{ loop: true, loop_row: 0, name: 'ALIENMENU (ALIEN BREED)', order: r.order }];
  m.play_speed = r.speed;
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

function makeRng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296 * 2 - 1; }; }

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
// Resample with a windowed-sinc low-pass (cutoff in Hz, default 0.43 x the
// new rate): anything above it only comes back as aliasing noise.
export function resample(pcm, from, to, cutoff = 0.43 * to) {
  if (from === to) return pcm;
  const n = Math.floor(pcm.length * to / from), out = new Float32Array(n), r = from / to;
  const fc = Math.min(cutoff, 0.5 * to) / from, half = Math.ceil(4 / fc);
  const kernel = new Float32Array(2 * half + 1);
  let sum = 0;
  for (let k = -half; k <= half; k++) {
    const sinc = k === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * k) / (Math.PI * k);
    const w = 0.42 + 0.5 * Math.cos(Math.PI * k / half) + 0.08 * Math.cos(2 * Math.PI * k / half);   // Blackman
    kernel[k + half] = sinc * w; sum += sinc * w;
  }
  for (let k = 0; k < kernel.length; k++) kernel[k] /= sum;
  for (let i = 0; i < n; i++) {
    const c = Math.round(i * r);
    let s = 0;
    for (let k = -half; k <= half; k++) { const j = c + k; if (j >= 0 && j < pcm.length) s += pcm[j] * kernel[k + half]; }
    out[i] = s;
  }
  return out;
}

// float PCM -> 4-bit $D418 values (0-15): normalised and softly limited to
// use all 16 levels, rounded without dither (dither on 4 bits is a constant
// hiss), and held on the centre level in near-silence
export function toNibbles(pcm) {
  let peak = 1e-6; for (const v of pcm) peak = Math.max(peak, Math.abs(v));
  const out = new Uint8Array(pcm.length);
  let env = 0;
  for (let i = 0; i < pcm.length; i++) {
    const x = Math.tanh(1.8 * pcm[i] / peak) / Math.tanh(1.8);
    env = Math.max(Math.abs(x), env * 0.999);
    const q = env < 0.04 ? 8 : Math.round(7.5 + x * 7.49);
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
    else if (i === 0) { const hi = renderBpsm(fs.readFileSync(MODULE), 0, rate * 4).pcm; pcm = resample(hi, rate * 4, rate, 3400); source = 'ALIENMENU module render'; }
    else { const hi = renderSfx(SFX[i - 1], rate * 4); pcm = resample(hi, rate * 4, rate); source = 'synthesised'; }
    clips.push({ name, rate, nib: toNibbles(pcm), loop: i === 0 ? 1 : 0, source });
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
