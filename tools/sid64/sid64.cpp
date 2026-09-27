// sid64 - reSID / reSID-fp wrapper for GameMaker (C64 Dev Machine)
// All exports: cdecl, double args, double return (GameMaker extension friendly).
// Buffer args: pass buffer_get_address(buf) (declare as string/pointer in the extension).
#include <string.h>
#include "resid/sid.h"
#include "resid-fp/sidfp.h"

#if defined(_WIN32)
#define EXPORT extern "C" __declspec(dllexport)
#else
#define EXPORT extern "C" __attribute__((visibility("default")))
#endif

static SID   *g_sid = 0;
static SIDFP *g_sidfp = 0;
static int g_clock = 985248;
static int g_rate = 44100;
static unsigned char g_regs[32];
static double g_gain = 1.0;
static int g_cycles_per_frame = 19656;

// GoatTracker order: voice 3 -> 1, AD/SR before CTRL so gate sees new envelope
static const unsigned char k_order[25] = {
  0x18,0x17,0x16,0x15,0x14,0x13,0x12,0x11,0x10,0x0f,0x0e,
  0x0d,0x0c,0x0b,0x0a,0x09,0x08,0x07,0x06,0x05,0x04,0x03,0x02,0x01,0x00 };
#define WRITE_DELAY 9

static void chip_write(int r, int v) {
  if (g_sid) g_sid->write(r, v);
  if (g_sidfp) g_sidfp->write(r, v);
  g_regs[r & 31] = (unsigned char)v;
}
static int chip_clock(int &cycles, short *out, int n) {
  cycle_count c = cycles;
  int got = 0;
  if (g_sid) got = g_sid->clock(c, out, n);
  if (g_sidfp) got = g_sidfp->clock(c, out, n);
  cycles = (int)c;
  if (g_gain != 1.0) {
    for (int i = 0; i < got; i++) {
      double v = out[i] * g_gain;
      if (v > 32767.0) v = 32767.0;
      if (v < -32768.0) v = -32768.0;
      out[i] = (short)v;
    }
  }
  return got;
}
static void free_chip() {
  if (g_sid) { delete g_sid; g_sid = 0; }
  if (g_sidfp) { delete g_sidfp; g_sidfp = 0; }
}

// model: 0 = 6581, 1 = 8580. engine: 0 = reSID, 1 = reSID-fp (better 6581 filter/distortion)
EXPORT double sid64_init(double clock_hz, double sample_rate, double model, double engine) {
  free_chip();
  g_clock = (int)clock_hz;
  g_rate = (int)sample_rate;
  if ((int)engine == 1) {
    g_sidfp = new SIDFP;
    g_sidfp->set_chip_model(((int)model == 1) ? MOS8580 : MOS6581);
    g_sidfp->set_sampling_parameters(g_clock, SAMPLE_INTERPOLATE, g_rate);   // no resampler FIR latency
    g_sidfp->get_filter().set_distortion_properties(0.50f, 3.3e6f, 1.0e-4f);
    g_sidfp->get_filter().set_type3_properties(1147036.4394268463f, 274228796.97550374f, 1.0066634233403395f, 16125.154840564108f);
    g_sidfp->get_filter().set_type4_properties(5.5f, 20.f);
    g_sidfp->set_voice_nonlinearity(0.9613160610660189f);
    g_sidfp->reset();
  } else {
    g_sid = new SID;
    g_sid->set_chip_model(((int)model == 1) ? MOS8580 : MOS6581);
    g_sid->set_sampling_parameters(g_clock, SAMPLE_INTERPOLATE, g_rate);
    g_sid->reset();
  }
  memset(g_regs, 0, sizeof(g_regs));
  return 1;
}

EXPORT double sid64_reset() {
  if (g_sid) g_sid->reset();
  if (g_sidfp) g_sidfp->reset();
  memset(g_regs, 0, sizeof(g_regs));
  return 1;
}

EXPORT double sid64_free() { free_chip(); return 1; }

EXPORT double sid64_write(double reg, double val) {
  if (!g_sid && !g_sidfp) return 0;
  chip_write(((int)reg) & 31, ((int)val) & 255);
  return 1;
}

// Render 'cycles' SID clocks into s16 mono at buf_ptr (max 'max_samples'). Returns samples written.
EXPORT double sid64_clock(const char *buf_ptr, double cycles, double max_samples) {
  if (!g_sid && !g_sidfp) return 0;
  short *out = (short*)buf_ptr;
  int c = (int)cycles, left = (int)max_samples, total = 0;
  while (c > 0 && left > 0) {
    int got = chip_clock(c, out, left);
    out += got; left -= got; total += got;
    if (got == 0) break;
  }
  return total;
}

// Offline render of a register log.
// frames_ptr: 'frames' records of 32 bytes: [0..24] register values, [25..28] u32 write mask
//   (bit r = write reg r this frame; 0 = write all 25), [29..31] unused.
// out_ptr: s16 mono buffer with room for out_max samples.
// Frame length comes from sid64_set_cycles_per_frame (19656 PAL / 17095 NTSC).
// Returns samples written.
// GameMaker allows mixed argument types only up to 4 arguments, so the frame
// length is set separately (sid64_set_cycles_per_frame, default 19656 PAL).
EXPORT double sid64_set_cycles_per_frame(double cycles) {
  if (cycles >= 1) g_cycles_per_frame = (int)cycles;
  return 1;
}

EXPORT double sid64_render_log(const char *frames_ptr, double frames, const char *out_ptr,
                               double out_max) {
  if (!g_sid && !g_sidfp) return 0;
  const unsigned char *f = (const unsigned char*)frames_ptr;
  short *out = (short*)out_ptr;
  int nf = (int)frames, left = (int)out_max, total = 0, cpf = g_cycles_per_frame;
  for (int i = 0; i < nf && left > 0; i++) {
    const unsigned char *rec = f + i * 32;
    unsigned mask = rec[25] | (rec[26] << 8) | (rec[27] << 16) | ((unsigned)rec[28] << 24);
    int budget = cpf;
    for (int k = 0; k < 25; k++) {
      int r = k_order[k];
      if (mask != 0 && !(mask & (1u << r))) continue;
      chip_write(r, rec[r]);
      int c = WRITE_DELAY;
      int got = chip_clock(c, out, left);
      out += got; left -= got; total += got; budget -= WRITE_DELAY;
    }
    int c = budget;
    while (c > 0 && left > 0) {
      int got = chip_clock(c, out, left);
      out += got; left -= got; total += got;
      if (got == 0) break;
    }
  }
  return total;
}

// Write volume/filter reg $18 and run the chip silently for 'ms' milliseconds, discarding output.
// Lets the 6581 volume-write DC step and the external filter settle before a render starts.
EXPORT double sid64_settle(double vol_reg, double ms) {
  if (!g_sid && !g_sidfp) return 0;
  chip_write(0x18, ((int)vol_reg) & 255);
  short scratch[1024];
  int c = (int)((double)g_clock * ms / 1000.0);
  while (c > 0) {
    int got = chip_clock(c, scratch, 1024);
    if (got == 0 && c > 0) { continue; }
  }
  return 1;
}

EXPORT double sid64_read(double reg) {
  int r = ((int)reg) & 31;
  if (g_sid && r >= 0x19) return g_sid->read(r);
  if (g_sidfp && r >= 0x19) return g_sidfp->read(r);
  return g_regs[r];
}

// Output gain applied to every rendered sample (1.0 = reSID's native level).
EXPORT double sid64_set_gain(double gain) { g_gain = gain; return 1; }

EXPORT double sid64_version() { return 1.0; }
