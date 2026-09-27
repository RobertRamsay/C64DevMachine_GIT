/// sid64 — reSID-backed audio for the Music Maker and SFX Maker previews.
///
/// A preview note is no longer synthesised in GML. Instead this walks the
/// note exactly as the MACRO_SID_SONG player would — hard restart, instrument
/// header (AD, SR, PW), then one instrument command step per 50 Hz frame —
/// records the SID register writes each frame, and hands that log to the
/// sid64 extension (reSID / reSID-fp from GoatTracker) to render. Waveforms,
/// combined waveforms, pulse width, noise and the real ADSR curves (including
/// the hard-restart timing) therefore come from the chip model, not a guess.
///
/// Each note is rendered on its own voice 1, so cross-voice features (ring mod,
/// sync, filter) are not heard — the player has no filter commands anyway.
///
/// global.sid64_ok is false when the extension isn't present on this platform;
/// callers then fall back to the old GML synth.

#macro SID64_PAL_CLOCK        985248
#macro SID64_RATE             44100
#macro SID64_CYCLES_PER_FRAME 19656
#macro SID64_MAX_FRAMES       300    // 6 s — hard cap on any one preview
#macro SID64_GATE_CAP         150    // 3 s — a looping instrument's gate drops here on a bare audition
#macro SID64_PLAIN_GATE       8      // no-instrument note: gate held 8 frames (0.16 s, as the old beep)

/// Called once from obj_workspace_manager Create, after the sid64 globals are set.
function scr_sid64_start() {
    // Shared chromatic table — same construction as SIDSONG_NOTELO/HI in
    // scr_compile_chain, so preview and compiled player use identical values.
    var _names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
    for (var _i = 0; _i < 96; _i++) {
        var _f = scr_note_name_to_freq(_names[_i mod 12] + string(_i div 12));
        if (_f < 0) {
            _f = 0;
        }
        global.sid64_note_freq[_i] = _f;
    }

    global.sid64_ok = false;
    try {
        if (sid64_version() >= 1) {
            sid64_init(SID64_PAL_CLOCK, SID64_RATE, global.sid64_model, global.sid64_engine);
            sid64_set_gain(0.6);
            sid64_set_cycles_per_frame(SID64_CYCLES_PER_FRAME);
            global.sid64_ok = true;
        }
    } catch (_e) {
        show_debug_message("sid64: extension unavailable, previews use the GML synth (" + string(_e.message) + ")");
        global.sid64_ok = false;
    }
}

/// Re-initialise after changing global.sid64_model / global.sid64_engine.
/// Clears the preview cache because every cached sound was rendered with the old chip.
function scr_sid64_reconfigure() {
    if (!global.sid64_ok) {
        return;
    }
    scr_sound_preview_cache_clear();
    sid64_init(SID64_PAL_CLOCK, SID64_RATE, global.sid64_model, global.sid64_engine);
    sid64_set_gain(0.6);
    sid64_set_cycles_per_frame(SID64_CYCLES_PER_FRAME);
}

/// Cache-key prefix: anything that changes the rendered audio but isn't in the
/// instrument itself. Empty when the GML synth is in use.
function scr_sid64_key_prefix() {
    if (!global.sid64_ok) {
        return "";
    }
    return "R" + string(global.sid64_engine) + "M" + string(global.sid64_model)
         + "H" + string(global.sid64_hard_restart) + "|";
}

/// Reads an instrument field, or the player's default when the field is missing.
function scr_sid64_instr_field(_instr, _name, _default) {
    var _v = _instr[$ _name];
    if (is_undefined(_v)) {
        return _default;
    }
    return real(_v);
}

