/// sid64 sim — a frame-by-frame GML copy of the MACRO_SID_SONG 6502 player.
///
/// Every register write the compiled player would make is made here, in the
/// same order and on the same frame, so what reSID renders from this is what
/// the C64 plays. It reads the Music Maker data live (patterns, order,
/// instruments), so edits made during playback are heard at the next row, as
/// before. Keep this in step with scr_compile_chain's MACRO_SID_SONG case and
/// scr_sid_song_emit_fx_routines — the two are one design.
///
/// Row sentinels match the compiled pattern bytes: note 253 = +++ key on,
/// 254 = hold (empty cell), 255 = --- rest; command 255 = none.

/// A voice's full state: the 6502 player's ZP bytes plus its RAM effect tables.
function scr_sid64_sim_voice_new() {
    return {
        // instrument stepper (ZP V block)
        instr    : undefined,   // instrument struct being stepped
        bytes    : [],          // its compiled command stream
        repeat_left: 0,
        pc       : 0,
        display_pcs: [],
        display_hold: -1,
        display_compiled: undefined,
        slide : 0,
        pulse_slide : 0,
        lane_pos : [0, 0],       // ~PITCH / ~PULSE record index into bytes
        lane_count : [0, 0],     // frames left on the record; 0 = table idle
        lane_off   : [0, 0],     // table start offset in bytes
        lane_key   : ["", ""],   // table contents (shared tables match by content)
        lane_keep  : [0, 0],     // frames left saved by the last new note
        lane_speed : [0, 0],     // speed saved by the last new note
        hold     : 0,
        base     : 0,           // base note index (0-95)
        active   : false,
        cb       : 0,           // $D404 shadow
        // hard restart (ZP H block)
        hr_note  : 0,
        hr_instr : undefined,
        hr_cd    : 0,
        // effect tables (RAM)
        freq     : 0,           // base pitch, 16-bit
        fx       : 0,
        fxv      : 0,
        tgt      : 0,           // slide-to-note target, 16-bit
        cvs      : 0,
        cvd      : 0,
        ivdl     : 0,
        ivs      : 0,
        ivp      : 0,
        vbc      : 0,
        vdir     : 0,
        voff     : 0,           // vibrato offset, kept as a 16-bit two's-complement value
        pcmd     : 0,
        pval     : 0,
        pw       : 0,           // pulse-width shadow, 12-bit (8XX / 9XX)
        was_on   : false        // voice was enabled last frame (mute handling)
    };
}

/// _m / _song: the Music Maker meta and the song to play (undefined for a
/// bare note audition). _loop_row: loop the starting order row forever (the
/// editor's pattern playback) instead of walking the song.
function scr_sid64_sim_create(_m, _song, _loop_row, _ord, _row) {
    var _speed = 6;
    if (is_struct(_m)) {
        _speed = clamp(real(_m.play_speed), 1, 255);
    }
    var _sim = {
        chip      : 0,
        m         : _m,
        song      : _song,
        loop_row  : _loop_row,
        ord       : _ord,
        row       : _row,
        tick      : 1,           // seek: the first frame lands on the row
        spd       : _speed,
        hr        : global.sid64_hard_restart,
        regs      : array_create(25, 0),
        mask      : 0,
        finished  : false,
        shown_ord : _ord,        // the row that sounded on the last row frame
        shown_row : _row,
        fcut      : 0x400,       // filter cutoff, 11-bit
        f17       : 0,           // $D417 copy (resonance + routing)
        f18       : 0x0F,        // $D418 copy (mode + volume)
        voices    : [scr_sid64_sim_voice_new(), scr_sid64_sim_voice_new(), scr_sid64_sim_voice_new()],
        note_freq : global.sid64_note_freq
    };
    // An asset's own note table (imported tuning) replaces the shared one.
    if (is_struct(_m)) {
        var _nt = _m[$ "note_table"];
        if (is_array(_nt) && array_length(_nt) == 96) _sim.note_freq = _nt;
    }
    // init: the song's filter settings (mode + full volume, resonance, cutoff;
    // no voice routed yet), or plain full volume for an audition.
    if (is_struct(_m)) {
        var _fm = _m[$ "filt_mode"];
        var _fr = _m[$ "filt_res"];
        var _fc = _m[$ "filt_cut"];
        if (!is_undefined(_fm)) {
            _sim.f18 = ((real(_fm) & 0x0F) << 4) | 0x0F;
        }
        if (!is_undefined(_fr)) {
            _sim.f17 = (real(_fr) & 0x0F) << 4;
        }
        if (!is_undefined(_fc)) {
            _sim.fcut = clamp(real(_fc), 0, 2047);
        }
        scr_sid64_sim_write(_sim, 0x17, _sim.f17);
        scr_sid64_sim_cut(_sim);
    }
    scr_sid64_sim_write(_sim, 0x18, _sim.f18);
    return _sim;
}

