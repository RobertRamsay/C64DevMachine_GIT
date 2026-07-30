function scr_code_editor_draw_find_dialogue(_px, _py, _pw, _mx, _my) {
    var _dw = 420;
    var _dh = 130;
    var _dx = _px + _pw - _dw - 20;
    var _dy = _py + 40;

    // Background fill
    draw_set_color(make_color_rgb(22, 26, 35));
    draw_rectangle(_dx, _dy, _dx + _dw, _dy + _dh, false);
    // Border
    draw_set_color(make_color_rgb(70, 180, 120));
    draw_rectangle(_dx, _dy, _dx + _dw, _dy + _dh, true);

    draw_set_font(fnt_c64_tiny);

    var _field_h  = 16;
    var _label_x  = _dx + 10;
    var _field_x  = _dx + 90;
    var _field_w  = _dw - 100;
    var _blink_on = (code_editor_blink mod 40 < 25);

    // --- FIND FIELD ---
    var _ty = _dy + 14;
    draw_set_color(make_color_rgb(120, 120, 180));
    draw_text(_label_x, _ty, "FIND:");

    var _f1_active = (code_editor_find_active_field == 1);
    draw_set_color(make_color_rgb(15, 18, 28));
    draw_rectangle(_field_x, _ty - 2, _field_x + _field_w, _ty + _field_h, false);
    draw_set_color(_f1_active ? make_color_rgb(80, 180, 120) : make_color_rgb(50, 55, 70));
    draw_rectangle(_field_x, _ty - 2, _field_x + _field_w, _ty + _field_h, true);
    draw_set_color(_f1_active ? c_white : make_color_rgb(150, 150, 150));
    var _f1_text = code_editor_find_text + ((_f1_active && _blink_on) ? "|" : "");
    draw_text(_field_x + 5, _ty, _f1_text);
    if (mouse_check_button_pressed(mb_left) && _mx >= _field_x && _mx <= _field_x + _field_w && _my >= _ty - 2 && _my <= _ty + _field_h) {
        code_editor_find_active_field = 1;
    }

    // --- REPLACE FIELD ---
    _ty += 28;
    draw_set_color(make_color_rgb(120, 120, 180));
    draw_text(_label_x, _ty, "REPLACE:");

    var _f2_active = (code_editor_find_active_field == 2);
    draw_set_color(make_color_rgb(15, 18, 28));
    draw_rectangle(_field_x, _ty - 2, _field_x + _field_w, _ty + _field_h, false);
    draw_set_color(_f2_active ? make_color_rgb(80, 180, 120) : make_color_rgb(50, 55, 70));
    draw_rectangle(_field_x, _ty - 2, _field_x + _field_w, _ty + _field_h, true);
    draw_set_color(_f2_active ? c_white : make_color_rgb(150, 150, 150));
    var _f2_text = code_editor_replace_text + ((_f2_active && _blink_on) ? "|" : "");
    draw_text(_field_x + 5, _ty, _f2_text);
    if (mouse_check_button_pressed(mb_left) && _mx >= _field_x && _mx <= _field_x + _field_w && _my >= _ty - 2 && _my <= _ty + _field_h) {
        code_editor_find_active_field = 2;
    }

    // --- BUTTONS ---
    var _bt_y  = _dy + _dh - 26;
    var _bt_h  = 20;
    var _bt_w  = 64;
    var _gap   = 5;
    var _search = string_trim(code_editor_find_text);

    var draw_btn = function(_x, _y, _w, _label, _enabled, _msx, _msy, _bth) {
        var _hov = (_enabled && _msx >= _x && _msx <= _x + _w && _msy >= _y && _msy <= _y + _bth);
        draw_set_color(_hov ? make_color_rgb(60, 160, 100) : (_enabled ? make_color_rgb(30, 50, 40) : make_color_rgb(25, 25, 30)));
        draw_rectangle(_x, _y, _x + _w, _y + _bth, false);
        draw_set_color(_hov ? c_white : (_enabled ? make_color_rgb(100, 200, 140) : make_color_rgb(60, 60, 70)));
        draw_rectangle(_x, _y, _x + _w, _y + _bth, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_x + _w / 2, _y + 4, _label);
        draw_set_halign(fa_left);
        return (_hov && mouse_check_button_pressed(mb_left));
    };

    var _bx = _dx + 6;

    // PREV
    if (draw_btn(_bx, _bt_y, _bt_w, "< PREV", _search != "", _mx, _my, _bt_h)) {
        scr_code_editor_do_search(-1);
    }
    _bx += _bt_w + _gap;

    // NEXT
    if (draw_btn(_bx, _bt_y, _bt_w, "NEXT >", _search != "", _mx, _my, _bt_h)) {
        scr_code_editor_do_search(1);
    }
    _bx += _bt_w + _gap;

    // REPLACE (current selection only)
    var _has_sel = (code_editor_sel_start != -1 && code_editor_sel_start != code_editor_sel_end);
    var _sel_matches = false;
    if (_has_sel && _search != "") {
        var _lo = min(code_editor_sel_start, code_editor_sel_end);
        var _hi = max(code_editor_sel_start, code_editor_sel_end);
        _sel_matches = (string_copy(code_editor_text, _lo + 1, _hi - _lo) == _search);
    }
    if (draw_btn(_bx, _bt_y, _bt_w, "REPLACE", _sel_matches, _mx, _my, _bt_h)) {
        if (_sel_matches) {
            var _lo = min(code_editor_sel_start, code_editor_sel_end);
            var _hi = max(code_editor_sel_start, code_editor_sel_end);
            scr_code_editor_push_undo();
            code_editor_text      = string_delete(code_editor_text, _lo + 1, _hi - _lo);
            code_editor_text      = string_insert(code_editor_replace_text, code_editor_text, _lo + 1);
            code_editor_cursor    = _lo + string_length(code_editor_replace_text);
            code_editor_sel_start = -1;
            code_editor_sel_end   = -1;
            code_editor_symbol_cache_dirty = true;
        }
    }
    _bx += _bt_w + _gap;

    // REPLACE ALL
    if (draw_btn(_bx, _bt_y, _bt_w, "ALL", _search != "", _mx, _my, _bt_h)) {
        scr_code_editor_push_undo();
        code_editor_text = string_replace_all(code_editor_text, _search, code_editor_replace_text);
        code_editor_symbol_cache_dirty = true;
        code_editor_cache_dirty        = true;
    }
    _bx += _bt_w + _gap;

    // CLEAR
    if (draw_btn(_bx, _bt_y, _bt_w, "CLEAR", true, _mx, _my, _bt_h)) {
        code_editor_find_text    = "";
        code_editor_replace_text = "";
        code_editor_sel_start    = -1;
        code_editor_sel_end      = -1;
    }
    _bx += _bt_w + _gap;

    // CLOSE
    if (draw_btn(_bx, _bt_y, _bt_w, "CLOSE", true, _mx, _my, _bt_h)) {
        code_editor_find_open         = false;
        code_editor_find_active_field = 0;
    }

    // Hint
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(70, 90, 80));
    draw_text(_dx + 8, _bt_y - 25, "TAB: switch field  |  ESC: close  |  ENTER: next");
}