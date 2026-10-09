/// Instrument command helpers for the Music Maker's COMMANDS box:
/// WAVE / NOTE / HOLD / LOOP / END dropdowns that insert a ready-made line at
/// the text cursor, and a ? button that lays a help table over the box.
///
/// All of it is called twice per frame from scr_sound_editor_draw_instruments:
///   scr_sound_editor_cmd_bar(..., false) at the COMMANDS header — draws the
///       buttons and handles every click (returns true when it used the click,
///       so the command box doesn't also react to it);
///   scr_sound_editor_cmd_bar(..., true)  after the box — draws the open list
///       or the help table on top of it.

/// The dropdowns' contents. LOOP is built from the instrument's own lines.
function scr_sound_editor_cmd_menus(_lines) {
    var _loop = [];
    for (var _li = 0; _li < min(array_length(_lines), 16); _li++) {
        var _n = string(_li);
        while (string_length(_n) < 2) { _n = "0" + _n; }
        array_push(_loop, { ins: "L" + string(_li), label: "BACK TO " + _n + ": " + string_trim(_lines[_li]) });
    }
    if (array_length(_loop) == 0) {
        array_push(_loop, { ins: "L0", label: "BACK TO THE FIRST STEP" });
    }
    array_push(_loop,{ins:"R3:0",label:"REPEAT FROM STEP 0 THREE MORE TIMES"});
    return [
        { id: "WAVE", items: [
            { ins: "$11", label: "TRIANGLE" },
            { ins: "$21", label: "SAWTOOTH" },
            { ins: "$41", label: "PULSE" },
            { ins: "$81", label: "NOISE" },
            { ins: "$15", label: "TRI + RING MOD" },
            { ins: "$13", label: "TRI + SYNC" },
            { ins: "$17", label: "TRI + RING + SYNC" },
            { ins: "$23", label: "SAW + SYNC" },
            { ins: "$43", label: "PULSE + SYNC" },
            { ins: "$61", label: "SAW + PULSE" },
            { ins: "$51", label: "TRI + PULSE" },
            { ins: "$31", label: "TRI + SAW" }
        ] },
        { id: "NOTE", items: [
            { ins: "N",    label: "THE PLAYED NOTE" },
            { ins: "N+12", label: "OCTAVE UP" },
            { ins: "N-12", label: "OCTAVE DOWN" },
            { ins: "N+7",  label: "FIFTH UP" },
            { ins: "N+5",  label: "FOURTH UP" },
            { ins: "N+4",  label: "MAJOR THIRD UP" },
            { ins: "N+3",  label: "MINOR THIRD UP" },
            { ins: "N+2",  label: "TONE UP" },
            { ins: "N+1",  label: "SEMITONE UP" },
            { ins: "N-1",  label: "SEMITONE DOWN" },
            { ins: "N+24", label: "TWO OCTAVES UP" },
            { ins: "N=81", label: "FIXED NOTE 81 (ANY ROW NOTE) - NOISE CLICKS" }
        ] },
        { id: "HOLD", items: [
            { ins: "D1",   label: "1 FRAME (FASTEST ARP)" },
            { ins: "D2",   label: "2 FRAMES" },
            { ins: "D3",   label: "3 FRAMES" },
            { ins: "D4",   label: "4 FRAMES" },
            { ins: "D6",   label: "6 FRAMES" },
            { ins: "D8",   label: "8 FRAMES" },
            { ins: "D12",  label: "12 FRAMES" },
            { ins: "D25",  label: "HALF A SECOND" },
            { ins: "D50",  label: "ONE SECOND" },
            { ins: "D255", label: "~5 SECONDS (SUSTAIN)" }
        ] },
        { id: "LOOP", items: _loop },
        { id: "FINE", items: [
            { ins: "F+1", label: "ADD 1 SID PITCH UNIT" },
            { ins: "F-1", label: "SUBTRACT 1 SID PITCH UNIT" },
            { ins: "F+40", label: "FINE RISE (FOLLOW WITH D1 / LOOP)" },
            { ins: "P$800", label: "PULSE WIDTH $800 (0-$FFF)" },
            { ins: "S+40", label: "SLIDE PITCH +40 EACH FRAME" },
            { ins: "S0", label: "STOP INSTRUMENT PITCH SLIDE" },
            { ins: "Q+32", label: "SWEEP PULSE +32 EACH FRAME" },
            { ins: "Q0", label: "STOP INSTRUMENT PULSE SWEEP" },
            { ins: "G$40", label: "GATE OFF, CONTINUE THE PROGRAM" },
            { ins: "G$41", label: "PULSE GATE ON, CONTINUE" },
            { ins: "H0", label: "KEEP ENVELOPE: BYPASS HARD RESTART" },
            { ins: "H1", label: "USE THE PLAYER HARD RESTART SETTING" },
            { ins: "PK", label: "KEEP PULSE WIDTH ON NEW NOTES (FOR ~PULSE+)" }
        ] },
        { id: "END", items: [
            { ins: "---", label: "GATE OFF + STOP (NOTE RELEASES)" }
        ] }
    ];
}

