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
function scr_sound_instrument_preview_play(_instr, _note_name, _channel = 0, _max_sec = -1, _prepare_only = false) {
    if (_note_name == "" || _note_name == "---") {
        return;
    }
    var _base_hz = scr_note_name_to_hz(_note_name);
    if (_base_hz <= 0) {
        return;
    }

    var _bytes = scr_instrument_ensure_compiled(_instr).bytes;
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
        if (!_prepare_only) scr_sound_preview_free_channel(_channel);
        var _hit = global.snd_preview_cache[? _ck];
        _hit.last_used = get_timer();
        if (_prepare_only) return;
        global.snd_preview_asset[_channel]    = _hit.snd;
        global.snd_preview_buffer[_channel]   = _hit.buf;
        global.snd_preview_instance[_channel] = audio_play_sound(_hit.snd, 1, false);
        if (variable_struct_exists(_hit, "follow")) scr_sound_instrument_follow_start(_instr, _channel, _hit.follow, _hit.follow_period);
        return;
    }

    // ── reSID RENDER ──
    // The note is walked exactly as the compiled player walks it and the
    // resulting SID register writes are rendered by the sid64 extension.
    // Falls through to the GML synth below only when the extension is absent.
    if (global.sid64_ok) {
        var _sid_out = scr_sid64_render_note(_instr, _note_name, _max_sec);
        if (is_struct(_sid_out)) {
            if (!_prepare_only) scr_sound_preview_free_channel(_channel);
            scr_sound_preview_cache_store(_ck, _sid_out.snd, _sid_out.buf);
            var _entry = global.snd_preview_cache[? _ck];
            _entry.follow = _sid_out.follow;
            _entry.follow_period = SID64_FRAME_US;
            if (_prepare_only) return;
            global.snd_preview_asset[_channel]    = _sid_out.snd;
            global.snd_preview_buffer[_channel]   = _sid_out.buf;
            global.snd_preview_instance[_channel] = audio_play_sound(_sid_out.snd, 1, false);
            scr_sound_instrument_follow_start(_instr, _channel, _sid_out.follow, SID64_FRAME_US);
            return;
        }
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

    var _cur_wave = 0x41;
    var _freq = round(_base_hz * 16777216 / 985248);
    var _pw = scr_sid64_instr_field(_instr, "pulse_width", 2048) & 4095;
    var _slide = 0;
    var _pulse_slide = 0;
    var _pc = 0, _repeat_left = 0;
    var _hold = 0;
    var _active = true;
    var _raw_gate = false;
    var _follow = [];
    var _follow_hold = -1;
    for (var _frame = 0; _frame < 150 && _active; _frame++) {
        var _follow_pcs = [];
        if (_hold > 0) { _hold -= 1; _follow_pcs = [_follow_hold]; }
        else {
            var _guard = 0;
            while (_active && _guard < 64) {
                _guard += 1;
                if (_pc >= array_length(_bytes)) { _active = false; break; }
                array_push(_follow_pcs, _pc);
                var _op = _bytes[_pc];
                var _arg = (_pc + 1 < array_length(_bytes)) ? _bytes[_pc + 1] : 0;
                var _word = _arg;
                if (_op >= 5 && _pc + 2 < array_length(_bytes)) _word |= _bytes[_pc + 2] << 8;
                if (_op == 0) { _cur_wave = _arg | 1; _pc += 2; }
                else if (_op == 1) {
                    var _off = _arg > 127 ? _arg - 256 : _arg;
                    _freq = round(_base_hz * power(2, _off / 12) * 16777216 / 985248);
                    _pc += 2;
                } else if (_op == 2) { _follow_hold = _pc; _hold = max(0, _arg - 1); _pc += 2; break; }
                else if (_op == 13) {
                    if (_repeat_left == 0) _repeat_left = _bytes[_pc+3]+1;
                    _repeat_left--;
                    if (_repeat_left > 0) _pc = _word; else _pc += 4;
                }
                else if (_op == 3 || _op == 5) _pc = _word;
                else if (_op == 6) { _freq = (_freq + _word) & 65535; _pc += 3; }
                else if (_op == 7) { _pw = _word & 4095; _pc += 3; }
                else if (_op == 8) { _slide = _word; _pc += 3; }
                else if (_op == 9) { _pulse_slide = _word; _pc += 3; }
                else if (_op == 10) { _cur_wave = _arg; _raw_gate = true; _pc += 2; }
                else _active = false;
            }
            if (_guard >= 64) _active = false;
        }
        if (!_active) break;
        array_push(_follow, { pcs: _follow_pcs });
        _freq = (_freq + _slide) & 65535;
        _pw = (_pw + _pulse_slide) & 4095;
        var _n = round((_frame + 1) * _rate / 50) - round(_frame * _rate / 50);
        array_push(_segs, { wave: _cur_wave, hz: _freq * 985248 / 16777216, n: _n, pw: _pw });
        _total_n += _n;
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
    if (!_prepare_only) scr_sound_preview_free_channel(_channel);

    var _buf = buffer_create(_buf_n * 2, buffer_fixed, 2);   // 16-bit mono

    var _seg_idx     = 0;
    var _seg_remain  = _segs[0].n;
    var _seg_wave    = _seg_wave_name(_segs[0].wave);
    var _phase       = 0;
    var _duty = _segs[0].pw / 4096;
    var _phase_step  = _segs[0].hz / _rate;

    var _seg_count = array_length(_segs);
    var _raw_env = 0;
    var _raw_stage = 0;
    var _raw_was_gate = false;
    var _rel_n_eff = max(1, _release_n * _lvl_gate_off);
    for (var _i = 0; _i < _buf_n; _i++) {
        if (_i < _gate_on_n && _seg_remain <= 0 && _seg_idx < _seg_count - 1) {
            _seg_idx    += 1;
            _seg_remain  = _segs[_seg_idx].n;
            _seg_wave    = _seg_wave_name(_segs[_seg_idx].wave);
            _phase_step  = _segs[_seg_idx].hz / _rate;
            _duty = _segs[_seg_idx].pw / 4096;
        }

        var _t = _phase - floor(_phase);
        var _s = 0;
        switch (_seg_wave) {
            case "SAW":      _s = (_t * 2) - 1; break;
            case "TRIANGLE": _s = (_t < 0.5) ? (_t * 4 - 1) : (3 - _t * 4); break;
            case "NOISE":    _s = random_range(-1, 1); break;
            default:         _s = (_t < _duty) ? 1 : -1; break;
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
            // Gate-off level and effective release length are invariant.
            // Reuse the values computed once before the sample loop.
            var _rprog     = (_i - _gate_on_n) / _rel_n_eff;
            var _rcurve    = max(0, 1 - _rprog);
            _env           = _lvl_gate_off * _rcurve * _rcurve * _rcurve;
        }

        // The fallback has a simplified envelope, but raw gate transitions
        // must still release/retrigger it while the program continues.
        if (_raw_gate) {
            var _gate = (_i < _gate_on_n) && ((_segs[_seg_idx].wave & 1) != 0);
            if (_gate != _raw_was_gate) _raw_stage = _gate ? 0 : 3;
            _raw_was_gate = _gate;
            if (!_gate) _raw_stage = 3;
            if (_raw_stage == 0) {
                _raw_env = min(1, _raw_env + 1 / _attack_n);
                if (_raw_env >= 1) _raw_stage = 1;
            } else if (_raw_stage == 1) {
                _raw_env = max(_sus_level, _raw_env - (1 - _sus_level) / _decay_n);
                if (_raw_env <= _sus_level) _raw_stage = 2;
            } else if (_raw_stage == 2) _raw_env = _sus_level;
            else _raw_env = max(0, _raw_env - 1 / _release_n);
            _env = _raw_env;
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

    scr_sound_preview_cache_store(_ck, _snd, _buf);
    var _entry = global.snd_preview_cache[? _ck];
    _entry.follow = _follow;
    _entry.follow_period = 20000;
    if (_prepare_only) return;

    global.snd_preview_asset[_channel]    = _snd;
    global.snd_preview_buffer[_channel]   = _buf;
    global.snd_preview_instance[_channel] = audio_play_sound(_snd, 1, false);
    scr_sound_instrument_follow_start(_instr, _channel, _follow, 20000);
}