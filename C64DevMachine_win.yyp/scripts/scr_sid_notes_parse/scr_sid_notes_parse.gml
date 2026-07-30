/// @desc scr_sid_notes_parse(_text)
/// Tokenises a TEXT_DATA note list into an array of {freq, gate} structs.
/// Separators: commas and newlines, both equivalent. Whitespace trimmed.
/// Empty tokens are skipped (trailing commas / blank lines cost nothing).
/// Anything scr_note_name_to_freq rejects becomes a REST: gate 0, freq 0.
/// A rest still lets the macro write AD/SR/PW/freq — only the WAVE/gate
/// write is suppressed — so the previous note rings on undisturbed.
///
/// RUN-LENGTH RESTS: "R" followed by 1-2 digits expands to that many rest
/// entries — "R04" is four rests, "R21" is twenty-one. Purely an authoring
/// shorthand; the table itself is still flat, one entry per tick, so the
/// runtime and the index var are unchanged. Bare "R" and "R00" are one rest.
/// Note holds aren't needed — that's what AD/SR are for.
function scr_sid_notes_parse(_text) {

    var _out = [];
    var _s   = string_replace_all(string(_text), "\r\n", "\n");
    _s       = string_replace_all(_s, "\r", "\n");
    _s       = string_replace_all(_s, "\n", ",");

    var _parts = string_split(_s, ",");

    for (var _i = 0; _i < array_length(_parts); _i++) {
        var _tok = string_trim(_parts[_i]);
        if (_tok == "") {
            continue;
        }
        // Run-length rest: R, R0-R9, R00-R99. Checked before the note parse
        // so it can't be mistaken for anything — no note name starts with R.
        var _up   = string_upper(_tok);
        var _reps = 0;
        if (string_char_at(_up, 1) == "R") {
            var _tail  = string_delete(_up, 1, 1);
            var _tlen  = string_length(_tail);
            var _digit = true;
            for (var _ci = 1; _ci <= _tlen; _ci++) {
                var _ch = string_char_at(_tail, _ci);
                if (_ch < "0" || _ch > "9") {
                    _digit = false;
                    break;
                }
            }
            if (_digit && _tlen <= 2) {
                if (_tlen == 0) {
                    _reps = 1;
                } else {
                    _reps = real(_tail);
                    if (_reps < 1) {
                        _reps = 1;
                    }
                }
            }
        }

        if (_reps > 0) {
            for (var _ri = 0; _ri < _reps; _ri++) {
                array_push(_out, { freq: 0, gate: 0 });
            }
            continue;
        }

        var _f = scr_note_name_to_freq(_tok);
        if (_f < 0) {
            array_push(_out, { freq: 0, gate: 0 });
        } else {
            array_push(_out, { freq: _f, gate: 1 });
        }
    }

    return _out;
}