/// Inserts _ins as its own line at the text cursor, opening the instrument's
/// text for editing first if it wasn't. A blank cursor line takes it in place.
function scr_sound_editor_cmd_insert(_m, _instr, _ins) {
    if (!_m.instr_edit_active) {
        _m.instr_edit_active      = true;
        _m.instr_edit_buf         = _instr.text;
        _m.instr_edit_cursor      = string_length(_m.instr_edit_buf);
        _m.instr_name_edit_active = false;
    }
    var _buf = _m.instr_edit_buf;
    var _cur = _m.instr_edit_cursor;
    var _ls = _cur;
    while (_ls > 0 && string_char_at(_buf, _ls) != "\n") {
        _ls -= 1;
    }
    var _le = _cur;
    while (_le < string_length(_buf) && string_char_at(_buf, _le + 1) != "\n") {
        _le += 1;
    }
    var _line = string_trim(string_copy(_buf, _ls + 1, _le - _ls));
    if (_line == "") {
        _m.instr_edit_buf    = string_delete(_buf, _ls + 1, _le - _ls);
        _m.instr_edit_buf    = string_insert(_ins, _m.instr_edit_buf, _ls + 1);
        _m.instr_edit_cursor = _ls + string_length(_ins);
    } else {
        _m.instr_edit_buf    = string_insert("\n" + _ins, _buf, _le + 1);
        _m.instr_edit_cursor = _le + 1 + string_length(_ins);
    }
}