/// The player's fcut: 11-bit cutoff to $D415 (bits 0-2) / $D416 (bits 3-10).
function scr_sid64_sim_cut(_sim) {
    scr_sid64_sim_write(_sim, 0x15, _sim.fcut & 0x07);
    scr_sid64_sim_write(_sim, 0x16, (_sim.fcut >> 3) & 0xFF);
}

function scr_sid64_sim_write(_sim, _reg, _val) {
    _sim.regs[_reg] = _val & 0xFF;
    _sim.mask = _sim.mask | (1 << _reg);
}

/// Voice enabled? Songs follow the asset's VOICES buttons; an audition always plays.
function scr_sid64_sim_voice_on(_sim, _v) {
    if (!is_struct(_sim.m)) {
        return true;
    }
    return ((scr_music_sid_mask(_sim.m, _sim.chip) & (1 << _v)) != 0);
}

/// The compiled player's per-order-row length: longest enabled voice's
/// pattern, or the row's forced length; 64 when nothing is assigned.
function scr_sid64_sim_row_len(_sim, _orow) {
    return scr_music_sid_length(_sim.m, _orow);
}

/// Instrument byte → struct, or undefined for "no instrument".
function scr_sid64_sim_instr(_sim, _idx) {
    if (!is_struct(_sim.m)) {
        return undefined;
    }
    if (_idx < 0 || _idx >= array_length(_sim.m.instruments)) {
        return undefined;
    }
    return _sim.m.instruments[_idx];
}

/// Trigger a note on voice _v (the player's immediate / HR-phase-2 path).
function scr_sid64_sim_trigger(_sim, _v, _instr) {
    var _vc = _sim.voices[_v];
    var _r0 = _v * 7;
    var _f  = _sim.note_freq[_vc.base];
    _vc.instr = _instr;
    _vc.display_pcs = [];
    _vc.display_hold = -1;
    _vc.repeat_left = 0;
    // Save each table's position for a keep-running table, then stop it.
    _vc.lane_keep[0] = _vc.lane_count[0];
    _vc.lane_keep[1] = _vc.lane_count[1];
    _vc.lane_speed[0] = _vc.slide;
    _vc.lane_speed[1] = _vc.pulse_slide;
    _vc.slide = 0;
    _vc.pulse_slide = 0;
    _vc.lane_count[0] = 0;
    _vc.lane_count[1] = 0;
    if (!is_struct(_instr)) {
        // No instrument: pitch, plain pulse gate; AD/SR/PW left as they are.
        _vc.freq = _f;
        _vc.cb = 0x41;
        scr_sid64_sim_write(_sim, _r0 + 4, 0x41);
        _vc.active = false;
        _vc.ivs = 0;
        _vc.ivp = 0;
        _vc.voff = 0;
        return;
    }
    // Gate first, then AD/SR (the ADSR-bug fix), PW, vibrato header, pitch.
    _vc.cb = 0x41;
    scr_sid64_sim_write(_sim, _r0 + 4, 0x41);
    var _atk = clamp(scr_sid64_instr_field(_instr, "attack", 0), 0, 15);
    var _dec = clamp(scr_sid64_instr_field(_instr, "decay", 8), 0, 15);
    var _sus = clamp(scr_sid64_instr_field(_instr, "sustain", 8), 0, 15);
    var _rel = clamp(scr_sid64_instr_field(_instr, "release", 0), 0, 15);
    var _pw  = floor(scr_sid64_instr_field(_instr, "pulse_width", 0x0800)) & 0x0FFF;
    scr_sid64_sim_write(_sim, _r0 + 5, (_atk << 4) | _dec);
    scr_sid64_sim_write(_sim, _r0 + 6, (_sus << 4) | _rel);
    scr_sid64_sim_write(_sim, _r0 + 2, _pw & 0xFF);
    scr_sid64_sim_write(_sim, _r0 + 3, (_pw >> 8) & 0x0F);
    _vc.pw = _pw;
    _vc.ivdl = clamp(floor(scr_sid64_instr_field(_instr, "vib_delay", 0)), 0, 255);
    _vc.ivs  = clamp(floor(scr_sid64_instr_field(_instr, "vib_speed", 0)), 0, 15);
    _vc.ivp  = (clamp(floor(scr_sid64_instr_field(_instr, "vib_depth", 0)), 0, 15) * 4) & 0x7F;
    // FILTER ON routes this voice through the filter; OFF takes it out.
    // Song playback only: a bare audition has no song filter set up, and a
    // routed voice with no filter mode is silent on the SID.
    if (is_struct(_sim.m)) {
        if (scr_sid64_instr_field(_instr, "filt", 0) != 0) {
            _sim.f17 = _sim.f17 | (1 << _v);
        } else {
            _sim.f17 = _sim.f17 & ~(1 << _v);
        }
        scr_sid64_sim_write(_sim, 0x17, _sim.f17);
    }
    _vc.vbc  = 0xFF;
    _vc.voff = 0;
    _vc.vdir = 0;
    _vc.freq = _f;
    _vc.instr  = _instr;
    _vc.display_compiled = scr_instrument_ensure_compiled(_instr);
    _vc.bytes = _vc.display_compiled.bytes;
    _vc.pc     = 0;
    _vc.hold   = 0;
    _vc.active = true;
}

