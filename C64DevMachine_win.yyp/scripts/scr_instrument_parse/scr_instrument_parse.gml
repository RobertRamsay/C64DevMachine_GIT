/// @desc scr_instrument_parse(_text)
/// Compiles an instrument mini-language string into a flat byte array the
/// 6502 interpreter walks one command per instrument-tick.
///
/// GRAMMAR (tokens separated by commas or newlines, whitespace ignored):
///   $21 or 21   waveform/control byte   -> [$00, byte]
///   N+n / Nn    note, +n semitones      -> [$01, n signed]
///   N-n         note, -n semitones      -> [$01, n signed]
///   N / N+0     note as-is              -> [$01, $00]
///   Dn          hold n ticks (1-255)    -> [$02, n]
///   Rc:n        repeat from step n c MORE times (1-254), then continue
///   Ln          loop to step n          -> [$03, byte-offset of step n]
///   ---         end (gate off + stop)   -> [$04]
///   ~PITCH      start of a pitch table: S / D / L lines that run alongside
///               the program on their own counter (each S is a slide speed)
///   ~PULSE      start of a pulse table: Q / D / L lines, the same way
///   ~PITCH+     / ~PULSE+ : the table KEEPS RUNNING across new notes — a note
///               (or tie) using the same table carries on from where it was
///               instead of restarting it. Identical tables are stored once
///               per song and shared, so instruments can share one vibrato.
///
/// Tables follow the program's implicit END as records of
/// [frames, speed lo, speed hi]; frames 0 is control: [0, back] jumps back
/// that many bytes (Ln), [0, 0] stops the table. The program opens with
/// [$0E, offset] / [$0F, offset] so the player starts each table on trigger
/// ($10 / $11 for the keep-running forms). The song build turns the offset
/// into the table's address.
///
/// Steps are variable length, so Ln can't point at a byte directly. The
/// parser records each step's byte offset in a first pass, then patches the
/// loop commands in a second pass. An implicit end ($04) is always appended
/// so a runaway pointer can't walk off into whatever follows the table.
///
/// Returns a struct:
///   { bytes: [...], step_offsets: [...], errors: [...] }
/// bytes        — the compiled command stream (what gets emitted as BYTE_DATA)
/// step_offsets — byte offset of each step (for the editor / debugging)
/// errors       — human-readable strings for malformed tokens (never throws)
function scr_instrument_parse(_text) {

    var _out    = { bytes: [], step_offsets: [], errors: [], version: 5, byte_lines: [], source: string(_text), no_hr: false, main_len: 0, lanes: [] };
    var _tokens = [];

    // ── Tokenise: newlines act as commas, then split, trim, drop empties ──
    var _s = string_replace_all(string(_text), "\r\n", "\n");
    _s     = string_replace_all(_s, "\r", "\n");
    var _token_lines = [];
    var _source_lines = string_split(_s, "\n");
    for (var _ln = 0; _ln < array_length(_source_lines); _ln++) {
        var _raw = string_split(_source_lines[_ln], ",");
        for (var _i = 0; _i < array_length(_raw); _i++) {
            var _t = string_trim(_raw[_i]);
            if (_t != "") { array_push(_tokens, _t); array_push(_token_lines, _ln); }
        }
    }
    var _previous_line = -1;

    // ── Table sections: everything from the first ~ line on is table data. ──
    var _main_count = array_length(_tokens);
    var _lane_heads = [];
    for (var _hi = 0; _hi < array_length(_tokens); _hi++) {
        if (string_char_at(_tokens[_hi], 1) == "~") {
            if (_main_count == array_length(_tokens)) _main_count = _hi;
            var _head = string_upper(_tokens[_hi]);
            var _kind = -1;
            var _keep = false;
            if (string_char_at(_head, string_length(_head)) == "+") {
                _keep = true;
                _head = string_copy(_head, 1, string_length(_head) - 1);
            }
            if (_head == "~PITCH") _kind = 0;
            if (_head == "~PULSE") _kind = 1;
            for (var _hk = 0; _hk < array_length(_lane_heads); _hk++) {
                if (_lane_heads[_hk].kind == _kind) _kind = -2;
            }
            if (_kind == -1) array_push(_out.errors, "step " + string(_hi) + ": tables are ~PITCH or ~PULSE");
            if (_kind == -2) array_push(_out.errors, "step " + string(_hi) + ": only one " + _head + " table per instrument");
            array_push(_lane_heads, { kind: _kind, ti: _hi, arg_pos: -1, keep: _keep });
        }
    }
    // Each table is started once, before step 00, so Ln in the program never restarts it.
    for (var _hk = 0; _hk < array_length(_lane_heads); _hk++) {
        if (_lane_heads[_hk].kind >= 0) {
            var _lane_op = 14 + _lane_heads[_hk].kind;
            if (_lane_heads[_hk].keep) _lane_op += 2;
            array_push(_out.bytes, _lane_op, 0, 0);
            _lane_heads[_hk].arg_pos = array_length(_out.bytes) - 2;
            var _hl = _token_lines[_lane_heads[_hk].ti];
            array_push(_out.byte_lines, _hl, _hl, _hl);
        }
    }

    // ── Pass 1: emit bytes, recording where each step begins. Loop targets
    //    are noted as (byte-position-of-arg, step-index) for pass-2 patching. ──
    var _wide = true; // version 2 uses 16-bit loop targets
    var _repeat_end = -1;
    var _loop_fixups = [];   // { arg_pos, step_idx }

    for (var _ti = 0; _ti < _main_count; _ti++) {

        // Map all emitted bytes, including implicit holds, to their source line.
        while (array_length(_out.byte_lines) < array_length(_out.bytes)) array_push(_out.byte_lines, _previous_line);
        _previous_line = _token_lines[_ti];
        var _tok = _tokens[_ti];
        var _up  = string_upper(_tok);

        // Record this step's byte offset before emitting it.
        array_push(_out.step_offsets, array_length(_out.bytes));

        var _c0 = string_char_at(_up, 1);

        // ── END ── (--- or any all-dash token)
        var _all_dash = (string_length(_up) >= 1);
        for (var _di = 1; _di <= string_length(_up); _di++) {
            if (string_char_at(_up, _di) != "-") {
                _all_dash = false;
                break;
            }
        }
        if (_all_dash) {
            array_push(_out.bytes, 0x04);
            continue;
        }

        // Look ahead: a NOTE or WAVE not followed by an explicit Dn gets an
        // implicit D1 appended, so every command occupies at least one frame.
        //
        // Without this the runtime executes consecutive commands in a single
        // frame — the stepper only exits on HOLD or END — so a run like
        // n14,n12,n10,n8 writes the frequency four times in one frame and only
        // the last is audible. The editor preview flushed each as a 1-tick
        // blip, so instruments sounded completely different there than on
        // hardware. Emitting the hold makes both read the same stream.
        var _next_is_hold = false;
        if (_ti + 1 < array_length(_tokens)) {
            var _nxt = string_upper(string_trim(_tokens[_ti + 1]));
            if (string_char_at(_nxt, 1) == "D") {
                _next_is_hold = true;
            }
        }

        // Rcount:step repeats a preceding, non-nested section count MORE times.
        // A timed section is required, so this cannot form a zero-time loop.
        if (_c0 == "R") {
            var _parts = string_split(string_delete(_up,1,1), ":");
            var _ok = array_length(_parts) == 2;
            var _count = 0, _step = -1;
            if (_ok) {
                _ok = _parts[0] != "" && _parts[1] != "";
                for (var _rp=0;_rp<2;_rp++) for (var _rc=1;_rc<=string_length(_parts[_rp]);_rc++)
                    if (string_pos(string_char_at(_parts[_rp],_rc),"0123456789") == 0) _ok = false;
                if (_ok) { _count = real(_parts[0]); _step = real(_parts[1]); }
            }
            _ok = _ok && _count >= 1 && _count <= 254 && _step > _repeat_end && _step < _ti;
            var _timed = false;
            if (_ok) for (var _rs=_step;_rs<_ti;_rs++) {
                var _rt = string_upper(_tokens[_rs]), _first = string_char_at(_rt,1);
                if (_first == "D") _timed = true;
                if (_first == "L" || _first == "R" || _first == "-") _ok = false;
            }
            if (!_ok || !_timed) {
                array_push(_out.errors,"step " + string(_ti) + ": Rcount:step needs 1-254 repeats of a preceding timed section, without nested loops");
                array_push(_out.bytes,4);
            } else {
                array_push(_out.bytes,13,0,0,_count);
                array_push(_loop_fixups,{arg_pos:array_length(_out.bytes)-3,step_idx:_step});
                _repeat_end = _ti;
            }
            continue;
        }

        // Fine pitch delta in SID frequency units, or an exact 12-bit pulse width.
        // These setup commands take no time; Dn controls when they are heard.
        if (_up == "H0" || _up == "H1") {
            _out.no_hr = (_up == "H0");
            continue;
        }
        if (_c0 == "G") {
            var _ghex = string_delete(_up, 1, 2);
            var _gok = string_char_at(_up, 2) == "$" && string_length(_ghex) == 2;
            for (var _gi = 1; _gi <= string_length(_ghex); _gi++) {
                if (string_pos(string_char_at(_ghex, _gi), "0123456789ABCDEF") == 0) _gok = false;
            }
            if (!_gok) array_push(_out.errors, "step " + string(_ti) + ": use G$00..G$FF for raw gate/wave control");
            array_push(_out.bytes, 10, _gok ? real(hex_to_decimal(_ghex)) : 0);
            continue;
        }
        if ((_c0 == "F" && (string_char_at(_up, 2) == "+" || string_char_at(_up, 2) == "-")) || _c0 == "P" || _c0 == "S" || _c0 == "Q") {
            var _arg = string_delete(_up, 1, 1);
            var _num = _arg;
            var _neg = false;
            var _hex = (_c0 == "P" && string_char_at(_num, 1) == "$");
            if (_hex) _num = string_delete(_num, 1, 1);
            if (_c0 != "P" && (string_char_at(_num, 1) == "+" || string_char_at(_num, 1) == "-")) {
                _neg = string_char_at(_num, 1) == "-";
                _num = string_delete(_num, 1, 1);
            }
            var _ok = string_length(_num) > 0;
            for (var _j = 1; _j <= string_length(_num); _j++) {
                if (string_pos(string_char_at(_num, _j), _hex ? "0123456789ABCDEF" : "0123456789") == 0) _ok = false;
            }
            var _val = 0;
            if (_ok) _val = _hex ? real(hex_to_decimal(_num)) : real(_num);
            if (_neg) _val = -_val;
            if (!_ok || (_c0 != "P" && (_val < -32768 || _val > 32767)) || (_c0 == "P" && (_val < 0 || _val > 4095))) {
                array_push(_out.errors, "step " + string(_ti) + ": F/S/Q use -32768..32767; P uses $000..$FFF");
                _val = 0;
            }
            var _opcode = _c0 == "F" ? 6 : (_c0 == "P" ? 7 : (_c0 == "S" ? 8 : 9));
            array_push(_out.bytes, _opcode, _val & 255, (_val >> 8) & 255);
            continue;
        }

        // ── NOTE ── N, N+n, N-n, Nn
        if (_c0 == "N") {
            var _rest = string_delete(_up, 1, 1);
            var _sign = 1;
            if (string_char_at(_rest, 1) == "+") {
                _rest = string_delete(_rest, 1, 1);
            } else if (string_char_at(_rest, 1) == "-") {
                _sign = -1;
                _rest = string_delete(_rest, 1, 1);
            }
            var _digits = string_digits(_rest);
            var _val    = (_digits != "") ? real(_digits) : 0;
            _val *= _sign;
            if (_val < -128 || _val > 127) {
                array_push(_out.errors, "step " + string(_ti) + ": note offset '" + _tok + "' out of range (-128..127)");
                _val = clamp(_val, -128, 127);
            }
            var _enc = (_val < 0) ? (256 + _val) : _val;   // two's complement
            array_push(_out.bytes, 0x01);
            array_push(_out.bytes, _enc & 0xFF);
            if (!_next_is_hold) {
                array_push(_out.bytes, 0x02);
                array_push(_out.bytes, 0x01);
            }
            continue;
        }

        // ── HOLD ── Dn
        if (_c0 == "D") {
            var _rest = string_delete(_up, 1, 1);
            var _digits = string_digits(_rest);
            if (_digits == "") {
                array_push(_out.errors, "step " + string(_ti) + ": hold '" + _tok + "' has no count, treating as D1");
                _digits = "1";
            }
            var _n = clamp(real(_digits), 1, 255);
            array_push(_out.bytes, 0x02);
            array_push(_out.bytes, _n & 0xFF);
            continue;
        }

        // ── LOOP ── Ln (target patched in pass 2)
        if (_c0 == "L") {
            var _rest = string_delete(_up, 1, 1);
            var _digits = string_digits(_rest);
            var _step   = (_digits != "") ? real(_digits) : 0;
            array_push(_out.bytes, _wide ? 0x05 : 0x03);
            array_push(_loop_fixups, { arg_pos: array_length(_out.bytes), step_idx: _step });
            array_push(_out.bytes, 0x00);   // placeholder, patched below
            if (_wide) array_push(_out.bytes, 0x00);
            continue;
        }

        // ── WAVEFORM ── $xx or bare 2-digit hex
        var _hexstr = _up;
        if (string_char_at(_hexstr, 1) == "$") {
            _hexstr = string_delete(_hexstr, 1, 1);
        }
        // Validate hex
        var _is_hex = (string_length(_hexstr) > 0);
        for (var _hi = 1; _hi <= string_length(_hexstr); _hi++) {
            if (string_pos(string_char_at(_hexstr, _hi), "0123456789ABCDEF") == 0) {
                _is_hex = false;
                break;
            }
        }
        if (_is_hex) {
            var _wv = real(hex_to_decimal(_hexstr)) & 0xFF;
            array_push(_out.bytes, 0x00);
            array_push(_out.bytes, _wv);
            if (!_next_is_hold) {
                array_push(_out.bytes, 0x02);
                array_push(_out.bytes, 0x01);
            }
            continue;
        }
        

        // ── UNRECOGNISED ── record and skip (no byte emitted, so step_offset
        //    we pushed is stale — pop it so it doesn't misalign L targets).
        array_push(_out.errors, "step " + string(_ti) + ": unrecognised token '" + _tok + "' skipped");
        array_pop(_out.step_offsets);
    }

    while (array_length(_out.byte_lines) < array_length(_out.bytes)) array_push(_out.byte_lines, _previous_line);
    array_push(_out.byte_lines, -1); // implicit END has no visible source line
    // ── Always append an end terminator ──
    array_push(_out.bytes, 0x04);

    if (array_length(_out.bytes) > 65535) {
        array_push(_out.errors, "instrument exceeds the 65535-byte address space");
        _out.bytes = [0x04];
        return _out;
    }

    // ── Pass 2: patch loop targets to the recorded byte offset. If the target
    //    step doesn't exist, point at the end terminator so it halts cleanly
    //    rather than jumping into the middle of a command — the user asked for
    //    a step that isn't there, and this is the least-surprising "nowhere". ──
    var _end_off = array_length(_out.bytes) - 1;   // the appended $04
    for (var _li = 0; _li < array_length(_loop_fixups); _li++) {
        var _fx  = _loop_fixups[_li];
        var _tgt = _end_off;
        if (_fx.step_idx >= 0 && _fx.step_idx < array_length(_out.step_offsets)) {
            _tgt = _out.step_offsets[_fx.step_idx];
        } else {
            array_push(_out.errors, "loop target step " + string(_fx.step_idx)
                + " doesn't exist; loop points at end (halts)");
        }
        _out.bytes[_fx.arg_pos] = _tgt & 0xFF;
        if (_wide) _out.bytes[_fx.arg_pos + 1] = (_tgt >> 8) & 255;
    }
    _out.main_len = array_length(_out.bytes);

    // ── Pass 3: tables, appended after the program's END. ──
    for (var _hk = 0; _hk < array_length(_lane_heads); _hk++) {
        var _lh = _lane_heads[_hk];
        var _stop = array_length(_tokens);
        if (_hk + 1 < array_length(_lane_heads)) _stop = _lane_heads[_hk + 1].ti;
        while (array_length(_out.step_offsets) <= _lh.ti) array_push(_out.step_offsets, array_length(_out.bytes));
        if (_lh.kind < 0) continue;
        var _start = array_length(_out.bytes);
        _out.bytes[_lh.arg_pos] = _start & 255;
        _out.bytes[_lh.arg_pos + 1] = (_start >> 8) & 255;
        var _letter = "S";
        if (_lh.kind == 1) _letter = "Q";
        var _val = 0;
        var _pending = false;
        var _pending_step = -1;
        var _closed = false;
        var _records = {};
        for (var _lt = _lh.ti + 1; _lt < _stop; _lt++) {
            var _lup = string_upper(_tokens[_lt]);
            var _lc = string_char_at(_lup, 1);
            var _line = _token_lines[_lt];
            array_push(_out.step_offsets, array_length(_out.bytes));
            if (_closed) {
                array_push(_out.errors, "step " + string(_lt) + ": nothing runs after a table's Ln");
                continue;
            }
            var _num = string_delete(_lup, 1, 1);
            var _neg = false;
            if (string_char_at(_num, 1) == "+" || string_char_at(_num, 1) == "-") {
                _neg = string_char_at(_num, 1) == "-";
                _num = string_delete(_num, 1, 1);
            }
            var _ok = string_length(_num) > 0 && string_digits(_num) == _num;
            var _n = 0;
            if (_ok) _n = real(_num);
            if (_neg) _n = -_n;
            if (_lc == _letter) {
                if (!_ok || _n < -32768 || _n > 32767) {
                    array_push(_out.errors, "step " + string(_lt) + ": " + _letter + " uses -32768..32767");
                    continue;
                }
                if (_pending) {
                    // A speed with no Dn lasts one frame, as in the program.
                    variable_struct_set(_records, string(_pending_step), array_length(_out.bytes));
                    array_push(_out.bytes, 1, _val & 255, (_val >> 8) & 255);
                    array_push(_out.byte_lines, _line, _line, _line);
                }
                _val = _n;
                _pending = true;
                _pending_step = _lt;
            } else if (_lc == "D") {
                if (!_ok || _n < 1 || _n > 255) {
                    array_push(_out.errors, "step " + string(_lt) + ": hold must be 1-255 frames");
                    continue;
                }
                var _rec = array_length(_out.bytes);
                if (_pending) variable_struct_set(_records, string(_pending_step), _rec);
                variable_struct_set(_records, string(_lt), _rec);
                array_push(_out.bytes, _n, _val & 255, (_val >> 8) & 255);
                array_push(_out.byte_lines, _line, _line, _line);
                _pending = false;
            } else if (_lc == "L") {
                if (_pending) {
                    variable_struct_set(_records, string(_pending_step), array_length(_out.bytes));
                    array_push(_out.bytes, 1, _val & 255, (_val >> 8) & 255);
                    array_push(_out.byte_lines, _line, _line, _line);
                    _pending = false;
                }
                var _back = -1;
                if (_ok && variable_struct_exists(_records, string(_n))) {
                    _back = array_length(_out.bytes) - variable_struct_get(_records, string(_n));
                }
                if (_back < 1 || _back > 255) {
                    array_push(_out.errors, "step " + string(_lt) + ": a table's Ln must go back to an earlier " + _letter + " or D in the same table, within 85 lines");
                    _back = 0;
                }
                array_push(_out.bytes, 0, _back);
                array_push(_out.byte_lines, _line, _line);
                _closed = true;
            } else {
                array_push(_out.errors, "step " + string(_lt) + ": a " + _letter + " table holds " + _letter + ", D and L lines only");
            }
        }
        if (_pending) {
            array_push(_out.bytes, 1, _val & 255, (_val >> 8) & 255);
            array_push(_out.byte_lines, -1, -1, -1);
        }
        if (!_closed) {
            array_push(_out.bytes, 0, 0);
            array_push(_out.byte_lines, -1, -1);
        }
        array_push(_out.lanes, [_start, array_length(_out.bytes) - _start]);
    }

    return _out;
}

