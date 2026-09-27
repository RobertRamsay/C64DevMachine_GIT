/// @function scr_sound_editor_wave_menu(_m, _instr, _x, _y, _mx, _my, _draw_list)
/// @desc The instrument panel's [WAVE] dropdown — an alternative to typing a
///       $xx waveform line. Picking an entry inserts that line at the text
///       cursor (its own line), opening the instrument text for editing if it
///       wasn't; commit as usual (Ctrl+Enter or click away).
///
///       Called twice per frame: _draw_list false at the COMMANDS header (draws
///       the button, handles every click) and _draw_list true at the end of the
///       panel so the open list is drawn over the command box.
///       Returns true when it used this frame's click, so the command box
///       under the list doesn't also react to it.
function scr_sound_editor_wave_menu(_m, _instr, _x, _y, _mx, _my, _draw_list) {
    // Ring modulation uses the previous voice (1 <- 3, 2 <- 1, 3 <- 2); sync
    // locks to it. Only triangle carries ring mod.
    var _items = [
        { name: "TRIANGLE",          code: 0x11 },
        { name: "SAWTOOTH",          code: 0x21 },
        { name: "PULSE",             code: 0x41 },
        { name: "NOISE",             code: 0x81 },
        { name: "TRI + RING MOD",    code: 0x15 },
        { name: "TRI + SYNC",        code: 0x13 },
        { name: "TRI + RING + SYNC", code: 0x17 },
        { name: "SAW + SYNC",        code: 0x23 },
        { name: "PULSE + SYNC",      code: 0x43 },
        { name: "SAW + PULSE",       code: 0x61 },
        { name: "TRI + PULSE",       code: 0x51 },
        { name: "TRI + SAW",         code: 0x31 }
    ];
    var _bw = 60;
    var _bh = 18;
    var _row_h = 18;
    var _lw = 200;
    var _lx1 = _x + _bw - _lw;
    var _ly1 = _y + _bh + 2;
    var _ly2 = _ly1 + array_length(_items) * _row_h + 4;

    if (_draw_list) {
        if (!_m.wave_menu_open) {
            return false;
        }
        draw_set_color(make_color_rgb(20, 20, 32));
        draw_rectangle(_lx1, _ly1, _lx1 + _lw, _ly2, false);
        draw_set_color(make_color_rgb(120, 120, 170));
        draw_rectangle(_lx1, _ly1, _lx1 + _lw, _ly2, true);
        for (var _i = 0; _i < array_length(_items); _i++) {
            var _iy = _ly1 + 2 + _i * _row_h;
            var _hov = point_in_rectangle(_mx, _my, _lx1, _iy, _lx1 + _lw, _iy + _row_h - 1);
            if (_hov) {
                draw_set_color(make_color_rgb(50, 50, 90));
                draw_rectangle(_lx1 + 1, _iy, _lx1 + _lw - 1, _iy + _row_h - 1, false);
            }
            var _hex = string_upper(decimal_to_hex(_items[_i].code));
            while (string_length(_hex) < 2) { _hex = "0" + _hex; }
            draw_set_color(make_color_rgb(255, 200, 100));
            draw_text_l(_lx1 + 6, _iy + 2, "$" + _hex);
            if (_hov) {
                draw_set_color(c_yellow);
            } else {
                draw_set_color(c_white);
            }
            draw_text_l(_lx1 + 46, _iy + 2, _items[_i].name);
        }
        return false;
    }

    // ── button ──
    var _bhov = point_in_rectangle(_mx, _my, _x, _y, _x + _bw, _y + _bh);
    if (_bhov || _m.wave_menu_open) {
        draw_set_color(make_color_rgb(60, 60, 110));
    } else {
        draw_set_color(make_color_rgb(40, 40, 70));
    }
    draw_rectangle(_x, _y, _x + _bw, _y + _bh, false);
    if (_bhov) {
        draw_set_color(c_yellow);
    } else {
        draw_set_color(c_white);
    }
    draw_text_l(_x + 6, _y + 3, "[WAVE]");

    if (!mouse_check_button_pressed(mb_left)) {
        return false;
    }
    if (_bhov) {
        _m.wave_menu_open = !_m.wave_menu_open;
        return true;
    }
    if (!_m.wave_menu_open) {
        return false;
    }
    // A click with the list open either picks an entry or just closes it.
    _m.wave_menu_open = false;
    if (!point_in_rectangle(_mx, _my, _lx1, _ly1, _lx1 + _lw, _ly2)) {
        return true;
    }
    var _pick = floor((_my - _ly1 - 2) / _row_h);
    if (_pick < 0 || _pick >= array_length(_items)) {
        return true;
    }
    var _hexp = string_upper(decimal_to_hex(_items[_pick].code));
    while (string_length(_hexp) < 2) { _hexp = "0" + _hexp; }
    var _ins = "$" + _hexp;

    if (!_m.instr_edit_active) {
        _m.instr_edit_active      = true;
        _m.instr_edit_buf         = _instr.text;
        _m.instr_edit_cursor      = string_length(_m.instr_edit_buf);
        _m.instr_name_edit_active = false;
    }
    // Find the cursor's line; a blank line takes the code in place, otherwise
    // it goes on a new line after the current one.
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
    return true;
}