/// Renders one note through reSID.
/// _instr     instrument struct, or undefined for the player's no-instrument path
/// _max_sec   cap the rendered length (row playback), or -1 for the full tail
/// _plain_pw  pulse width assumed for a no-instrument note
/// Returns { snd, buf } (caller stores it in the preview cache) or undefined.
function scr_sid64_render_note(_instr, _note_name, _max_sec, _plain_pw = 0x0800) {
    if (!global.sid64_ok) {
        return undefined;
    }
    var _base = scr_sid_song_note_index(_note_name);
    if (_base < 0) {
        return undefined;
    }

    var _has_instr = is_struct(_instr);
    var _ad = 0;
    var _sr = 0;
    var _pw = _plain_pw & 0x0FFF;
    var _bytes = [];
    var _rel = 0;
    if (_has_instr) {
        var _atk = clamp(scr_sid64_instr_field(_instr, "attack", 0), 0, 15);
        var _dec = clamp(scr_sid64_instr_field(_instr, "decay", 8), 0, 15);
        var _sus = clamp(scr_sid64_instr_field(_instr, "sustain", 8), 0, 15);
        _rel = clamp(scr_sid64_instr_field(_instr, "release", 0), 0, 15);
        _ad = ((_atk << 4) | _dec) & 0xFF;
        _sr = ((_sus << 4) | _rel) & 0xFF;
        _pw = scr_sid64_instr_field(_instr, "pulse_width", 0x0800) & 0x0FFF;
        _bytes = scr_instrument_ensure_compiled(_instr).bytes;
    }
    var _nb = array_length(_bytes);

    // Release table (ms, full scale) — only used to size the tail after gate-off.
    var _rel_ms = [6, 24, 48, 72, 114, 168, 204, 240, 300, 750, 1500, 2400, 3000, 9000, 15000, 24000];

    var _limit = SID64_MAX_FRAMES;
    if (_max_sec > 0) {
        _limit = clamp(ceil(_max_sec * 50), 1, SID64_MAX_FRAMES);
    }

    var _regs = array_create(25, 0);
    _regs[24] = 0x0F;
    _regs[2] = _pw & 0xFF;          // seeds the plain-note PW; an instrument rewrites it on trigger
    _regs[3] = (_pw >> 8) & 0x0F;

    var _hr = global.sid64_hard_restart;
    var _countdown = 0;
    var _pending = true;
    var _active = false;
    var _hold = 0;
    var _pc = 0;
    var _cb = 0;
    var _fired_at = -1;
    var _gate_off_at = -1;
    var _end = _limit;
    var _fb = global.sid64_frame_buf;
    var _nf = 0;

    while (_nf < _end) {
        var _mask = (1 << 24) | (1 << 2) | (1 << 3);

        // ── Row frame: hard restart phase 1 (gate off, dummy ADSR parks the envelope) ──
        if (_nf == 0) {
            if (_hr > 0) {
                _cb = 0;
                _regs[4] = 0;
                _regs[5] = 0x0F;
                _regs[6] = 0x00;
                _mask = _mask | (1 << 4) | (1 << 5) | (1 << 6);
                _countdown = _hr;
            }
        }

        // ── Trigger: immediately without HR, else when the countdown reaches 0 ──
        var _waiting = false;
        if (_pending) {
            var _fire = false;
            if (_hr > 0) {
                _countdown -= 1;
                if (_countdown <= 0) {
                    _fire = true;
                } else {
                    _waiting = true;
                }
            } else {
                _fire = true;
            }
            if (_fire) {
                _pending = false;
                _fired_at = _nf;
                var _f0 = global.sid64_note_freq[_base];
                _regs[0] = _f0 & 0xFF;
                _regs[1] = (_f0 >> 8) & 0xFF;
                _cb = 0x41;
                _regs[4] = _cb;
                _mask = _mask | (1 << 0) | (1 << 1) | (1 << 4);
                if (_has_instr) {
                    _regs[5] = _ad;
                    _regs[6] = _sr;
                    _regs[2] = _pw & 0xFF;
                    _regs[3] = (_pw >> 8) & 0x0F;
                    _mask = _mask | (1 << 5) | (1 << 6);
                    _hold = 0;
                    _pc = 0;
                    _active = true;
                }
            }
        }

        // ── Instrument stepper — mirrors the player's per-frame walk ──
        if (!_waiting && _active) {
            if (_hold > 0) {
                _hold -= 1;
            } else {
                var _stepping = true;
                var _guard = 0;
                while (_stepping && _guard < 64) {
                    _guard += 1;
                    var _op = 0x04;
                    var _arg = 0;
                    if (_pc < _nb) {
                        _op = _bytes[_pc];
                    }
                    if (_pc + 1 < _nb) {
                        _arg = _bytes[_pc + 1] & 0xFF;
                    }
                    switch (_op) {
                        case 0x00:   // WAVE — the player always ORs the gate bit in
                            _cb = _arg | 0x01;
                            _regs[4] = _cb;
                            _mask = _mask | (1 << 4);
                            _pc += 2;
                            break;
                        case 0x01:   // NOTE — 8-bit add, then clamp >= 96 to 95 (as the 6502 does)
                            var _ni = (_arg + _base) & 0xFF;
                            if (_ni >= 96) {
                                _ni = 95;
                            }
                            var _fn = global.sid64_note_freq[_ni];
                            _regs[0] = _fn & 0xFF;
                            _regs[1] = (_fn >> 8) & 0xFF;
                            _mask = _mask | (1 << 0) | (1 << 1);
                            _pc += 2;
                            break;
                        case 0x02:   // HOLD n — this frame plus n-1 more
                            _hold = (_arg - 1) & 0xFF;
                            _pc += 2;
                            _stepping = false;
                            break;
                        case 0x03:   // LOOP — offset from the stream start
                            _pc = _arg;
                            break;
                        default:     // END — gate off, instrument idle
                            _cb = _cb & 0xFE;
                            _regs[4] = _cb;
                            _mask = _mask | (1 << 4);
                            _active = false;
                            _stepping = false;
                            break;
                    }
                }
                if (_stepping) {
                    // A loop with no hold spins forever on the 6502 too; stop it here.
                    _active = false;
                }
            }
        }

        // ── Bare audition: drop the gate on a plain note / runaway loop ──
        if (_max_sec <= 0 && _fired_at >= 0 && (_cb & 0x01) == 1) {
            var _cap = SID64_GATE_CAP;
            if (!_has_instr) {
                _cap = SID64_PLAIN_GATE;
            }
            if (_nf - _fired_at >= _cap) {
                _cb = _cb & 0xFE;
                _regs[4] = _cb;
                _mask = _mask | (1 << 4);
                _active = false;
            }
        }

        // ── Once the gate is off, render just the release tail ──
        if (_max_sec <= 0 && _fired_at >= 0 && _gate_off_at < 0 && (_cb & 0x01) == 0) {
            _gate_off_at = _nf;
            var _tail = ceil(_rel_ms[_rel] / 20) + 3;
            _end = min(_limit, _nf + 1 + _tail);
        }

        var _o = _nf * 32;
        for (var _r = 0; _r < 25; _r++) {
            buffer_poke(_fb, _o + _r, buffer_u8, _regs[_r]);
        }
        buffer_poke(_fb, _o + 25, buffer_u32, _mask);
        _nf += 1;
    }

    sid64_reset();
    sid64_settle(0x0F, 100);

    var _cap_samples = ceil(_nf * SID64_CYCLES_PER_FRAME * SID64_RATE / SID64_PAL_CLOCK) + 64;
    var _buf = buffer_create(_cap_samples * 2, buffer_fixed, 2);
    var _got = sid64_render_log(buffer_get_address(_fb), _nf, buffer_get_address(_buf), _cap_samples);
    if (_got <= 0) {
        buffer_delete(_buf);
        return undefined;
    }
    // The DLL wrote through the raw address, so GameMaker still thinks the
    // buffer is empty — audio_create_buffer_sound refuses an "empty" buffer.
    buffer_set_used_size(_buf, _got * 2);
    var _snd = audio_create_buffer_sound(_buf, buffer_s16, SID64_RATE, 0, _got * 2, audio_mono);
    return { snd: _snd, buf: _buf };
}