// Imported instruments may contain source only: compiled is a disposable cache.
// Repair it lazily, leaving valid caches and uncommitted editor text alone.
function scr_instrument_ensure_compiled(_instr) {
    var _valid = variable_struct_exists(_instr, "compiled");
    if (_valid) _valid = is_struct(_instr.compiled);
    if (_valid) _valid = variable_struct_exists(_instr.compiled, "bytes") && variable_struct_exists(_instr.compiled, "errors");
    if (_valid) _valid = is_array(_instr.compiled.bytes) && is_array(_instr.compiled.errors);
    if (_valid) _valid = variable_struct_exists(_instr.compiled, "version") && variable_struct_exists(_instr.compiled, "source");
    if (_valid) _valid = _instr.compiled.version == 5 && _instr.compiled.source == _instr.text;
    if (!_valid) _instr.compiled = scr_instrument_parse(_instr.text);
    return _instr.compiled;
}

// One command per editor entry; token order (and therefore loop numbering) stays fixed.
function scr_instrument_format(_text) {
    var _s = string_replace_all(string(_text), "\r", "\n");
    _s = string_replace_all(_s, ",", "\n");
    var _raw = string_split(_s, "\n");
    var _lines = [];
    for (var _i = 0; _i < array_length(_raw); _i++) {
        var _t = string_trim(_raw[_i]);
        if (_t != "") array_push(_lines, _t);
    }
    return string_join_ext("\n", _lines);
}