/// _x0/_x1: the COMMANDS column's left/right edges; _y: header row.
/// _bx0.._by1: the command box (the help table covers it).
function scr_sound_editor_cmd_bar(_m, _instr, _x0, _x1, _y, _bx0, _by0, _bx1, _by1, _mx, _my, _draw_top) {
    var _src = _instr.text;
    if (_m.instr_edit_active) {
        _src = _m.instr_edit_buf;
    }
    var _menus = scr_sound_editor_cmd_menus(string_split(_src, "\n"));
    var _bh = 16;
    var _row_h = 16;
    var _lw = 230;
    var _gap = 3;

    // Button layout, right-aligned: WAVE NOTE HOLD LOOP FINE END ?
    // Laid out from the right; when a row would run past the column's left
    // edge the rest stack on the row ABOVE, so the bar never spills into the
    // instrument list's header (+ PRESETS).
    var _n_menu = array_length(_menus);
    var _bw = array_create(_n_menu, 0);
    var _bx = array_create(_n_menu, 0);
    var _by = array_create(_n_menu, _y);
    for (var _i = 0; _i < _n_menu; _i++) {
        _bw[_i] = string_width_l(_menus[_i].id) + 10;
    }
    var _qw = string_width_l("?") + 10;
    var _qx = _x1 - _qw;
    var _qy = _y;
    var _cx = _qx - _gap;
    var _cy = _y;
    for (var _i = _n_menu - 1; _i >= 0; _i--) {
        if (_cx - _bw[_i] < _x0 && _cx < _x1 - _qw - _gap) {
            _cx = _x1;
            _cy -= _bh + _gap;
        }
        _bx[_i] = _cx - _bw[_i];
        _by[_i] = _cy;
        _cx = _bx[_i] - _gap;
    }

    // The open list (if any).
    var _open = -1;
    for (var _i = 0; _i < array_length(_menus); _i++) {
        if (_m.cmd_menu_open == _menus[_i].id) {
            _open = _i;
        }
    }
    var _lx1 = 0;
    var _ly1 = _y + _bh + 2;
    var _ly2 = _ly1;
    if (_open >= 0) {
        _lx1 = clamp(_bx[_open] + _bw[_open] - _lw, _x0 - 4, _x1 - _lw);
        _ly2 = _ly1 + array_length(_menus[_open].items) * _row_h + 4;
    }

    if (_draw_top) {
        draw_set_font_l(fnt_c64_pico);
        if (_open >= 0) {
            var _its = _menus[_open].items;
            draw_set_color(make_color_rgb(20, 20, 32));
            draw_rectangle(_lx1, _ly1, _lx1 + _lw, _ly2, false);
            draw_set_color(make_color_rgb(120, 120, 170));
            draw_rectangle(_lx1, _ly1, _lx1 + _lw, _ly2, true);
            for (var _i = 0; _i < array_length(_its); _i++) {
                var _iy = _ly1 + 2 + _i * _row_h;
                var _hov = point_in_rectangle(_mx, _my, _lx1, _iy, _lx1 + _lw, _iy + _row_h - 1);
                scr_mm_info(_hov, "INSERTS " + _its[_i].ins + " (" + _its[_i].label + ") AT THE TEXT CURSOR");
                if (_hov) {
                    draw_set_color(make_color_rgb(50, 50, 90));
                    draw_rectangle(_lx1 + 1, _iy, _lx1 + _lw - 1, _iy + _row_h - 1, false);
                }
                draw_set_color(make_color_rgb(255, 200, 100));
                draw_text_l(_lx1 + 6, _iy + 3, _its[_i].ins);
                if (_hov) {
                    draw_set_color(c_yellow);
                } else {
                    draw_set_color(c_white);
                }
                var _lab = _its[_i].label;
                while (string_length(_lab) > 1 && string_width_l(_lab) > _lw - 56) {
                    _lab = string_copy(_lab, 1, string_length(_lab) - 1);
                }
                draw_text_l(_lx1 + 50, _iy + 3, _lab);
            }
        } else if (_m.cmd_help_open) {
            scr_sound_editor_cmd_help(_bx0, _by0, _bx1, _by1);
        }
        draw_set_font_l(fnt_c64_tiny);
        return false;
    }

    // ── buttons ──
    draw_set_font_l(fnt_c64_pico);
    for (var _i = 0; _i <= array_length(_menus); _i++) {
        var _is_q = (_i == array_length(_menus));
        var _x = _qx;
        var _w = _qw;
        var _yy = _qy;
        var _lab = "?";
        var _on = _m.cmd_help_open;
        if (!_is_q) {
            _x = _bx[_i];
            _w = _bw[_i];
            _yy = _by[_i];
            _lab = _menus[_i].id;
            _on = (_open == _i);
        }
        var _hv = point_in_rectangle(_mx, _my, _x, _yy, _x + _w, _yy + _bh);
        scr_mm_info(_hv, scr_mm_button_info("CMD:" + _lab));
        if (_hv || _on) {
            draw_set_color(make_color_rgb(60, 60, 110));
        } else {
            draw_set_color(make_color_rgb(40, 40, 70));
        }
        draw_rectangle(_x, _yy, _x + _w, _yy + _bh, false);
        if (_hv) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(c_white);
        }
        draw_text_l(_x + 5, _yy + 3, _lab);
    }
    draw_set_font_l(fnt_c64_tiny);

    if (!mouse_check_button_pressed(mb_left)) {
        return false;
    }
    // A button: toggle its list (or the help), closing anything else.
    for (var _i = 0; _i <= array_length(_menus); _i++) {
        var _is_q = (_i == array_length(_menus));
        var _x = _qx;
        var _w = _qw;
        var _yy = _qy;
        if (!_is_q) {
            _x = _bx[_i];
            _w = _bw[_i];
            _yy = _by[_i];
        }
        if (point_in_rectangle(_mx, _my, _x, _yy, _x + _w, _yy + _bh)) {
            if (_is_q) {
                _m.cmd_help_open = !_m.cmd_help_open;
                _m.cmd_menu_open = "";
            } else {
                if (_open == _i) {
                    _m.cmd_menu_open = "";
                } else {
                    _m.cmd_menu_open = _menus[_i].id;
                }
                _m.cmd_help_open = false;
            }
            return true;
        }
    }
    // Help open: any click closes it.
    if (_m.cmd_help_open) {
        _m.cmd_help_open = false;
        return true;
    }
    if (_open < 0) {
        return false;
    }
    // List open: a click picks an entry or just closes it.
    _m.cmd_menu_open = "";
    if (!point_in_rectangle(_mx, _my, _lx1, _ly1, _lx1 + _lw, _ly2)) {
        return true;
    }
    var _pick = floor((_my - _ly1 - 2) / _row_h);
    if (_pick >= 0 && _pick < array_length(_menus[_open].items)) {
        scr_sound_editor_cmd_insert(_m, _instr, _menus[_open].items[_pick].ins);
    }
    return true;
}

