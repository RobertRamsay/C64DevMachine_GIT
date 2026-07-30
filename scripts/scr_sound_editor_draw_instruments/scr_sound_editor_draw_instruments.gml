/// @function scr_sound_editor_draw_instruments(_m, _ix0, _iy0, _mx, _my)
/// @desc Draws and handles the INSTRUMENTS panel — id/name list with
///       ADD/REMOVE/COPY/PASTE, and an inline multi-line text editor for the
///       selected instrument's mini-language source (see
///       scr_instrument_parse). Recompiles on commit only (click-away or
///       Ctrl+Enter), never on every keystroke, so a mid-typo string never
///       corrupts instr.compiled.
function scr_sound_editor_draw_instruments(_m, _ix0, _iy0, _mx, _my) {

    var _list_row_h = 22;
    var _list_vis   = 6;
    var _list_w     = 260;

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text(_ix0, _iy0 - 20, "INSTRUMENTS");

    // ── LIST BOX ──
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_ix0 - 4, _iy0 - 2, _ix0 + _list_w + 4, _iy0 + _list_vis * _list_row_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_ix0 - 4, _iy0 - 2, _ix0 + _list_w + 4, _iy0 + _list_vis * _list_row_h + 2, true);

    _m.instr_list_scroll = clamp(_m.instr_list_scroll, 0, max(0, array_length(_m.instruments) - _list_vis));

    for (var _ilv = 0; _ilv < _list_vis; _ilv++) {
        var _ii = _ilv + _m.instr_list_scroll;
        if (_ii >= array_length(_m.instruments)) {
            break;
        }
        var _instr = _m.instruments[_ii];
        var _iry   = _iy0 + _ilv * _list_row_h;
        var _sel   = (_ii == _m.sel_instr);

        draw_set_color(_sel ? make_color_rgb(50, 70, 110) : ((_ii mod 2 == 0) ? make_color_rgb(20, 20, 32) : make_color_rgb(16, 16, 26)));
        draw_rectangle(_ix0, _iry, _ix0 + _list_w, _iry + _list_row_h, false);

        draw_set_color(make_color_rgb(120, 120, 160));
        var _id_str = string(_ii);
        while (string_length(_id_str) < 2) { _id_str = "0" + _id_str; }
        draw_text(_ix0 + 6, _iry + 4, _id_str);

        draw_set_color(_sel ? c_white : make_color_rgb(180, 180, 200));
        draw_text(_ix0 + 36, _iry + 4, _instr.name);

        var _row_hov = point_in_rectangle(_mx, _my, _ix0, _iry, _ix0 + _list_w, _iry + _list_row_h);
        if (_row_hov && mouse_check_button_pressed(mb_left)) {
            var _instr_dbl = (_m.instr_last_click_idx == _ii
                           && (current_time - _m.instr_last_click_time) < 350);
            _m.instr_last_click_time = current_time;
            _m.instr_last_click_idx  = _ii;

            if (_m.sel_instr != _ii) {
                _m.instr_edit_active      = false;
                _m.instr_name_edit_active = false;
            }
            _m.sel_instr = _ii;

            if (_instr_dbl) {
                _m.instr_name_edit_active      = true;
                _m.instr_name_edit_buf         = _instr.name;
                _m.instr_name_edit_cursor      = string_length(_instr.name);
                _m.instr_edit_active           = false;
                _m.instr_name_edit_opened_time = current_time;
            }
        }
    }

    if (point_in_rectangle(_mx, _my, _ix0 - 4, _iy0 - 2, _ix0 + _list_w + 4, _iy0 + _list_vis * _list_row_h + 2)) {
        if (mouse_wheel_up())   { _m.instr_list_scroll = max(0, _m.instr_list_scroll - 1); }
        if (mouse_wheel_down()) { _m.instr_list_scroll = min(max(0, array_length(_m.instruments) - _list_vis), _m.instr_list_scroll + 1); }
    }

    // ── ADD / REMOVE / COPY / PASTE ──
    var _iby   = _iy0 + _list_vis * _list_row_h + 10;
    var _btn_h = 18;
    var _btns  = ["+ ADD", "- REMOVE", "COPY", "PASTE"];
    var _bx    = _ix0;
    for (var _bi = 0; _bi < array_length(_btns); _bi++) {
        var _this_w = (_btns[_bi] == "- REMOVE") ? 90 : 60;
        var _locked = (_btns[_bi] == "- REMOVE" && _m.sel_instr < 0)
                   || (_btns[_bi] == "COPY"     && _m.sel_instr < 0)
                   || (_btns[_bi] == "PASTE"    && !variable_global_exists("se_instr_clipboard"));
        var _hov = !_locked && point_in_rectangle(_mx, _my, _bx, _iby, _bx + _this_w, _iby + _btn_h);
        var _base_col = make_color_rgb(30, 70, 100);
        if (_btns[_bi] == "+ ADD") {
            _base_col = make_color_rgb(20, 100, 40);
	        } else if (_btns[_bi] == "- REMOVE") {
	            _base_col = make_color_rgb(100, 30, 30);
	        }
        draw_set_color(_locked ? make_color_rgb(45, 45, 55) : (_hov ? make_color_rgb(80, 140, 200) : _base_col));
        draw_rectangle(_bx, _iby, _bx + _this_w, _iby + _btn_h, false);
        draw_set_color(_locked ? make_color_rgb(90, 90, 100) : c_white);
        draw_set_halign(fa_center);
        draw_text(_bx + _this_w * 0.5, _iby + 4, _btns[_bi]);
        draw_set_halign(fa_left);

        if (!_locked && _hov && mouse_check_button_pressed(mb_left)) {
            if (_btns[_bi] == "+ ADD") {
                var _new_idx_str = string(array_length(_m.instruments));
                while (string_length(_new_idx_str) < 2) { _new_idx_str = "0" + _new_idx_str; }
                var _new_text = "$21\nN\nD8\n---";
                array_push(_m.instruments, {
                    name     : "INSTR " + _new_idx_str,
                    text     : _new_text,
                    compiled : scr_instrument_parse(_new_text),
                    ins_name : "",
                    dirty    : false,
                    attack   : 0,
                    decay    : 8,
                    sustain  : 8,
                    release  : 0,
                    pulse_width : 2048
                });
                _m.sel_instr = array_length(_m.instruments) - 1;
                global.undo_dirty      = true;
                global.addresses_dirty = true;

            } else if (_btns[_bi] == "- REMOVE") {
                var _rm_idx = _m.sel_instr;
                array_delete(_m.instruments, _rm_idx, 1);
                for (var _pri = 0; _pri < array_length(_m.patterns); _pri++) {
                    var _rm_pat = _m.patterns[_pri];
                    for (var _rsi = 0; _rsi < array_length(_rm_pat.steps); _rsi++) {
                        var _rm_step = _rm_pat.steps[_rsi];
                        if (_rm_step.instr_idx == _rm_idx) {
                            _rm_step.instr_idx = -1;
                        } else if (_rm_step.instr_idx > _rm_idx) {
                            _rm_step.instr_idx -= 1;
                        }
                    }
                }
                _m.sel_instr = clamp(_rm_idx - 1, -1, array_length(_m.instruments) - 1);
                _m.instr_edit_active      = false;
                _m.instr_name_edit_active = false;
                global.undo_dirty      = true;
                global.addresses_dirty = true;

            } else if (_btns[_bi] == "COPY") {
                var _cp_src = _m.instruments[_m.sel_instr];
                global.se_instr_clipboard = {
                    name: _cp_src.name, text: _cp_src.text,
                    attack: _cp_src.attack, decay: _cp_src.decay,
                    sustain: _cp_src.sustain, release: _cp_src.release,
                    pulse_width: _cp_src.pulse_width
                };
                _m.warn_msg   = "COPIED INSTRUMENT";
                _m.warn_timer = game_get_speed(gamespeed_fps) * 2;

            } else if (_btns[_bi] == "PASTE") {
                var _pc = global.se_instr_clipboard;
                array_push(_m.instruments, {
                    name     : _pc.name + " COPY",
                    text     : _pc.text,
                    compiled : scr_instrument_parse(_pc.text),
                    ins_name : "",
                    dirty    : false,
                    attack   : _pc.attack,
                    decay    : _pc.decay,
                    sustain  : _pc.sustain,
                    release  : _pc.release,
                    pulse_width : _pc.pulse_width
                });
                _m.sel_instr = array_length(_m.instruments) - 1;
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }
        }
        _bx += _this_w + 6;
    }

    // ── SELECTED INSTRUMENT: NAME + SOURCE TEXT ──
    if (_m.sel_instr < 0 || _m.sel_instr >= array_length(_m.instruments)) {
        draw_set_color(c_white);
        return;
    }
    var _sel_instr = _m.instruments[_m.sel_instr];
    var _dy        = _iby + _btn_h + 20;

    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text(_ix0, _dy, "NAME:");
    var _nm_x1  = _ix0 + 50;
    var _nm_x2  = _nm_x1 + 180;
    var _nm_hov = point_in_rectangle(_mx, _my, _nm_x1, _dy - 2, _nm_x2, _dy + 16);

    if (_m.instr_name_edit_active) {
        var _nm_blink = (current_time mod 600) < 300;
        var _nm_disp  = _nm_blink ? string_insert("|", _m.instr_name_edit_buf, _m.instr_name_edit_cursor + 1) : _m.instr_name_edit_buf;
        draw_set_color(c_lime);
        draw_text(_nm_x1, _dy, _nm_disp);
    } else {
        draw_set_color(_nm_hov ? c_aqua : c_white);
        draw_text(_nm_x1, _dy, _sel_instr.name);
        if (_nm_hov && mouse_check_button_pressed(mb_left)) {
            _m.instr_name_edit_active      = true;
            _m.instr_name_edit_buf         = _sel_instr.name;
            _m.instr_name_edit_cursor      = string_length(_sel_instr.name);
            _m.instr_edit_active           = false;
            _m.instr_name_edit_opened_time = current_time;
        }
    }

    if (_m.instr_name_edit_active && !_nm_hov && mouse_check_button_pressed(mb_left)
    &&  current_time > _m.instr_name_edit_opened_time) {
        if (string_trim(_m.instr_name_edit_buf) != "") {
            _sel_instr.name   = string_trim(_m.instr_name_edit_buf);
            global.undo_dirty = true;
        }
        _m.instr_name_edit_active = false;
    }

    if (_m.instr_name_edit_active) {
        var _nm_ctrl = keyboard_check(vk_control) || scr_cmd_held();

        if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_escape)) {
            if (keyboard_check_pressed(vk_enter) && string_trim(_m.instr_name_edit_buf) != "") {
                _sel_instr.name   = string_trim(_m.instr_name_edit_buf);
                global.undo_dirty = true;
            }
            _m.instr_name_edit_active = false;
            keyboard_string = "";
        } else if (_nm_ctrl && (keyboard_check_pressed(vk_backspace) || keyboard_check_pressed(vk_delete))) {
            _m.instr_name_edit_buf    = "";
            _m.instr_name_edit_cursor = 0;
            keyboard_string = "";
        } else if (keyboard_check_pressed(vk_backspace) && _m.instr_name_edit_cursor > 0) {
            _m.instr_name_edit_buf    = string_delete(_m.instr_name_edit_buf, _m.instr_name_edit_cursor, 1);
            _m.instr_name_edit_cursor -= 1;
        } else if (keyboard_string != "") {
            var _nm_added = scr_strip_key_ghosts(keyboard_string);
            if (_nm_added != "" && string_length(_m.instr_name_edit_buf) < 24) {
                _m.instr_name_edit_buf    = string_insert(_nm_added, _m.instr_name_edit_buf, _m.instr_name_edit_cursor + 1);
                _m.instr_name_edit_cursor += string_length(_nm_added);
            }
            keyboard_string = "";
        }
    }

    // ── ADSR ──
    var _adsr_y   = _dy + 24;
    var _adsr_lbl = ["A", "D", "S", "R"];
    var _adsr_key = ["attack", "decay", "sustain", "release"];
    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text(_ix0, _adsr_y, "ADSR:");
    var _adsr_x = _ix0 + 50;
    for (var _adi = 0; _adi < 4; _adi++) {
        var _ad_val = _sel_instr[$ _adsr_key[_adi]];

        draw_set_color(make_color_rgb(180, 180, 200));
        draw_text(_adsr_x, _adsr_y, _adsr_lbl[_adi] + ":");

        var _ad_dnx1 = _adsr_x + 16;
        var _ad_dnx2 = _ad_dnx1 + 14;
        var _ad_hov_dn = point_in_rectangle(_mx, _my, _ad_dnx1, _adsr_y - 2, _ad_dnx2, _adsr_y + 14);
        draw_set_color(_ad_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text(_ad_dnx1 + 2, _adsr_y, "-");
        if (_ad_hov_dn && mouse_check_button_pressed(mb_left)) {
            _sel_instr[$ _adsr_key[_adi]] = max(0, _ad_val - 1);
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }

        draw_set_color(c_white);
        var _ad_str = string(_ad_val);
        while (string_length(_ad_str) < 2) { _ad_str = "0" + _ad_str; }
        draw_text(_ad_dnx2 + 4, _adsr_y, _ad_str);

        var _ad_upx1 = _ad_dnx2 + 26;
        var _ad_upx2 = _ad_upx1 + 14;
        var _ad_hov_up = point_in_rectangle(_mx, _my, _ad_upx1, _adsr_y - 2, _ad_upx2, _adsr_y + 14);
        draw_set_color(_ad_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text(_ad_upx1 + 2, _adsr_y, "+");
        if (_ad_hov_up && mouse_check_button_pressed(mb_left)) {
            _sel_instr[$ _adsr_key[_adi]] = min(15, _ad_val + 1);
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }

        _adsr_x = _ad_upx2 + 16;
    }

    // ── PULSE WIDTH ──
    var _pw_y = _adsr_y + 24;
    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text(_ix0, _pw_y, "PULSE:");

    var _pw_val = _sel_instr.pulse_width;

    var _pw_dnx1 = _ix0 + 50;
    var _pw_dnx2 = _pw_dnx1 + 14;
    var _pw_hov_dn = point_in_rectangle(_mx, _my, _pw_dnx1, _pw_y - 2, _pw_dnx2, _pw_y + 14);
    draw_set_color(_pw_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
    draw_text(_pw_dnx1 + 2, _pw_y, "-");
    if (_pw_hov_dn && mouse_check_button_pressed(mb_left)) {
        var _step = keyboard_check(vk_shift) ? 16 : 128;
        _sel_instr.pulse_width = max(0, _pw_val - _step);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_color(c_white);
    var _pw_str = string(_pw_val);
    while (string_length(_pw_str) < 4) { _pw_str = "0" + _pw_str; }
    draw_text(_pw_dnx2 + 4, _pw_y, _pw_str);

    var _pw_upx1 = _pw_dnx2 + 42;
    var _pw_upx2 = _pw_upx1 + 14;
    var _pw_hov_up = point_in_rectangle(_mx, _my, _pw_upx1, _pw_y - 2, _pw_upx2, _pw_y + 14);
    draw_set_color(_pw_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
    draw_text(_pw_upx1 + 2, _pw_y, "+");
    if (_pw_hov_up && mouse_check_button_pressed(mb_left)) {
        var _step = keyboard_check(vk_shift) ? 16 : 128;
        _sel_instr.pulse_width = min(4095, _pw_val + _step);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_color(make_color_rgb(110, 110, 130));
    draw_set_font(fnt_c64_pico);
    draw_text(_pw_upx2 + 8, _pw_y + 2, "(SHIFT: FINE)");
    draw_set_font(fnt_c64_tiny);

    // ── SOURCE TEXT BOX ──
    var _tb_y1 = _pw_y + 24;
    var _tb_h  = 340;
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_ix0 - 4, _tb_y1 - 2, _ix0 + _list_w + 4, _tb_y1 + _tb_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_ix0 - 4, _tb_y1 - 2, _ix0 + _list_w + 4, _tb_y1 + _tb_h + 2, true);

    var _tb_hov = point_in_rectangle(_mx, _my, _ix0 - 4, _tb_y1 - 2, _ix0 + _list_w + 4, _tb_y1 + _tb_h + 2);
    if (!_tb_hov && mouse_check_button_pressed(mb_left) && _m.instr_edit_active) {
        scr_sound_editor_commit_instrument(_m, _sel_instr);
    }
    if (_tb_hov && mouse_check_button_pressed(mb_left)) {
        if (!_m.instr_edit_active) {
            _m.instr_edit_active      = true;
            _m.instr_edit_buf         = _sel_instr.text;
            _m.instr_edit_cursor      = string_length(_m.instr_edit_buf);
            _m.instr_name_edit_active = false;
        } else {
            // ── CLICK-TO-POSITION — clicking an already-open box moves the
            // cursor to the clicked line/column instead of doing nothing.
            // The step-number gutter's width is subtracted out first, since
            // it's drawn but isn't part of the actual buffer content. ──
            var _cl_lines = string_split(_m.instr_edit_buf, "\n");
            var _click_line = clamp(floor((_my - _tb_y1 - 4) / 16), 0, array_length(_cl_lines) - 1);
            var _cl_prefix = string(_click_line);
            while (string_length(_cl_prefix) < 2) { _cl_prefix = "0" + _cl_prefix; }
            _cl_prefix += ": ";
            var _cl_prefix_w  = string_width(_cl_prefix);
            var _cl_line_txt  = _cl_lines[_click_line];
            var _cl_best_col  = string_length(_cl_line_txt);
            for (var _cci = 0; _cci <= string_length(_cl_line_txt); _cci++) {
                var _cl_sub_w = string_width(string_copy(_cl_line_txt, 1, _cci));
                if (_ix0 + 4 + _cl_prefix_w + _cl_sub_w >= _mx) {
                    _cl_best_col = _cci;
                    break;
                }
            }
            var _cl_flat = 0;
            for (var _fli = 0; _fli < _click_line; _fli++) {
                _cl_flat += string_length(_cl_lines[_fli]) + 1;
            }
            _m.instr_edit_cursor = _cl_flat + _cl_best_col;
        }
    }

    var _tb_disp  = _m.instr_edit_active ? _m.instr_edit_buf : _sel_instr.text;
    var _tb_lines = string_split(_tb_disp, "\n");

    // ── CURSOR POSITION — convert the flat cursor offset into a line/column
    // so the blinking "|" lands where you're actually typing, not just at
    // the end of the buffer. ──
    var _tb_cursor_line = 0;
    var _tb_cursor_col  = 0;
    if (_m.instr_edit_active) {
        var _tb_running = 0;
        for (var _tci = 0; _tci < array_length(_tb_lines); _tci++) {
            var _tb_line_len = string_length(_tb_lines[_tci]);
            if (_m.instr_edit_cursor <= _tb_running + _tb_line_len) {
                _tb_cursor_line = _tci;
                _tb_cursor_col  = _m.instr_edit_cursor - _tb_running;
                break;
            }
            _tb_running += _tb_line_len + 1;
        }
    }

    // ── STEP-NUMBER GUTTER, DIVIDER LINE, & AUTOMATED SIDE COMMENTS ──
    var _tb_blink = (current_time mod 600) < 300;
    
    // Draw a clean vertical divider line inside the box (moved slightly left)
    draw_set_color(make_color_rgb(45, 45, 65));
    draw_line(_ix0 + 72, _tb_y1 + 2, _ix0 + 72, _tb_y1 + _tb_h - 2);

    for (var _tli = 0; _tli < array_length(_tb_lines); _tli++) {
        var _tb_prefix = string(_tli);
        while (string_length(_tb_prefix) < 2) { _tb_prefix = "0" + _tb_prefix; }
        _tb_prefix += ": ";
        var _tb_prefix_w = string_width(_tb_prefix);

        draw_set_color(make_color_rgb(90, 90, 120));
        draw_text(_ix0 + 4, _tb_y1 + 4 + _tli * 16, _tb_prefix);

        var _tb_line_txt = _tb_lines[_tli];
        if (_m.instr_edit_active && _tb_blink && _tli == _tb_cursor_line) {
            _tb_line_txt = string_insert("|", _tb_line_txt, _tb_cursor_col + 1);
        }
        draw_set_color(_m.instr_edit_active ? c_lime : make_color_rgb(160, 160, 180));
        draw_text(_ix0 + 4 + _tb_prefix_w, _tb_y1 + 4 + _tli * 16, _tb_line_txt);

        // Generate automated side-notes with detailed SID register decoding when not editing
        if (!_m.instr_edit_active) {
            var _raw_tok = string_trim(_tb_lines[_tli]);
            var _up_tok  = string_upper(_raw_tok);
            var _comment = "";

            if (_raw_tok != "") {
                var _c0 = string_char_at(_up_tok, 1);
                
                // Check for End / Dashes
                var _all_dash = true;
                for (var _di = 1; _di <= string_length(_up_tok); _di++) {
                    if (string_char_at(_up_tok, _di) != "-") { _all_dash = false; break; }
                }

                if (_all_dash) {
                    _comment = "; gate off + stop";
                } else if (_c0 == "N") {
                    var _rest = string_delete(_up_tok, 1, 1);
                    if (_rest == "" || _rest == "+0") {
                        _comment = "; note reset";
                    } else {
                        _comment = "; note offset " + _rest;
                    }
                } else if (_c0 == "D") {
                    _comment = "; hold " + string_delete(_up_tok, 1, 1) + " ticks";
                } else if (_c0 == "L") {
                    _comment = "; loop to step " + string_delete(_up_tok, 1, 1);
                } else {
                    // Waveform / Control byte hex decoding
                    var _hexstr = _up_tok;
                    if (string_char_at(_hexstr, 1) == "$") { _hexstr = string_delete(_hexstr, 1, 1); }
                    var _is_hex = (string_length(_hexstr) > 0);
                    for (var _hi = 1; _hi <= string_length(_hexstr); _hi++) {
                        if (string_pos(string_char_at(_hexstr, _hi), "0123456789ABCDEF") == 0) { _is_hex = false; break; }
                    }
                    
                    if (_is_hex) {
                        var _val = real(hex_to_decimal(_hexstr));
                        var _wf_parts = [];
                        
                        // Extract waveforms (bits 4-7)
                        if (_val & 0x80) array_push(_wf_parts, "Noise");
                        if (_val & 0x40) array_push(_wf_parts, "Pulse");
                        if (_val & 0x20) array_push(_wf_parts, "Saw");
                        if (_val & 0x10) array_push(_wf_parts, "Triangle");
                        
                        var _wf_str = (array_length(_wf_parts) > 0) ? string_join_ext("+", _wf_parts) : "No Wave";
                        
                        // Extract control bits (bits 0-3)
                        var _ctrl_parts = [];
                        if (_val & 0x01) array_push(_ctrl_parts, "Gate on");
                        if (_val & 0x02) array_push(_ctrl_parts, "Sync");
                        if (_val & 0x04) array_push(_ctrl_parts, "Ring mod");
                        if (_val & 0x08) array_push(_ctrl_parts, "Test");
						
						                        
                        _comment = "; " + _wf_str;
                        if (array_length(_ctrl_parts) > 0) {
                            _comment += ", " + string_join_ext(", ", _ctrl_parts);
                        }
                  }
                }
            }

            if (_comment != "") {
                draw_set_color(make_color_rgb(90, 110, 90));
                draw_text(_ix0 + 80, _tb_y1 + 4 + _tli * 16, _comment);
            }
        }
    }

    if (_m.instr_edit_active) {
        if (keyboard_check_pressed(vk_escape)) {
            _m.instr_edit_active = false;
            keyboard_string = "";
        } else if ((keyboard_check(vk_control) || scr_cmd_held()) && keyboard_check_pressed(vk_enter)) {
            scr_sound_editor_commit_instrument(_m, _sel_instr);
            keyboard_string = "";
        } else if (keyboard_check_pressed(vk_enter)) {
            _m.instr_edit_buf    = string_insert("\n", _m.instr_edit_buf, _m.instr_edit_cursor + 1);
            _m.instr_edit_cursor += 1;
        } else if (keyboard_check_pressed(vk_backspace) && _m.instr_edit_cursor > 0) {
            _m.instr_edit_buf    = string_delete(_m.instr_edit_buf, _m.instr_edit_cursor, 1);
            _m.instr_edit_cursor -= 1;
        } else if (keyboard_check_pressed(vk_delete) && _m.instr_edit_cursor < string_length(_m.instr_edit_buf)) {
            _m.instr_edit_buf = string_delete(_m.instr_edit_buf, _m.instr_edit_cursor + 1, 1);
        } else if (keyboard_check_pressed(vk_left)) {
            _m.instr_edit_cursor = max(0, _m.instr_edit_cursor - 1);
        } else if (keyboard_check_pressed(vk_right)) {
            _m.instr_edit_cursor = min(string_length(_m.instr_edit_buf), _m.instr_edit_cursor + 1);
        } else if (keyboard_check_pressed(vk_up) && _tb_cursor_line > 0) {
            var _tb_up_line = _tb_lines[_tb_cursor_line - 1];
            var _tb_up_col  = min(_tb_cursor_col, string_length(_tb_up_line));
            _m.instr_edit_cursor -= (_tb_cursor_col + 1 + (string_length(_tb_up_line) - _tb_up_col));
        } else if (keyboard_check_pressed(vk_down) && _tb_cursor_line < array_length(_tb_lines) - 1) {
            var _tb_cur_line  = _tb_lines[_tb_cursor_line];
            var _tb_down_line = _tb_lines[_tb_cursor_line + 1];
            var _tb_down_col  = min(_tb_cursor_col, string_length(_tb_down_line));
            _m.instr_edit_cursor += (string_length(_tb_cur_line) - _tb_cursor_col + 1 + _tb_down_col);
        } else if (keyboard_check_pressed(vk_home)) {
            _m.instr_edit_cursor -= _tb_cursor_col;
        } else if (keyboard_check_pressed(vk_end)) {
            _m.instr_edit_cursor += (string_length(_tb_lines[_tb_cursor_line]) - _tb_cursor_col);
        } else if (keyboard_string != "") {
            var _tb_added = scr_strip_key_ghosts(keyboard_string);
            if (_tb_added != "" && string_length(_m.instr_edit_buf) < 2000) {
                _m.instr_edit_buf    = string_insert(_tb_added, _m.instr_edit_buf, _m.instr_edit_cursor + 1);
                _m.instr_edit_cursor += string_length(_tb_added);
            }
            keyboard_string = "";
        }
    }

    // ── COMPILED PREVIEW / ERRORS ──
    var _pv_y = _tb_y1 + _tb_h + 16;
    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text(_ix0, _pv_y, "COMPILED: " + string(array_length(_sel_instr.compiled.bytes)) + " BYTES");
    var _err_n = array_length(_sel_instr.compiled.errors);
    if (_err_n > 0) {
        draw_set_font(fnt_c64_pico);
        draw_set_color(c_red);
        for (var _eri = 0; _eri < _err_n; _eri++) {
            draw_text(_ix0, _pv_y + 18 + _eri * 12, _sel_instr.compiled.errors[_eri]);
        }
        draw_set_font(fnt_c64_tiny);
    }

    // ── COMMAND LEGEND ──
    var _lg_y = _pv_y + 32 + (_err_n * 12) + 10;
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(110, 110, 130));
    draw_text(_ix0, _lg_y,      "$xx / xx   WAVEFORM / CONTROL BYTE (HEX)");
    draw_text(_ix0, _lg_y + 12, "N, N+n, N-n   NOTE, OPTIONAL SEMITONE OFFSET");
    draw_text(_ix0, _lg_y + 24, "Dn   HOLD FOR n TICKS (1-255)");
    draw_text(_ix0, _lg_y + 36, "Ln   LOOP BACK TO STEP n");
    draw_text(_ix0, _lg_y + 48, "---   END (GATE OFF + STOP)");
    draw_set_font(fnt_c64_tiny);

    draw_set_color(c_white);
}