/// Compile editable Music Maker commands into shared, non-nested C64 tables.
/// Branch destinations remain in the instrument stream. No playback timing,
/// parameter values or source-line highlighting are changed by storage sharing.
function scr_music_table_pack(_instruments) {
    var _cache_key = "";
    for (var _i = 0; _i < array_length(_instruments); _i++) {
        var _source = string(_instruments[_i].text);
        _cache_key += string(string_length(_source)) + ":" + _source;
    }
    if (variable_global_exists("music_table_cache_key") && global.music_table_cache_key == _cache_key) return global.music_table_cache;
    var _streams = [], _original = [], _raw = 0;
    for (var _i = 0; _i < array_length(_instruments); _i++) {
        var _c = scr_instrument_ensure_compiled(_instruments[_i]);
        var _b = _c.bytes, _ops = [], _targets = {};
        // Only the program is made of commands; table data after it is copied as-is.
        var _main_len = _c.main_len;
        for (var _p = 0; _p < _main_len;) {
            var _op = _b[_p];
            var _len = scr_music_op_len(_op);
            if (_op == 3 || _op == 5 || (_op >= 13 && _op <= 17)) {
                var _dest = _b[_p + 1];
                if (_op != 3) _dest += _b[_p + 2] * 256;
                variable_struct_set(_targets, string(_dest), true);
            }
            _p += _len;
        }
        for (var _p = 0; _p < _main_len;) {
            var _op = _b[_p];
            var _len = scr_music_op_len(_op);
            var _bytes = [], _key = "";
            for (var _j = 0; _j < _len; _j++) { array_push(_bytes, _b[_p + _j]); _key += string(_b[_p + _j]) + ","; }
            array_push(_ops, {bytes:_bytes, key:_key, pos:_p, size:_len,
                target:variable_struct_exists(_targets,string(_p)), call:-1, raw:false});
            _p += _len;
        }
        for (var _l = 0; _l < array_length(_c.lanes); _l++) {
            var _lane = _c.lanes[_l], _bytes = [];
            for (var _j = 0; _j < _lane[1]; _j++) array_push(_bytes, _b[_lane[0] + _j]);
            array_push(_ops, {bytes:_bytes, key:"", pos:_lane[0], size:_lane[1], target:true, call:-1, raw:true});
        }
        array_push(_streams, _ops);
        array_push(_original, _ops);
        _raw += array_length(_b);
    }
    var _tables = [];
    // Longer phrases first. Later passes share shorter material left between
    // calls; existing calls can never enter a new table (no runtime stack).
    var _lengths = [32, 16, 8, 4];
    for (var _pass = 0; _pass < array_length(_lengths); _pass++) {
        var _n = _lengths[_pass], _lookup = {}, _candidates = [];
        for (var _i = 0; _i < array_length(_streams); _i++) {
            var _ops = _streams[_i];
            for (var _p = 0; _p + _n <= array_length(_ops); _p++) {
                var _key = "", _size = 0, _ok = true;
                for (var _j = 0; _j < _n; _j++) {
                    var _o = _ops[_p + _j], _op = _o.bytes[0];
                    if (_o.raw || _o.call >= 0 || _op == 3 || _op == 4 || _op == 5 || (_op >= 13 && _op <= 17) || (_j > 0 && _o.target)) { _ok = false; break; }
                    _key += _o.key + ";"; _size += _o.size;
                }
                if (!_ok) continue;
                var _ci;
                if (!variable_struct_exists(_lookup, _key)) {
                    _ci = array_length(_candidates); variable_struct_set(_lookup, _key, _ci);
                    array_push(_candidates, {rank:_ci, key:_key, size:_size, count:0, last_i:-1, last_p:-1000, table:-1, positions:[]});
                } else _ci = variable_struct_get(_lookup, _key);
                var _cand = _candidates[_ci];
                array_push(_cand.positions, [_i, _ops[_p].pos]);
                if (_cand.last_i != _i || _p >= _cand.last_p + _n) {
                    _cand.count++; _cand.last_i = _i; _cand.last_p = _p;
                }
            }
        }
        // Use only candidates with a net data saving, accounting for calls
        // and the one-byte return. Count actual uses before accepting a table.
        // Prefer phrases with the largest estimated saving; actual uses are checked below.
        array_sort(_candidates, function(_a, _b) {
            var _saving = (_b.count * (_b.size - 3) - _b.size) - (_a.count * (_a.size - 3) - _a.size); return (_saving == 0) ? _a.rank - _b.rank : _saving;
        });
        for (var _ci = 0; _ci < array_length(_candidates); _ci++) {
            var _cand = _candidates[_ci];
            if (_cand.count * (_cand.size - 3) <= _cand.size + 1) continue;
            var _uses = [], _maps = [];
            for (var _i = 0; _i < array_length(_streams); _i++) {
                var _map = {}, _ops = _streams[_i];
                for (var _p = 0; _p < array_length(_ops); _p++) variable_struct_set(_map,string(_ops[_p].pos),_p);
                array_push(_maps,_map);
            }
            var _last_i = -1, _last_p = -1000;
            for (var _u = 0; _u < array_length(_cand.positions); _u++) {
                var _loc = _cand.positions[_u], _i = _loc[0], _map = _maps[_i];
                if (!variable_struct_exists(_map,string(_loc[1]))) continue;
                var _p = variable_struct_get(_map,string(_loc[1])), _ops = _streams[_i];
                if ((_last_i == _i && _p < _last_p + _n) || _p + _n > array_length(_ops)) continue;
                var _key = "";
                for (var _j = 0; _j < _n; _j++) {
                    var _o = _ops[_p + _j];
                    if (_o.raw || _o.call >= 0 || (_j > 0 && _o.target)) break;
                    _key += _o.key + ";";
                }
                if (_key == _cand.key) { array_push(_uses,[_i,_p]); _last_i = _i; _last_p = _p; }
            }
            if (array_length(_uses) * (_cand.size - 3) <= _cand.size + 1) continue;
            var _tab = [], _first = _uses[0];
            for (var _j = 0; _j < _n; _j++) array_push(_tab, _streams[_first[0]][_first[1] + _j]);
            var _tid = array_length(_tables); array_push(_tables, _tab);
            // Reverse replacement retains the positions of preceding uses.
            for (var _u = array_length(_uses) - 1; _u >= 0; _u--) {
                var _use = _uses[_u], _ops = _streams[_use[0]], _at = _use[1], _new = [];
                for (var _j = 0; _j < array_length(_ops); _j++) {
                    if (_j == _at) {
                        array_push(_new, {bytes:[11,0,0], key:"", pos:_ops[_j].pos, size:3, target:_ops[_j].target, call:_tid, raw:false});
                        _j += _n - 1;
                    } else array_push(_new, _ops[_j]);
                }
                _streams[_use[0]] = _new;
            }
        }
    }
    var _stored = 0;
    for (var _i = 0; _i < array_length(_streams); _i++) for (var _j = 0; _j < array_length(_streams[_i]); _j++) _stored += _streams[_i][_j].size;
    for (var _i = 0; _i < array_length(_tables); _i++) {
        _stored++;
        for (var _j = 0; _j < array_length(_tables[_i]); _j++) _stored += _tables[_i][_j].size;
    }
    // The three interpreters and six bytes of return-address RAM cost less
    // than 256 bytes. Small songs retain their original player/data layout.
    var _result;
    if (_raw - _stored <= 256) _result = {streams:_original,tables:[],raw_bytes:_raw,stored_bytes:_raw};
    else _result = {streams:_streams,tables:_tables,raw_bytes:_raw,stored_bytes:_stored};
    global.music_table_cache_key = _cache_key;
    global.music_table_cache = _result;
    return _result;
}