/// The ? table: what each instrument command does, with an example.
function scr_sound_editor_cmd_help(_x0, _y0, _x1, _y1) {
    draw_set_color(make_color_rgb(14, 14, 24));
    draw_rectangle(_x0, _y0, _x1, _y1, false);
    draw_set_color(make_color_rgb(120, 120, 170));
    draw_rectangle(_x0, _y0, _x1, _y1, true);
    var _rows = [
        ["INSTRUMENT PROGRAM: RUNS FROM STEP 00 WHEN A NOTE PLAYS", ""],
        ["", ""],
        ["$xx", "set the waveform (see WAVE)"],
        ["", "$41 pulse  $21 saw  $11 tri  $81 noise"],
        ["", "the gate stays on until --- or a rest"],
        ["N", "play the pattern's note"],
        ["N+n / N-n", "the note shifted n semitones"],
        ["", "N+12 octave up, N+7 fifth, N+4 3rd"],
        ["F+n / F-n", "add/subtract SID pitch units once"],
        ["S+n / S-n", "pitch slide each frame; S0 stops"],
        ["P$xxx", "exact pulse width $000-$FFF"],
        ["Q+n / Q-n", "pulse sweep each frame; Q0 stops"],
        ["G$xx", "raw waveform + gate; keeps stepping"],
        ["H0 / H1", "bypass / inherit player hard restart"],
        ["Dn", "wait n frames before the next step"],
        ["", "50 frames = 1 second (PAL)"],
        ["Ln", "jump back to step n (loops forever)"],
        ["R3:8", "repeat from step 8 three MORE times, then continue"],
        ["~PITCH", "table of S/D/L lines, runs beside the program"],
        ["~PULSE", "table of Q/D/L lines, runs beside the program"],
        ["~PITCH+", "same, but carries on across new notes / ties"],
        ["~FILTER", "table of C/D/L lines: cutoff speed per frame"],
        ["C$400", "set the filter cutoff ($000-$7FF)"],
        ["V$44", "vibrato from here: speed 4, depth 4 (V0 stops)"],
        ["~PITCH4", "table stepping 4x a frame: Dn counts quarter frames"],
        [">nn", "end a table by carrying on in instrument nn's table"],
        ["", "the program must keep running (Dn / Ln) to hear them"],
        ["---", "gate off + stop: the note releases"],
        ["", ""],
        ["EXAMPLES", ""],
        ["plain lead", "$41 / D255 / L1"],
        ["major arp", "$41 / N / D1 / N+4 / D1 / N+7 / D1 / L1"],
        ["minor arp", "$41 / N / D1 / N+3 / D1 / N+7 / D1 / L1"],
        ["octave arp", "$41 / N / D1 / N+12 / D1 / L1"],
        ["drum", "$81 / N+24 / D1 / $41 / N / D3 / ---"],
        ["", ""],
        ["CLICK ANYWHERE TO CLOSE", ""]
    ];
    draw_set_font_l(fnt_c64_pico);
    for (var _i = 0; _i < array_length(_rows); _i++) {
        var _ry = _y0 + 6 + _i * 13;
        if (_ry + 12 > _y1) {
            break;
        }
        // Rows with no second column are headings and may run across it.
        draw_set_color(make_color_rgb(255, 200, 100));
        draw_text_l(_x0 + 6, _ry, _rows[_i][0]);
        draw_set_color(make_color_rgb(200, 200, 220));
        draw_text_l(_x0 + 84, _ry, _rows[_i][1]);
    }
    draw_set_font_l(fnt_c64_tiny);
}