/// Process one pattern row on voice _v (note byte, instrument struct or
/// undefined, command byte, value).
function scr_sid64_sim_row(_sim, _v, _note, _instr, _cmd, _val) {
    var _vc = _sim.voices[_v];
    var _r0 = _v * 7;
    if (_note == 254) {
        // hold — the command still applies
    } else if (_note == 253) {
        // +++ key on: gate back on from the shadow
        if (_vc.active == 2) _vc.active = true;
        _vc.cb = _vc.cb | 0x01;
        scr_sid64_sim_write(_sim, _r0 + 4, _vc.cb);
    } else if (_note == 255) {
        // Release: keep the instrument running; state 2 latches the gate off.
        _vc.cb = _vc.cb & 0xFE;
        scr_sid64_sim_write(_sim, _r0 + 4, _vc.cb);
        if (_vc.active) _vc.active = 2;
        _vc.hr_cd = 0;
    } else if (_cmd == 3) {
        // slide to this note: set the target, no trigger
        _vc.tgt = _sim.note_freq[_note];
    } else if (_cmd == 19) {
        scr_sid64_sim_tie(_sim, _v, _note, _instr);
    } else {
        _vc.fx = 0;              // a new note ends the continuous effect
        _vc.base = _note;
        if (_sim.hr > 0 && !(is_struct(_instr) && scr_instrument_ensure_compiled(_instr).no_hr)) {
            // hard restart phase 1: park the envelope, trigger _hr frames later
            _vc.hr_instr = _instr;
            _vc.hr_note  = _note;
            _vc.hr_cd    = _sim.hr;
            _vc.cb = 0;
            scr_sid64_sim_write(_sim, _r0 + 4, 0);
            _vc.active = false;
            scr_sid64_sim_write(_sim, _r0 + 5, 0x0F);
            scr_sid64_sim_write(_sim, _r0 + 6, 0x00);
        } else {
            _vc.hr_cd = 0;
            scr_sid64_sim_trigger(_sim, _v, _instr);
        }
    }
    // An empty release row must not cancel an already running vibrato.
    if (!(_vc.active == 2 && _cmd == 255 && _vc.fx == 4)) scr_sid64_sim_cmd(_sim, _v, _cmd, _val);
}

