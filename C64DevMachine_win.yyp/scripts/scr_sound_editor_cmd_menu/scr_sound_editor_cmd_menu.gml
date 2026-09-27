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
            { ins: "N+24", label: "TWO OCTAVES UP" }
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

    // Button layout, right-aligned: WAVE NOTE HOLD LOOP END ?
    var _bw = [];
    var _total = 0;
    for (var _i = 0; _i < array_length(_menus); _i++) {
        array_push(_bw, string_width_l(_menus[_i].id) + 10);
        _total += _bw[_i] + _gap;
    }
    var _qw = string_width_l("?") + 10;
    _total += _qw;
    var _bx = [];
    var _cx = _x1 - _total;
    for (var _i = 0; _i < array_length(_menus); _i++) {
        array_push(_bx, _cx);
        _cx += _bw[_i] + _gap;
    }
    var _qx = _cx;

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
        var _lab = "?";
        var _on = _m.cmd_help_open;
        if (!_is_q) {
            _x = _bx[_i];
            _w = _bw[_i];
            _lab = _menus[_i].id;
            _on = (_open == _i);
        }
        var _hv = point_in_rectangle(_mx, _my, _x, _y, _x + _w, _y + _bh);
        if (_hv || _on) {
            draw_set_color(make_color_rgb(60, 60, 110));
        } else {
            draw_set_color(make_color_rgb(40, 40, 70));
        }
        draw_rectangle(_x, _y, _x + _w, _y + _bh, false);
        if (_hv) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(c_white);
        }
        draw_text_l(_x + 5, _y + 3, _lab);
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
        if (!_is_q) {
            _x = _bx[_i];
            _w = _bw[_i];
        }
        if (point_in_rectangle(_mx, _my, _x, _y, _x + _w, _y + _bh)) {
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
        ["Dn", "wait n frames before the next step"],
        ["", "50 frames = 1 second (PAL)"],
        ["Ln", "jump back to step n (loops forever)"],
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