/// Readable explanation of one instrument program line, for the command box's
/// side column. _lines is the whole program (so a loop can say where it goes).
/// Returns { text, bad } — bad marks something that won't do what it looks like.
function scr_sound_editor_instr_comment(_line, _lines) {
    var _raw = string_trim(_line);
    var _up  = string_upper(_raw);
    if (_raw == "") {
        return { text: "", bad: false };
    }

    // ~PITCH / ~PULSE : table sections that run alongside the program
    if (string_char_at(_up, 1) == "~") {
        if (_up == "~PITCH") return { text: "pitch table: S/D/L lines on their own counter", bad: false };
        if (_up == "~PULSE") return { text: "pulse table: Q/D/L lines on their own counter", bad: false };
        if (_up == "~PITCH+") return { text: "pitch table that keeps running across notes", bad: false };
        if (_up == "~PULSE+") return { text: "pulse table that keeps running across notes", bad: false };
        if (_up == "~FILTER") return { text: "filter table: C/D/L lines move the cutoff", bad: false };
        if (_up == "~FILTER+") return { text: "filter table that keeps running across notes", bad: false };
        if (string_char_at(_up, string_length(_up)) == "4" || string_copy(_up, string_length(_up) - 1, 2) == "4+") {
            return { text: "table stepping 4x a frame (Dn = quarter frames)", bad: false };
        }
        return { text: "? tables are ~PITCH, ~PULSE or ~FILTER", bad: true };
    }
    if (string_copy(_up, 1, 2) == "C$") {
        return { text: "set filter cutoff to " + string_delete(_up, 1, 1), bad: false };
    }

    // --- : end
    var _all_dash = true;
    for (var _di = 1; _di <= string_length(_up); _di++) {
        if (string_char_at(_up, _di) != "-") {
            _all_dash = false;
            break;
        }
    }
    if (_all_dash) {
        return { text: "gate off, program stops - the note releases", bad: false };
    }

    var _c0 = string_char_at(_up, 1);
    var _rest = string_delete(_up, 1, 1);

    if (_up == "H0" || _up == "H1") {
        return { text: _up == "H0" ? "instrument setting: bypass hard restart (keep envelope)" : "instrument setting: use player hard restart", bad: false };
    }
    if (_c0 == "G") {
        var _gp = scr_instrument_parse(_raw);
        return { text: array_length(_gp.errors) > 0 ? "? use G$00..G$FF" : "raw gate/wave byte; program continues", bad: array_length(_gp.errors) > 0 };
    }
    if ((_c0 == "F" && (string_char_at(_up, 2) == "+" || string_char_at(_up, 2) == "-")) || _c0 == "P" || _c0 == "S" || _c0 == "Q") {
        var _parsed = scr_instrument_parse(_raw);
        if (array_length(_parsed.errors) > 0) return { text: _parsed.errors[0], bad: true };
        var _desc = "fine pitch change (SID units)";
        if (_c0 == "P") _desc = "set exact pulse width (0-$FFF)";
        if (_c0 == "S") _desc = "pitch slide per frame; S0 stops";
        if (_c0 == "Q") _desc = "pulse sweep per frame; Q0 stops (wraps 12-bit)";
        return { text: _desc + "; Dn sets duration", bad: false };
    }
    // V$xy : vibrato from here
    if (_c0 == "V") {
        if (_up == "V0" || _up == "V$00") return { text: "vibrato off", bad: false };
        return { text: "vibrato from here: speed x, depth y (as pattern 4XY)", bad: false };
    }
    // >nn : carry on in another instrument's table
    if (_c0 == ">") {
        return { text: "continue in instrument " + string_delete(_up, 1, 1) + "'s table of this kind", bad: false };
    }
    // C+n / C-n : a ~FILTER table's cutoff speed
    if (_c0 == "C" && (string_char_at(_up, 2) == "+" || string_char_at(_up, 2) == "-")) {
        return { text: "cutoff speed per frame (in a ~FILTER table); Dn sets duration", bad: false };
    }
    // N=n : a fixed table note, whatever note the row plays
    if (_c0 == "N" && string_char_at(_rest, 1) == "=") {
        var _abs_d = string_digits(string_delete(_rest, 1, 1));
        if (_abs_d == "" || string_length(_abs_d) != string_length(_rest) - 1 || real(_abs_d) > 95) {
            return { text: "? write N=0 .. N=95", bad: true };
        }
        var _abs_n = real(_abs_d);
        var _abs_names = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"];
        return { text: "fixed note " + _abs_names[_abs_n mod 12] + string(_abs_n div 12) + " (ignores the row note)", bad: false };
    }
    if (_up == "PK") {
        return { text: "instrument setting: keep the pulse width on new notes", bad: false };
    }
    // N / N+n / N-n : note
    if (_c0 == "N") {
        if (_rest == "" || _rest == "+0" || _rest == "-0") {
            return { text: "play the pattern's note", bad: false };
        }
        var _sgn = string_char_at(_rest, 1);
        var _num = string_digits(string_delete(_rest, 1, 1));
        if ((_sgn != "+" && _sgn != "-") || _num == "" || string_length(_num) != string_length(_rest) - 1) {
            return { text: "? write N, N+n or N-n", bad: true };
        }
        var _n = real(_num);
        var _names = ["unison", "semitone", "tone", "minor 3rd", "major 3rd", "4th", "tritone",
                      "5th", "minor 6th", "major 6th", "minor 7th", "major 7th"];
        var _desc = _names[_n mod 12];
        var _oct = _n div 12;
        if (_n mod 12 == 0) {
            _desc = string(_oct) + " octave";
            if (_oct > 1) {
                _desc += "s";
            }
        } else if (_oct > 0) {
            _desc += " + " + string(_oct) + " oct";
        }
        var _dir = "up";
        if (_sgn == "-") {
            _dir = "down";
        }
        return { text: "note " + _dir + " " + string(_n) + " (" + _desc + ")", bad: false };
    }

    // Dn : hold
    if (_c0 == "D") {
        var _dn = string_digits(_rest);
        if (_dn == "" || string_length(_dn) != string_length(_rest)) {
            return { text: "? write Dn, n = 1-255 frames", bad: true };
        }
        var _d = real(_dn);
        if (_d < 1 || _d > 255) {
            return { text: "? hold must be 1-255 frames", bad: true };
        }
        var _secs = string_format(_d / 50, 1, 2);
        var _fr = " frames";
        if (_d == 1) {
            _fr = " frame";
        }
        return { text: "hold " + string(_d) + _fr + " (" + string_trim(_secs) + " s)", bad: false };
    }

    if (_c0 == "R") {
        var _rp = string_split(_rest,":");
        if (array_length(_rp) != 2) return {text:"? write Rcount:step, e.g. R3:8",bad:true};
        return {text:"repeat from step " + _rp[1] + " another " + _rp[0] + " times, then continue",bad:false};
    }
    // Ln : loop
    if (_c0 == "L") {
        var _ln = string_digits(_rest);
        if (_ln == "" || string_length(_ln) != string_length(_rest)) {
            return { text: "? write Ln, n = a step number", bad: true };
        }
        var _l = real(_ln);
        if (_l >= array_length(_lines)) {
            return { text: "! step " + string(_l) + " doesn't exist", bad: true };
        }
        var _to = string_trim(_lines[_l]);
        return { text: "loop back to step " + string(_l) + " (" + _to + ")", bad: false };
    }

    // $xx / xx : waveform + control bits
    var _hex = _up;
    if (string_char_at(_hex, 1) == "$") {
        _hex = string_delete(_hex, 1, 1);
    }
    var _is_hex = (string_length(_hex) > 0 && string_length(_hex) <= 2);
    for (var _hi = 1; _hi <= string_length(_hex); _hi++) {
        if (string_pos(string_char_at(_hex, _hi), "0123456789ABCDEF") == 0) {
            _is_hex = false;
            break;
        }
    }
    if (!_is_hex) {
        return { text: "? not a command - see WAVE/NOTE/HOLD/LOOP/END", bad: true };
    }
    var _v = real(hex_to_decimal(_hex));
    var _w = [];
    if (_v & 0x10) array_push(_w, "triangle");
    if (_v & 0x20) array_push(_w, "saw");
    if (_v & 0x40) array_push(_w, "pulse");
    if (_v & 0x80) array_push(_w, "noise");
    var _txt = "silent (no waveform)";
    if (array_length(_w) > 0) {
        _txt = string_join_ext(" + ", _w);
    }
    if (_v & 0x04) _txt += ", ring mod";
    if (_v & 0x02) _txt += ", sync";
    if (_v & 0x08) _txt += ", TEST (oscillator held)";
    // The player always turns the gate bit on for a program waveform line.
    if ((_v & 0x01) == 0) {
        _txt += " (gate forced on)";
    }
    return { text: _txt, bad: false };
}