/// The player's cmdr routine.
function scr_sid64_sim_cmd(_sim, _v, _cmd, _val) {
    var _vc = _sim.voices[_v];
    if (_cmd >= 16 && _cmd <= 18) {
        _vc.fx = 0;
        _vc.pcmd = _cmd;
        _vc.pval = _val;
        return;
    }
    // Effects 1-4 last for their own row only.
    if (_cmd == 255) {
        _vc.fx = 0;
        return;
    }
    if (_cmd == 9) {
        _vc.fx  = 9;            // pulse sweep, an effect like 1-4
        _vc.fxv = _val;
        return;
    }
    if (_cmd >= 5) {
        _vc.fx = 0;
    }
    if (_cmd == 0) {
        _vc.fx = 0;
        return;
    }
    if (_cmd < 5) {
        if (_cmd == 4 && _vc.fx != 4) {
            _vc.vbc  = 0xFF;
            _vc.voff = 0;
            _vc.vdir = 0;
        }
        _vc.fx  = _cmd;
        _vc.fxv = _val;
        if (_cmd <= 3) {
            _vc.fxv = _val * 4;     // pitch speed: XX * 4 per frame
        }
        if (_cmd == 4) {
            _vc.cvd = ((_val & 0x0F) * 4) & 0xFF;
            _vc.cvs = (_val >> 4) & 0x0F;
        }
        return;
    }
    if (_cmd < 9) {
        _vc.pcmd = _cmd;
        _vc.pval = _val;
        return;
    }
    if (_cmd == 0x0A) {
        _sim.fcut = (_val << 3) & 0x7FF;
        scr_sid64_sim_cut(_sim);
        return;
    }
    if (_cmd == 0x0B) {
        _sim.f17 = (_sim.f17 & 0x0F) | (_val & 0xF0);
        scr_sid64_sim_write(_sim, 0x17, _sim.f17);
        return;
    }
    if (_cmd == 0x0C) {
        _vc.fx  = 0x0C;         // cutoff sweep, an effect for this row
        _vc.fxv = _val;
        return;
    }
    if (_cmd == 0x0D) {
        _sim.f18 = _val;
        scr_sid64_sim_write(_sim, 0x18, _val);
        return;
    }
    if (_cmd == 0x0E) {
        _sim.f18 = (_sim.f18 & 0x0F) | ((_val & 0x0F) << 4);
        scr_sid64_sim_write(_sim, 0x18, _sim.f18);
        return;
    }
    if (_cmd == 0x0F && _val != 0) {
        _sim.spd = _val;
        if (variable_struct_exists(_sim, "shared_clock")) _sim.shared_clock.next = _val;
    }
}

/// The instrument stepper for one voice (runs when the voice is active).
function scr_sid64_sim_step(_sim, _v) {
    var _vc = _sim.voices[_v];
    var _r0 = _v * 7;
    if (!_vc.active) {
        _vc.display_pcs = [];
        return;
    }
    if (_vc.hold > 0) {
        _vc.hold -= 1;
        _vc.display_pcs = [_vc.display_hold];
        return;
    }
    _vc.display_pcs = [];
    var _nb = array_length(_vc.bytes);
    var _guard = 0;
    while (_guard < 64) {
        _guard += 1;
        array_push(_vc.display_pcs, _vc.pc);
        var _op = 0x04;
        var _arg = 0;
        if (_vc.pc < _nb) {
            _op = _vc.bytes[_vc.pc];
        }
        if (_vc.pc + 1 < _nb) {
            _arg = _vc.bytes[_vc.pc + 1] & 0xFF;
        }
        if (_op == 0x00) {
            // WAVE: normal trigger gates on; released voices stay released.
            _vc.cb = (_vc.active == 2) ? (_arg & 0xFE) : (_arg | 0x01);
            scr_sid64_sim_write(_sim, _r0 + 4, _vc.cb);
            _vc.pc += 2;
        } else if (_op == 0x01) {
            // NOTE — 8-bit add, >= 96 clamps to 95
            var _ni = (_arg + _vc.base) & 0xFF;
            if (_ni >= 96) {
                _ni = 95;
            }
            _vc.freq = _sim.note_freq[_ni];
            _vc.pc += 2;
        } else if (_op == 0x02) {
            _vc.display_hold = _vc.pc;
            // HOLD n — this frame plus n-1
            _vc.hold = (_arg - 1) & 0xFF;
            _vc.pc += 2;
            return;
        } else if (_op == 13) {
            if (_vc.repeat_left == 0) _vc.repeat_left = _vc.bytes[_vc.pc + 3] + 1;
            _vc.repeat_left--;
            if (_vc.repeat_left > 0) _vc.pc = _arg | ((_vc.bytes[_vc.pc + 2] & 255) << 8);
            else _vc.pc += 4;
        } else if (_op == 0x05) {
            _vc.pc = _arg | ((_vc.bytes[_vc.pc + 2] & 255) << 8);
        } else if (_op == 0x06) {
            var _delta = _arg | ((_vc.bytes[_vc.pc + 2] & 255) << 8);
            _vc.freq = (_vc.freq + _delta) & 65535;
            _vc.pc += 3;
        } else if (_op == 0x07) {
            _vc.pw = (_arg | ((_vc.bytes[_vc.pc + 2] & 15) << 8));
            scr_sid64_sim_write(_sim, _r0 + 2, _vc.pw & 255);
            scr_sid64_sim_write(_sim, _r0 + 3, _vc.pw >> 8);
            _vc.pc += 3;
        } else if (_op == 0x08 || _op == 0x09) {
            var _d = _arg | ((_vc.bytes[_vc.pc + 2] & 255) << 8);
            if (_op == 0x08) _vc.slide = _d; else _vc.pulse_slide = _d;
            _vc.pc += 3;
        } else if (_op == 10) {
            _vc.cb = (_vc.active == 2) ? (_arg & 0xFE) : _arg;
            scr_sid64_sim_write(_sim, _r0 + 4, _vc.cb);
            _vc.pc += 2;
        } else if (_op == 0x03) {
            _vc.pc = _arg;
        } else if (_op >= 14 && _op <= 17) {
            // start the pitch / pulse table; its first record loads this frame
            scr_sid64_sim_lane_start(_vc, (_op - 14) & 1, _op >= 16, _arg | ((_vc.bytes[_vc.pc + 2] & 255) << 8));
            _vc.pc += 3;
        } else {
            // END — gate off, instrument idle
            _vc.cb = _vc.cb & 0xFE;
            scr_sid64_sim_write(_sim, _r0 + 4, _vc.cb);
            _vc.active = false;
            return;
        }
    }
    // A loop with no hold would spin forever on the C64 too; stop it here.
    _vc.active = false;
}

