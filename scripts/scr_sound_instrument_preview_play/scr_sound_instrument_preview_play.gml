/// @function scr_sound_instrument_preview_play(_instr, _note_name, _channel)
/// @desc Auditions an instrument's compiled bytecode against a note, walking
///       WAVE/NOTE/HOLD/LOOP commands the same way the 6502 interpreter
///       will, and shaping the result with a SID-style ADSR envelope: attack
///       ramps up, decay falls to the sustain level, sustain holds for the
///       combined length of every D-tick hold in the instrument (the "gate
///       on" period), then release fades out after that. Loops are followed
///       up to a safety cap so a runaway L-target can't hang the preview.
/// _max_sec caps the rendered length. During song/row playback the next row
/// hard-stops this sound anyway, so rendering the instrument's full natural
/// release is wasted work — at speed 6 (100ms a row) with release 8 (240ms)
/// more than half the buffer is synthesised and then thrown away, and that
/// cost lands on the single frame the row advances. Callers that know the
/// row duration pass it; a bare audition (clicking a key) passes nothing and
/// gets the full tail as before.
function scr_sound_instrument_preview_play(_instr, _note_name, _channel = 0, _max_sec = -1) {
    if (_note_name == "" || _note_name == "---") {
        return;
    }
    var _base_hz = scr_note_name_to_hz(_note_name);
    if (_base_hz <= 0) {
        return;
    }

    var _bytes = _instr.compiled.bytes;
    if (array_length(_bytes) == 0) {
        return;
    }

    // ── CACHE LOOKUP ──
    // Synthesising is ~66k iterations of the sample loop plus a buffer_create.
    // Auditioning fires on every piano keypress and on every note of a row
    // during playback, so the same handful of (instrument, note) pairs get
    // rebuilt hundreds of times a session. Render once, replay thereafter.
    if (!variable_global_exists("snd_preview_cache")) {
        global.snd_preview_cache = ds_map_create();
    }
    var _ck = scr_sound_preview_cache_key(_instr, _note_name, _max_sec);
    if (ds_map_exists(global.snd_preview_cache, _ck)) {
        scr_sound_preview_free_channel(_channel);
        var _hit = global.snd_preview_cache[? _ck];
        global.snd_preview_asset[_channel]    = _hit.snd;
        global.snd_preview_buffer[_channel]   = _hit.buf;
        global.snd_preview_instance[_channel] = audio_play_sound(_hit.snd, 1, false);
        return;
    }

    // ── WALK THE BYTECODE, BUILDING A LIST OF {wave, hz, n} SEGMENTS ──
    // PAL. The C64 player is driven from a raster IRQ at 50Hz, so an
    // instrument's D-tick is 20ms, not the 16.7ms a 60Hz assumption gives.
    // Getting this wrong makes every hold — and therefore the whole
    // instrument — run 20% fast against VICE.
    var _tick_sec    = 1 / 50;
    var _rate        = 11025;
    var _max_segs    = 200;
    var _max_seconds = 3;
    var _segs        = [];
    var _total_n     = 0;
    var _total_sec   = 0;

    var _cur_wave      = 0x40;
    var _cur_offset    = 0;
    var _pc            = 0;
    var _visits        = 0;
    var _pending_dirty = false;   // true when a WAVE/NOTE changed since the last flushed (D) segment

    while (_pc < array_length(_bytes) && _visits < _max_segs && _total_sec < _max_seconds) {
        _visits += 1;
        var _op = _bytes[_pc];

        if (_op == 0x00) {
            // A WAVE change with no D since the last one still needs to be
            // heard — flush the state it's about to replace as a 1-tick
            // blip first, so a run of $xx commands with no holds between
            // them plays each one in sequence instead of only the last.
            if (_pending_dirty) {
                var _fw_hz = _base_hz * power(2, _cur_offset / 12);
                var _fw_n  = max(1, round(_tick_sec * _rate));
                array_push(_segs, { wave: _cur_wave, hz: _fw_hz, n: _fw_n });
                _total_n   += _fw_n;
                _total_sec += _tick_sec;
            }
            _cur_wave      = _bytes[_pc + 1];
            _pending_dirty = true;
            _pc += 2;

        } else if (_op == 0x01) {
            if (_pending_dirty) {
                var _fn_hz = _base_hz * power(2, _cur_offset / 12);
                var _fn_n  = max(1, round(_tick_sec * _rate));
                array_push(_segs, { wave: _cur_wave, hz: _fn_hz, n: _fn_n });
                _total_n   += _fn_n;
                _total_sec += _tick_sec;
            }
            var _raw_off = _bytes[_pc + 1];
            _cur_offset    = (_raw_off > 127) ? (_raw_off - 256) : _raw_off;
            _pending_dirty = true;
            _pc += 2;

        } else if (_op == 0x02) {
            var _hold_ticks = _bytes[_pc + 1];
            var _seg_hz     = _base_hz * power(2, _cur_offset / 12);
            var _seg_sec    = _hold_ticks * _tick_sec;
            var _seg_n      = max(1, round(_seg_sec * _rate));
            array_push(_segs, { wave: _cur_wave, hz: _seg_hz, n: _seg_n });
            _total_n       += _seg_n;
            _total_sec     += _seg_sec;
            _pending_dirty  = false;
            _pc += 2;

        } else if (_op == 0x03) {
            _pc = _bytes[_pc + 1];

        } else {
            break;
        }
    }

    if (_pending_dirty) {
        // Whatever WAVE/NOTE state was current when the instrument ended
        // (hit --- or ran out of commands) still needs its 1-tick blip.
        var _fe_hz = _base_hz * power(2, _cur_offset / 12);
        var _fe_n  = max(1, round(_tick_sec * _rate));
        array_push(_segs, { wave: _cur_wave, hz: _fe_hz, n: _fe_n });
        _total_n   += _fe_n;
        _total_sec += _tick_sec;
    }

    if (array_length(_segs) == 0) {
        return;
    }

    // ── SID ADSR TIMING — standard published rate tables, milliseconds per
    // 0-15 step. Decay and Release share one table on real SID hardware. ──
    var _attack_ms_table = [2, 8, 16, 24, 38, 56, 68, 80, 100, 250, 500, 800, 1000, 3000, 5000, 8000];
    var _decrel_ms_table = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000];

    var _atk = clamp(variable_struct_exists(_instr, "attack")  ? _instr.attack  : 0, 0, 15);
    var _dec = clamp(variable_struct_exists(_instr, "decay")   ? _instr.decay   : 8, 0, 15);
    var _sus = clamp(variable_struct_exists(_instr, "sustain") ? _instr.sustain : 8, 0, 15);
    var _rel = clamp(variable_struct_exists(_instr, "release") ? _instr.release : 0, 0, 15);

    var _attack_n  = max(1, round((_attack_ms_table[_atk] / 1000) * _rate));
    var _decay_n   = max(1, round((_decrel_ms_table[_dec] / 1000) * _rate));
    var _release_n = max(1, round((_decrel_ms_table[_rel] / 1000) * _rate));
    var _sus_level = _sus / 15;

    var _gate_on_n = _total_n;   // combined D-tick hold length — the gated note duration

    // Work out where the envelope actually is when the gate drops, so the
    // release tail can be sized to the ground it has left to cover rather
    // than always the full table duration. Mirrors the envelope maths in the
    // sample loop below — keep the two in step if either changes.
    var _lvl_gate_off = _sus_level;
    if (_gate_on_n < _attack_n) {
        _lvl_gate_off = _gate_on_n / _attack_n;
    } else if (_gate_on_n < _attack_n + _decay_n) {
        var _dp_g  = (_gate_on_n - _attack_n) / _decay_n;
        var _dc_g  = max(0, 1 - _dp_g);
        _dc_g      = _dc_g * _dc_g * _dc_g;
        _lvl_gate_off = _sus_level + ((1 - _sus_level) * _dc_g);
    }
    var _buf_n = _gate_on_n + max(1, round(_release_n * _lvl_gate_off));

    // Trim to the caller's cap. The envelope maths below is unchanged — it
    // still computes attack/decay/sustain/release against the FULL timeline,
    // so the samples that do get rendered are identical to the untrimmed
    // version. This only stops generating the tail that would be cut off.
    if (_max_sec > 0) {
        var _cap_n = round(_max_sec * _rate);
        if (_cap_n < 1) {
            _cap_n = 1;
        }
        if (_buf_n > _cap_n) {
            _buf_n = _cap_n;
        }
    }

    var _seg_wave_name = function(_w) {
        if (_w & 0x80) return "NOISE";
        if (_w & 0x40) return "SQUARE";
        if (_w & 0x20) return "SAW";
        if (_w & 0x10) return "TRIANGLE";
        return "SQUARE";
    };

    // Free the PREVIOUS audition on this channel — asset and buffer both.
    // Shared with scr_sound_preview_play, which writes the same globals.
    scr_sound_preview_free_channel(_channel);

    var _buf = buffer_create(_buf_n * 2, buffer_fixed, 2);   // 16-bit mono

    var _seg_idx     = 0;
    var _seg_remain  = _segs[0].n;
    var _seg_wave    = _seg_wave_name(_segs[0].wave);
    var _phase       = 0;
    var _phase_step  = _segs[0].hz / _rate;

    for (var _i = 0; _i < _buf_n; _i++) {
        if (_i < _gate_on_n && _seg_remain <= 0 && _seg_idx < array_length(_segs) - 1) {
            _seg_idx    += 1;
            _seg_remain  = _segs[_seg_idx].n;
            _seg_wave    = _seg_wave_name(_segs[_seg_idx].wave);
            _phase_step  = _segs[_seg_idx].hz / _rate;
        }

        var _t = _phase - floor(_phase);
        var _s = 0;
        switch (_seg_wave) {
            case "SAW":      _s = (_t * 2) - 1; break;
            case "TRIANGLE": _s = (_t < 0.5) ? (_t * 4 - 1) : (3 - _t * 4); break;
            case "NOISE":    _s = random_range(-1, 1); break;
            default:         _s = (_t < 0.5) ? 1 : -1; break;
        }

        // ── ADSR ENVELOPE ──
        var _env;
        if (_i < _attack_n) {
            _env = _i / _attack_n;
        } else if (_i < _attack_n + _decay_n) {
            // Decay shares the SID's envelope hardware and rate table with
            // release, so it has the same exponential shape: steep at first,
            // then crawling toward the sustain level. Modelling it linearly
            // made it read as far too slow — the fall spent most of its time
            // in the upper half of the range where the real chip is already
            // through it. Cubed progress matches the curve, same as release.
            var _dprog  = (_i - _attack_n) / _decay_n;
            var _dcurve = max(0, 1 - _dprog);
            _dcurve     = _dcurve * _dcurve * _dcurve;
            _env        = _sus_level + ((1 - _sus_level) * _dcurve);
        } else if (_i < _gate_on_n) {
            _env = _sus_level;
        } else {
            // Release starts from wherever the envelope ACTUALLY was when the
            // gate dropped, not from _sus_level. With a short instrument the
            // decay ramp may not have reached sustain yet; with sustain 0 the
            // level may already be silent. Recompute the level at gate-off so
            // the preview matches what the SID does.
            var _lvl_at_gate_off = _sus_level;
            if (_gate_on_n < _attack_n) {
                _lvl_at_gate_off = _gate_on_n / _attack_n;
            } else if (_gate_on_n < _attack_n + _decay_n) {
                var _dp_off = (_gate_on_n - _attack_n) / _decay_n;
                var _dc_off = max(0, 1 - _dp_off);
                _dc_off     = _dc_off * _dc_off * _dc_off;
                _lvl_at_gate_off = _sus_level + ((1 - _sus_level) * _dc_off);
            }
            // The SID's envelope generator traverses at a fixed RATE, not
            // over a fixed duration — the published release times assume a
            // full-scale fall from peak. Releasing from a lower level covers
            // less ground and finishes proportionally sooner, so scale the
            // ramp length by where the envelope actually was at gate-off.
            // Without this a half-height release still took the full table
            // duration, which is most of why the preview outran VICE.
            // The SID's envelope output is exponential, not linear: it falls
            // steeply at first then crawls, so it is perceptually gone long
            // before the nominal release time elapses. A linear ramp stays
            // audible almost to the end, which is why the preview's tails
            // outlasted VICE's even after scaling for the gate-off level.
            // Cubing the linear progress approximates the curve closely
            // enough for an audition without modelling the real counter.
            var _rel_n_eff = max(1, _release_n * _lvl_at_gate_off);
            var _rprog     = (_i - _gate_on_n) / _rel_n_eff;
            var _rcurve    = max(0, 1 - _rprog);
            _env           = _lvl_at_gate_off * _rcurve * _rcurve * _rcurve;
        }

        var _amp = 0.30;
        var _val = clamp(round(_s * _env * _amp * 32767), -32768, 32767);
        buffer_write(_buf, buffer_s16, _val);

        _phase += _phase_step;
        if (_i < _gate_on_n) {
            _seg_remain -= 1;
        }
    }

    var _snd = audio_create_buffer_sound(_buf, buffer_s16, _rate, 0, buffer_get_size(_buf), audio_mono);

    // Store before playing. Entries are owned by the CACHE from here on —
    // scr_sound_preview_free_channel only stops playback, it must not free
    // these, or the next hit would play a destroyed asset.
    //
    // Flushed wholesale at the cap rather than evicted LRU: tracking access
    // order costs more bookkeeping than it saves, and a full rebuild of the
    // dozen notes actually in use is a fraction of a second.
    if (ds_map_size(global.snd_preview_cache) >= 128) {
        scr_sound_preview_cache_clear();
    }
    global.snd_preview_cache[? _ck] = { snd: _snd, buf: _buf };

    global.snd_preview_asset[_channel]    = _snd;
    global.snd_preview_buffer[_channel]   = _buf;
    global.snd_preview_instance[_channel] = audio_play_sound(_snd, 1, false);
}