/// Pattern commands use hexadecimal digits; instrument VIB fields are decimal.
function scr_sound_editor_vibrato_help() {
    return "INSTRUMENT VIB (DECIMAL VALUES)"
        + "\nDL = DELAY IN FRAMES BEFORE VIBRATO STARTS."
        + "\nSP = SPEED: FRAMES PER HALF-SWING. HIGHER = SLOWER."
        + "\nDP = DEPTH: PITCH CHANGE OF DP * 4 PER FRAME."
        + "\nSP OR DP = 0 DISABLES INSTRUMENT VIBRATO."
        + "\n4XY OVERRIDES IT FOR THAT ROW; IT CAN RESUME AFTERWARD.";
}

/// Shared by command-cell hover and the command legend's reference tooltip.
function scr_sound_editor_pattern_help(_cmd) {
    switch (_cmd) {
        case 0: return "0XX: NO PATTERN EFFECT THIS ROW (XX IS IGNORED).\nINSTRUMENT VIBRATO CAN STILL RUN.";
        case 1: return "1XX: SLIDE PITCH UP BY XX * 4 PER FRAME, THIS ROW ONLY.";
        case 2: return "2XX: SLIDE PITCH DOWN BY XX * 4 PER FRAME, THIS ROW ONLY.";
        case 3: return "3XX: SLIDE TOWARD THE NOTE AT XX * 4 PER FRAME.\nTHIS ROW ONLY; STOPS AT THE TARGET PITCH.";
        case 4: return "4XY: VIBRATO (HEX DIGITS 0-F)"
            + "\nX = SPEED: FRAMES PER HALF-SWING. HIGHER = SLOWER."
            + "\nY = DEPTH: PITCH CHANGE OF Y * 4 PER FRAME. HIGHER = WIDER."
            + "\nBOTH X AND Y AFFECT THE TOTAL SWING; LOW NOTES SOUND WIDER."
            + "\n448: 4 FRAMES PER HALF-SWING, DEPTH 8 (32 UNITS PER FRAME)."
            + "\nFIRST SWING STARTS PARTWAY THROUGH THE CYCLE."
            + "\n400 (OR X/Y = 0): NO VIBRATO THIS ROW."
            + "\n4XY LASTS ONE ROW; REPEAT IT ON FOLLOWING ROWS TO CONTINUE.";
        case 5: return "5AD: SET ATTACK (A) AND DECAY (D), HEX 0-F EACH.";
        case 6: return "6SR: SET SUSTAIN (S) AND RELEASE (R), HEX 0-F EACH.";
        case 7: return "7XX: SET SID WAVEFORM / CONTROL BYTE.\n711 TRIANGLE, 721 SAW, 741 PULSE, 781 NOISE (GATE ON).";
        case 8: return "8XX: SET PULSE WIDTH TO HEX XX * 16.\n800 = ZERO, 880 = HALF, 8FF = NEAR MAXIMUM.";
        case 9: return "9XX: PULSE-WIDTH SWEEP, THIS ROW ONLY.\n01-7F UP; 80-FF DOWN (FF = -1, F0 = -16 PER FRAME).";
        case 10: return "AXX: SET FILTER CUTOFF TO HEX XX * 8.\nA00 = ZERO, AFF = 2040. FILTER IS SHARED BY ALL VOICES.";
        case 11: return "BX0: SET FILTER RESONANCE X (HEX 0-F).\nLAST DIGIT IS IGNORED; VOICE ROUTING IS PRESERVED.";
        case 12: return "CXX: FILTER CUTOFF SWEEP, THIS ROW ONLY.\n01-7F UP; 80-FF DOWN (FF = -1 PER FRAME).\nSTOPS AT 0 OR 2047; FILTER IS SHARED BY ALL VOICES.";
        case 13: return "DXX: SET THE FULL SID $D418 BYTE.\nHIGH DIGIT: FILTER MODE; LOW DIGIT: VOLUME (0-F).";
        case 14: return "EXX: SET FILTER MODE, KEEP VOLUME.\nLOW DIGIT BITS: 1 LOW-PASS, 2 BAND-PASS, 4 HIGH-PASS, 8 VOICE 3 OFF.";
        case 16: return "GXX: ADD A SIGNED FINE PITCH OFFSET ONCE.\n01-7F UP, 80-FF DOWN (FF = -1). APPLIES AFTER HARD RESTART.";
        case 17: return "HXX: CONTINUOUS PITCH SWEEP IN SINGLE SID UNITS PER FRAME.\n01-7F UP, 80-FF DOWN. H00 STOPS.\nPERSISTS ACROSS ROWS; A NEW NOTE OR INSTRUMENT S COMMAND REPLACES IT.";
        case 18: return "IXX: CONTINUOUS PULSE SWEEP, WITH 12-BIT WRAP.\n01-7F UP, 80-FF DOWN. I00 STOPS.\nPERSISTS ACROSS ROWS; A NEW NOTE OR INSTRUMENT Q COMMAND REPLACES IT.";
        case 15: return "FXX: SET FRAMES PER ROW (HEX). HIGHER = SLOWER. F00 IS IGNORED."
            + "\nSHARED TIMING: AFFECTS THE WHOLE SONG FROM THE NEXT ROW."
            + "\nPER VOICE TIMING: THIS VOICE ONLY, FROM THIS ROW ON (F01-F7F);"
            + "\nF80-FFF SETS SPEED XX-80 AND MAKES THIS ROW TAKE NO TIME.";
        case 19: return "J00 ON A NOTE: TIE. CHANGE PITCH WITHOUT RESTARTING THE NOTE."
            + "\nENVELOPE, GATE, PULSE WIDTH, SWEEPS AND RUNNING TABLES CARRY ON."
            + "\nWITH AN INSTRUMENT IN THE ROW, ITS PROGRAM TAKES OVER (E.G. A NEW ARP)"
            + "\nAND ITS ~PITCH+/~PULSE+ TABLES CONTINUE IF THEY MATCH THE RUNNING ONES.";
    }
    return "PATTERN COMMAND GUIDE"
        + "\nSELECT NOTES: CTRL+Q/A = SEMITONE UP/DOWN; CTRL+W/S = OCTAVE UP/DOWN."
        + "\nALSO CTRL+=/- OR NUMPAD +/-: SEMITONE. ADD SHIFT FOR AN OCTAVE."
        + "\nCLICK A COMMAND CELL, THEN TYPE A COMMAND (0-J), THEN TWO HEX DIGITS (0-F)."
        + "\nTHIRD DIGIT STORES IT; ENTER PADS WITH ZEROS AND MOVES DOWN."
        + "\nBACKSPACE ERASES A TYPED DIGIT; WITH NO PENDING DIGITS IT CLEARS THE COMMAND."
        + "\nDELETE CLEARS THE COMMAND; ESC CANCELS PENDING TYPING. NOTES STAY IN PLACE."
        + "\nTHE GUIDE BUTTON LISTS EVERY COMMAND. 1-4, 9 AND C LAST ONE ROW.";
}