/// The player's table start ($0E-$11). Tables are identified by their contents,
/// as the song build stores each distinct table once and starts it by address.
function scr_sid64_sim_lane_start(_vc, _k, _keep, _off) {
    var _key = "";
    var _lanes = _vc.display_compiled.lanes;
    for (var _l = 0; _l < array_length(_lanes); _l++) {
        if (_lanes[_l][0] == _off) {
            for (var _j = 0; _j < _lanes[_l][1]; _j++) _key += string(_vc.bytes[_off + _j]) + ",";
        }
    }
    if (_keep && _key == _vc.lane_key[_k]) {
        if (_vc.lane_count[_k] != 0) {
            // still running (a tie): carry on, now read from this program's copy
            _vc.lane_pos[_k] = _off + (_vc.lane_pos[_k] - _vc.lane_off[_k]);
            _vc.lane_off[_k] = _off;
            return;
        }
        if (_vc.lane_keep[_k] != 0) {
            // saved by the new note: resume where it was
            _vc.lane_count[_k] = _vc.lane_keep[_k];
            if (_k == 0) {
                _vc.slide = _vc.lane_speed[0];
            } else {
                _vc.pulse_slide = _vc.lane_speed[1];
            }
            _vc.lane_pos[_k] = _off + (_vc.lane_pos[_k] - _vc.lane_off[_k]);
            _vc.lane_off[_k] = _off;
            return;
        }
    }
    _vc.lane_pos[_k] = _off;
    _vc.lane_off[_k] = _off;
    _vc.lane_key[_k] = _key;
    _vc.lane_count[_k] = 1;
}

/// JXX tie: new pitch, and the named instrument's program if any, with no
/// re-trigger — envelope, gate, pulse width, sweeps and tables carry on.
function scr_sid64_sim_tie(_sim, _v, _note, _instr) {
    var _vc = _sim.voices[_v];
    _vc.base = _note;
    _vc.freq = _sim.note_freq[_note];
    if (is_struct(_instr)) {
        _vc.instr = _instr;
        _vc.display_compiled = scr_instrument_ensure_compiled(_instr);
        _vc.bytes = _vc.display_compiled.bytes;
        _vc.display_pcs = [];
        _vc.pc = 0;
        _vc.hold = 0;
        _vc.repeat_left = 0;
    }
}