/// _lanes is the song's table registry { count, labels:{content -> label} }:
/// each distinct ~PITCH / ~PULSE table is emitted once and every start command
/// points at it by address, so identical tables are shared (and a keep-running
/// table carries on across instruments that use it).
function scr_music_table_emit(_list, _id, _key, _ops, _lanes) {
    var _offsets = {}, _offset = 0;
    var _lane_at = {};
    for (var _i = 0; _i < array_length(_ops); _i++) {
        variable_struct_set(_offsets, string(_ops[_i].pos), _offset);
        _offset += _ops[_i].size;
        if (_ops[_i].raw) {
            var _content = "";
            for (var _j = 0; _j < array_length(_ops[_i].bytes); _j++) _content += string(_ops[_i].bytes[_j]) + ",";
            var _label = "";
            var _fresh = false;
            if (variable_struct_exists(_lanes.labels, _content)) {
                _label = variable_struct_get(_lanes.labels, _content);
            } else {
                _label = _key + "lane" + string(_lanes.count);
                _lanes.count += 1;
                variable_struct_set(_lanes.labels, _content, _label);
                _fresh = true;
            }
            variable_struct_set(_lane_at, string(_ops[_i].pos), { label: _label, fresh: _fresh });
        }
    }
    for (var _i = 0; _i < array_length(_ops); _i++) {
        var _o = _ops[_i], _bytes = _o.bytes;
        if (_o.raw) {
            var _la = variable_struct_get(_lane_at, string(_o.pos));
            if (_la.fresh) {
                array_push(_list, ["label", _la.label]);
                for (var _j = 0; _j < array_length(_bytes); _j++) array_push(_list,["byte",_bytes[_j],_id]);
            }
        } else if (_bytes[0] >= 14 && _bytes[0] <= 17) {
            // Table start: the operand is the (possibly shared) table's address.
            var _la = variable_struct_get(_lane_at, string(_bytes[1] + _bytes[2] * 256));
            array_push(_list, ["byte", _bytes[0], _id], ["byte_lab_lo", _la.label, _id], ["byte_lab_hi", _la.label, _id]);
        } else if (_o.call >= 0) {
            array_push(_list, ["byte",11,_id], ["byte_lab_lo",_key+"table"+string(_o.call),_id], ["byte_lab_hi",_key+"table"+string(_o.call),_id]);
        } else if (_bytes[0] == 5 || _bytes[0] == 3 || _bytes[0] == 13) {
            var _dest = _bytes[1];
            if (_bytes[0] != 3) _dest += _bytes[2] * 256;
            var _new = variable_struct_get(_offsets,string(_dest));
            array_push(_list,["byte",_bytes[0],_id],["byte",_new & 255,_id]);
            if (_bytes[0] != 3) array_push(_list,["byte",(_new >> 8) & 255,_id]);
            if (_bytes[0] == 13) array_push(_list,["byte",_bytes[3],_id]);
        } else for (var _j = 0; _j < array_length(_bytes); _j++) array_push(_list,["byte",_bytes[_j],_id]);
    }
}

/// Byte length of one program command (tables after the program excluded).
function scr_music_op_len(_op) {
    if (_op == 13) return 4;
    if (_op == 4) return 1;
    if (_op >= 5 && _op <= 9) return 3;
    if (_op >= 14 && _op <= 17) return 3;
    return 2;
}
