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
///   Ln          loop to step n          -> [$03, byte-offset of step n]
///   ---         end (gate off + stop)   -> [$04]
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

    var _out    = { bytes: [], step_offsets: [], errors: [] };
    var _tokens = [];

    // ── Tokenise: newlines act as commas, then split, trim, drop empties ──
    var _s = string_replace_all(string(_text), "\r\n", "\n");
    _s     = string_replace_all(_s, "\r", "\n");
    _s     = string_replace_all(_s, "\n", ",");
    var _raw = string_split(_s, ",");
    for (var _i = 0; _i < array_length(_raw); _i++) {
        var _t = string_trim(_raw[_i]);
        if (_t != "") {
            array_push(_tokens, _t);
        }
    }

    // ── Pass 1: emit bytes, recording where each step begins. Loop targets
    //    are noted as (byte-position-of-arg, step-index) for pass-2 patching. ──
    var _loop_fixups = [];   // { arg_pos, step_idx }

    for (var _ti = 0; _ti < array_length(_tokens); _ti++) {

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
            array_push(_out.bytes, 0x03);
            array_push(_loop_fixups, { arg_pos: array_length(_out.bytes), step_idx: _step });
            array_push(_out.bytes, 0x00);   // placeholder, patched below
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

    // ── Always append an end terminator ──
    array_push(_out.bytes, 0x04);

    // ── Soft warning if the compiled instrument overruns a one-byte offset.
    //    Loop targets are stored as a single byte, so anything past 255 can't
    //    be reached. Instruments are virtually never this long, but flag it
    //    rather than emit a silently-truncated loop. ──
    if (array_length(_out.bytes) > 255) {
        array_push(_out.errors, "instrument is " + string(array_length(_out.bytes))
            + " bytes; loop targets past 255 can't be addressed by a one-byte offset");
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
    }

    return _out;
}