/// The player's table step: _k 0 = ~PITCH (sets slide), 1 = ~PULSE (sets pulse_slide).
function scr_sid64_sim_lane(_vc, _k) {
    if (_vc.lane_count[_k] == 0) return;
    _vc.lane_count[_k] -= 1;
    if (_vc.lane_count[_k] != 0) return;
    var _b = _vc.bytes;
    for (var _guard = 0; _guard < 2; _guard++) {
        var _p = _vc.lane_pos[_k];
        if (_p < 0 || _p + 1 >= array_length(_b)) return;
        if (_b[_p] != 0) {
            if (_p + 2 >= array_length(_b)) return;
            _vc.lane_count[_k] = _b[_p];
            var _speed = (_b[_p + 1] & 255) | ((_b[_p + 2] & 255) << 8);
            if (_k == 0) {
                _vc.slide = _speed;
            } else {
                _vc.pulse_slide = _speed;
            }
            _vc.lane_pos[_k] = _p + 3;
            return;
        }
        if (_b[_p + 1] == 0) return;     // [0, 0]: table stops, speed stays
        _vc.lane_pos[_k] = _p - _b[_p + 1];
    }
}

/// The player's fxr routine: one-shot, portamento, vibrato, pitch output.
function scr_sid64_sim_fx(_sim, _v, _hrw) {
    var _vc = _sim.voices[_v];
    var _r0 = _v * 7;

    if (_vc.active && _hrw == 0) {
        scr_sid64_sim_lane(_vc, 0);
        scr_sid64_sim_lane(_vc, 1);
        _vc.freq = (_vc.freq + _vc.slide) & 65535;
        if (_vc.pulse_slide != 0) {
            _vc.pw = (_vc.pw + _vc.pulse_slide) & 4095;
            scr_sid64_sim_write(_sim, _r0 + 2, _vc.pw & 255);
            scr_sid64_sim_write(_sim, _r0 + 3, _vc.pw >> 8);
        }
    }
    // pending one-shot 5/6/7, once any hard restart has fired
    if (_vc.pcmd != 0 && _hrw == 0) {
        if (_vc.pcmd == 5) {
            scr_sid64_sim_write(_sim, _r0 + 5, _vc.pval);
        } else if (_vc.pcmd == 6) {
            scr_sid64_sim_write(_sim, _r0 + 6, _vc.pval);
        } else if (_vc.pcmd == 7) {
            _vc.cb = _vc.pval;
            scr_sid64_sim_write(_sim, _r0 + 4, _vc.pval);
        } else {
            _vc.pw = (_vc.pval << 4) & 0xFFF;
            scr_sid64_sim_write(_sim, _r0 + 2, _vc.pw & 0xFF);
            scr_sid64_sim_write(_sim, _r0 + 3, (_vc.pw >> 8) & 0x0F);
        }
        _vc.pcmd = 0;
    }

    // portamento
    if (_vc.fx == 1) {
        _vc.freq += _vc.fxv;
        if (_vc.freq > 0xFFFF) {
            _vc.freq = 0xFFFF;
        }
    } else if (_vc.fx == 2) {
        _vc.freq -= _vc.fxv;
        if (_vc.freq < 0) {
            _vc.freq = 0;
        }
    } else if (_vc.fx == 0x0C) {
        // cutoff sweep: XX sign-extended, clamped to 0-2047
        var _dct = _vc.fxv;
        if (_dct >= 0x80) {
            _dct -= 256;
        }
        _sim.fcut = clamp(_sim.fcut + _dct, 0, 2047);
        scr_sid64_sim_cut(_sim);
    } else if (_vc.fx == 9) {
        // pulse sweep: XX sign-extended, clamped to $000-$FFF
        var _dpw = _vc.fxv;
        if (_dpw >= 0x80) {
            _dpw -= 256;
        }
        _vc.pw = clamp(_vc.pw + _dpw, 0, 0xFFF);
        scr_sid64_sim_write(_sim, _r0 + 2, _vc.pw & 0xFF);
        scr_sid64_sim_write(_sim, _r0 + 3, (_vc.pw >> 8) & 0x0F);
    } else if (_vc.fx == 3) {
        if (_vc.freq < _vc.tgt) {
            _vc.freq += _vc.fxv;
            if (_vc.freq >= _vc.tgt) {
                _vc.freq = _vc.tgt;
            }
        } else if (_vc.freq > _vc.tgt) {
            _vc.freq -= _vc.fxv;
            if (_vc.freq < _vc.tgt) {
                _vc.freq = _vc.tgt;
            }
        }
    }

    // vibrato: the 4XY command's, else the instrument's after its delay
    var _vts = 0;
    var _vtd = 0;
    var _run = true;
    if (_vc.fx == 4) {
        _vts = _vc.cvs;
        _vtd = _vc.cvd;
    } else if (_vc.ivdl > 0) {
        _vc.ivdl -= 1;
        _run = false;
    } else {
        _vts = _vc.ivs;
        _vtd = _vc.ivp;
    }
    if (_vts == 0 || _vtd == 0) {
        _run = false;
    }
    if (_run) {
        if (_vc.vbc == 0xFF) {
            _vc.vbc = _vts >> 1;
        }
        if (_vc.vdir == 0) {
            _vc.voff = (_vc.voff + _vtd) & 0xFFFF;
        } else {
            _vc.voff = (_vc.voff - _vtd) & 0xFFFF;
        }
        _vc.vbc = (_vc.vbc + 1) & 0xFF;
        if (_vc.vbc >= _vts) {
            _vc.vbc  = 0;
            _vc.vdir = _vc.vdir ^ 1;
        }
    } else {
        _vc.voff = 0;
        _vc.vdir = 0;
        _vc.vbc  = 0xFF;
    }

    // output: base + vibrato offset
    var _out = (_vc.freq + _vc.voff) & 0xFFFF;
    scr_sid64_sim_write(_sim, _r0 + 0, _out & 0xFF);
    scr_sid64_sim_write(_sim, _r0 + 1, (_out >> 8) & 0xFF);
}