/// Top of the GUIDE panel: how to enter commands and notes, transpose keys,
/// and the digi lane's keys.
function scr_sound_editor_guide_intro() {
    return "COMMAND CELLS: CLICK THE CELL RIGHT OF A NOTE, TYPE A COMMAND (0-J) THEN TWO HEX DIGITS (0-F). THE THIRD DIGIT STORES IT;"
        + " ENTER PADS WITH ZEROS AND MOVES DOWN. BACKSPACE ERASES A TYPED DIGIT, OR CLEARS THE COMMAND WHEN NOTHING IS PENDING."
        + " DELETE CLEARS THE COMMAND; ESC CANCELS PENDING TYPING. NOTES STAY IN PLACE."
        + "\nTRANSPOSE SELECTED NOTES: CTRL+Q / CTRL+A = SEMITONE UP / DOWN, CTRL+W / CTRL+S = OCTAVE UP / DOWN."
        + " ALSO CTRL+= / CTRL+- OR NUMPAD + / -: SEMITONE, ADD SHIFT FOR AN OCTAVE."
        + "\nVIBRATO 4XY: X = FRAMES PER HALF-SWING, Y = DEPTH (Y * 4 PER FRAME); E.G. 448. IT LASTS ONE ROW, SO REPEAT IT TO CONTINUE."
        + "\nDIGI LANE: PIANO KEYS PLACE A NOTE WITH THE CURRENT SAMPLE SLOT (C-4 = THE SAMPLE'S OWN PITCH).  , / . SLOT DOWN / UP.  [ / ] VOLUME."
        + "  - OFF.  DEL / BACKSPACE CLEAR.  SHIFT+UP / DOWN SELECT.  CTRL+C / X / V COPY, CUT, PASTE.  CTRL+Z / Y UNDO, REDO.  RMB CLEARS A CELL.";
}