/// Per-frame voice work after the rows: HR phase 2, stepper, effects.
function scr_sid64_sim_voice_frame(_sim, _v) {
    var _vc = _sim.voices[_v];
    var _skip_step = false;
    if (_sim.hr > 0 && _vc.hr_cd != 0) {
        _vc.hr_cd -= 1;
        if (_vc.hr_cd != 0) {
            _skip_step = true;          // still waiting, voice silent
        } else {
            _vc.base = _vc.hr_note;
            scr_sid64_sim_trigger(_sim, _v, _vc.hr_instr);
            if (!is_struct(_vc.hr_instr)) {
                _skip_step = true;      // no-instrument fire skips the stepper
            }
        }
    }
    if (!_skip_step && _vc.pcmd >= 16 && _vc.pcmd <= 18) {
        var _delta = _vc.pval;
        if (_delta >= 128) _delta -= 256;
        if (_vc.pcmd == 16) _vc.freq = (_vc.freq + _delta) & 65535;
        if (_vc.pcmd == 17) _vc.slide = _delta & 65535;
        if (_vc.pcmd == 18) _vc.pulse_slide = _delta & 65535;
        _vc.pcmd = 0;
    }
    if (!_skip_step) {
        scr_sid64_sim_step(_sim, _v);
    }
    var _hrw = 0;
    if (_sim.hr > 0) {
        _hrw = _vc.hr_cd;
    }
    scr_sid64_sim_fx(_sim, _v, _hrw);
}

/// Reads voice _v's row at the current order row / master row. Returns
/// undefined when the voice has nothing this row (no pattern, or a shorter
/// non-repeating pattern that has ended).
function scr_sid64_sim_fetch(_sim, _v, _orow) {
    var _pi = scr_music_sid_pattern(_orow, _sim.chip * 3 + _v);
    if (_pi < 0 || _pi >= array_length(_sim.m.patterns)) {
        return undefined;
    }
    var _pat = _sim.m.patterns[_pi];
    var _len = clamp(real(_pat.pattern_len), 1, 255);
    var _local = _sim.row;
    if (_local >= _len) {
        var _wrap = _orow[$ "repeat_short"];
        if (is_undefined(_wrap) || _wrap != true) {
            return undefined;
        }
        _local = _local mod _len;
    }
    var _note = 254;
    var _instr = undefined;
    var _cmd = 255;
    var _val = 0;
    if (_local < array_length(_pat.steps)) {
        var _st = _pat.steps[_local];
        var _empty = _st[$ "empty"];
        var _nn = _st[$ "note"];
        if (is_undefined(_nn)) {
            _nn = "";
        }
        if (!is_undefined(_empty) && _empty == true) {
            _note = 254;
        } else if (_nn == "+++") {
            _note = 253;
        } else if (_nn == "" || _nn == "---") {
            _note = 255;
        } else {
            var _idx = scr_sid_song_note_index(_nn);
            if (_idx < 0) {
                _note = 255;
            } else {
                _note = _idx;
            }
        }
        var _ii = _st[$ "instr_idx"];
        if (!is_undefined(_ii)) {
            _instr = scr_sid64_sim_instr(_sim, real(_ii));
        }
        var _cc = _st[$ "cmd"];
        if (!is_undefined(_cc) && real(_cc) >= 0) {
            _cmd = real(_cc) & 0xFF;
            var _cv = _st[$ "cmd_val"];
            if (!is_undefined(_cv)) {
                _val = real(_cv) & 0xFF;
            }
        }
    }
    return { note: _note, instr: _instr, cmd: _cmd, val: _val };
}

/// One 50 Hz frame of the player. Afterwards _sim.regs holds every register
/// and _sim.mask which of them were written since the last scr_sid64_sim_put
/// (so writes made just before a frame — an audition's row — land in it too).
function scr_sid64_sim_frame(_sim) {

    // voices switched off mid-song go quiet (the compiled player never has them)
    for (var _mv = 0; _mv < 3; _mv++) {
        var _on = scr_sid64_sim_voice_on(_sim, _mv);
        var _mvc = _sim.voices[_mv];
        if (!_on && _mvc.was_on) {
            _mvc.cb = 0;
            _mvc.active = false;
            _mvc.hr_cd = 0;
            scr_sid64_sim_write(_sim, _mv * 7 + 4, 0);
        }
        _mvc.was_on = _on;
    }

    if (is_struct(_sim.song) && !_sim.finished) {
        _sim.tick -= 1;
        if (_sim.tick <= 0) {
            _sim.tick = _sim.spd;
            var _n_ord = array_length(_sim.song.order);
            _sim.ord = clamp(_sim.ord, 0, _n_ord - 1);
            var _orow = _sim.song.order[_sim.ord];
            _sim.shown_ord = _sim.ord;
            _sim.shown_row = _sim.row;
            for (var _v = 0; _v < 3; _v++) {
                if (!scr_sid64_sim_voice_on(_sim, _v)) {
                    continue;
                }
                var _rd = scr_sid64_sim_fetch(_sim, _v, _orow);
                if (is_struct(_rd)) {
                    scr_sid64_sim_row(_sim, _v, _rd.note, _rd.instr, _rd.cmd, _rd.val);
                }
            }
            // advance the master row / order row
            _sim.row += 1;
            if (_sim.row >= scr_sid64_sim_row_len(_sim, _orow)) {
                _sim.row = 0;
                if (!_sim.loop_row) {
                    _sim.ord += 1;
                    if (_sim.ord >= _n_ord) {
                        var _lp = _sim.song[$ "loop"];
                        if (!is_undefined(_lp) && _lp == true) {
                            _sim.ord = clamp(real(_sim.song.loop_row), 0, _n_ord - 1);
                            // loop wrap: every voice restarts clean
                            for (var _wv = 0; _wv < 3; _wv++) {
                                var _wvc = _sim.voices[_wv];
                                _wvc.hold = 0;
                                _wvc.active = false;
                                _wvc.hr_cd = 0;
                                _wvc.cb = 0;
                            }
                        } else {
                            // stop: park on the last row, silence everything
                            _sim.ord = _n_ord - 1;
                            _sim.finished = true;
                            for (var _sv = 0; _sv < 3; _sv++) {
                                var _svc = _sim.voices[_sv];
                                _svc.cb = 0;
                                _svc.active = false;
                                _svc.hr_cd = 0;
                                scr_sid64_sim_write(_sim, _sv * 7 + 4, 0);
                            }
                        }
                    }
                }
            }
        }
    }

    for (var _fv = 0; _fv < 3; _fv++) {
        if (scr_sid64_sim_voice_on(_sim, _fv)) {
            scr_sid64_sim_voice_frame(_sim, _fv);
        }
    }
}

/// Writes the sim's current frame as record _i of frame buffer _fb.
function scr_sid64_sim_put(_sim, _fb, _i) {
    var _o = _i * 32;
    for (var _r = 0; _r < 25; _r++) {
        buffer_poke(_fb, _o + _r, buffer_u8, _sim.regs[_r]);
    }
    var _mask = _sim.mask;
    if (_mask == 0) {
        _mask = (1 << 24);      // 0 would mean "write all"; $D418 again is harmless
    }
    buffer_poke(_fb, _o + 25, buffer_u32, _mask);
    _sim.mask = 0;
}

/// Immutable display snapshot; never expose a voice that is being rendered ahead.
function scr_sid64_voice_display(_vc) {
    if (!is_struct(_vc.instr) || (!_vc.active && (_vc.cb & 1) == 0)) return undefined;
    return { instr: _vc.instr, compiled: _vc.display_compiled, pcs: _vc.display_pcs };
}
