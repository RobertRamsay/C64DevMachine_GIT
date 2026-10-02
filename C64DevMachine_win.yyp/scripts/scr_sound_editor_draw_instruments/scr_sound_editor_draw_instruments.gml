/// @function scr_sound_editor_draw_instruments(_m, _ix0, _iy0, _mx, _my)
/// @desc Draws and handles the INSTRUMENTS panel — id/name list with
///       ADD/REMOVE/COPY/PASTE, and an inline multi-line text editor for the
///       selected instrument's mini-language source (see
///       scr_instrument_parse). Recompiles on commit only (click-away or
///       Ctrl+Enter), never on every keystroke, so a mid-typo string never
///       corrupts instr.compiled.
/// _ix1 / _iy1 (optional): the panel's right and bottom edges. When given, the
/// panel lays out in two columns — list, buttons, name, ADSR and pulse on the
/// left, the command box, compiled size and legend on the right — and sizes
/// itself to stay inside that rectangle. Omitted (SFX Maker) keeps the
/// original single-column layout.
function scr_sound_editor_draw_instruments(_m, _ix0, _iy0, _mx, _my, _ix1 = -1, _iy1 = -1) {

    var _follow = scr_sound_instrument_follow_read(_m);
    var _two_col    = (_ix1 > 0 && _iy1 > 0);
    var _list_row_h = 22;
    var _list_vis   = 6;
    var _list_w     = 260;
    if (_two_col) {
        // Everything under the list in the left column (buttons, name, two
        // ADSR rows, pulse, vibrato, filter) takes 182px; the list gets the rest.
        _list_w   = 290;
        _list_vis = clamp(floor((_iy1 - _iy0 - 182) / _list_row_h), 6, 20);
    }

    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text_l(_ix0, _iy0 - 20, "INSTRUMENTS");

    // Presets append independent instruments and never replace existing slots.
    if (_two_col) {
        if (!variable_struct_exists(_m, "preset_picker_open")) _m.preset_picker_open = false;
        if (scr_sfx_maker_button(_ix0 + 150, _iy0 - 24, 130,
                                _m.preset_picker_open ? "CLOSE PRESETS" : "+ PRESETS", _mx, _my)) {
            if (_m.instr_edit_active && _m.sel_instr >= 0) {
                scr_sound_editor_commit_instrument(_m, _m.instruments[_m.sel_instr]);
            }
            _m.instr_name_edit_active = false;
            _m.preset_picker_open = !_m.preset_picker_open;
            keyboard_string = "";
        }
        if (_m.preset_picker_open) {
            scr_sound_editor_preset_picker(_m, _ix0, _iy0, _list_w, _list_vis, _mx, _my);
            return;
        }
    }

    // ── LIST BOX ──
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_ix0 - 4, _iy0 - 2, _ix0 + _list_w + 4, _iy0 + _list_vis * _list_row_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_ix0 - 4, _iy0 - 2, _ix0 + _list_w + 4, _iy0 + _list_vis * _list_row_h + 2, true);

    _m.instr_list_scroll = clamp(_m.instr_list_scroll, 0, max(0, array_length(_m.instruments) - _list_vis));

    _m.instr_list_scroll = scr_sound_editor_scrollbar(_m, "instr_list_drag", _m.instr_list_scroll,
        array_length(_m.instruments), _list_vis, _ix0 + _list_w - 12, _iy0, 12, _list_vis * _list_row_h, _mx, _my);

    for (var _ilv = 0; _ilv < _list_vis; _ilv++) {
        var _ii = _ilv + _m.instr_list_scroll;
        if (_ii >= array_length(_m.instruments)) {
            break;
        }
        var _instr = _m.instruments[_ii];
        var _iry   = _iy0 + _ilv * _list_row_h;
        var _sel   = (_ii == _m.sel_instr);
        var _sounding = false;
        for (var _fv = 0; _fv < array_length(_follow); _fv++) {
            if (is_struct(_follow[_fv]) && _follow[_fv].instr == _instr) { _sounding = true; break; }
        }

        draw_set_color(_sel ? make_color_rgb(50, 70, 110) : ((_ii mod 2 == 0) ? make_color_rgb(20, 20, 32) : make_color_rgb(16, 16, 26)));
        draw_rectangle(_ix0, _iry, _ix0 + _list_w - 14, _iry + _list_row_h, false);

        draw_set_color(make_color_rgb(120, 120, 160));
        var _id_str = string(_ii);
        while (string_length(_id_str) < 2) { _id_str = "0" + _id_str; }
        draw_text_l(_ix0 + 6, _iry + 4, _id_str);

        if (_sounding) {
            draw_set_color(c_lime);
            draw_rectangle(_ix0 + 1, _iry + 2, _ix0 + 3, _iry + _list_row_h - 2, false);
        }
        draw_set_color(_sounding ? c_lime : (_sel ? c_white : make_color_rgb(180, 180, 200)));
        var _list_name = _instr.name;
        while (string_length(_list_name) > 0 && string_width_l(_list_name) > _list_w - 54)
            _list_name = string_delete(_list_name, string_length(_list_name), 1);
        draw_text_l(_ix0 + 36, _iry + 4, _list_name);

        var _row_hov = point_in_rectangle(_mx, _my, _ix0, _iry, _ix0 + _list_w - 14, _iry + _list_row_h);
        if (_row_hov && mouse_check_button_pressed(mb_left)) {
            var _instr_dbl = (_m.instr_last_click_idx == _ii
                           && (current_time - _m.instr_last_click_time) < 350);
            _m.instr_last_click_time = current_time;
            _m.instr_last_click_idx  = _ii;

            if (_m.sel_instr != _ii) {
                if (_m.instr_edit_active && _m.sel_instr >= 0) scr_sound_editor_commit_instrument(_m, _m.instruments[_m.sel_instr]);
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
        if (variable_struct_exists(_m,"sfx_asset_name") && array_length(_m.instruments)>=64 && (_btns[_bi]=="+ ADD" || _btns[_bi]=="PASTE")) _locked=true;
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
        draw_text_l(_bx + _this_w * 0.5, _iby + 4, _btns[_bi]);
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
                    pulse_width : 2048,
                    vib_delay : 0,
                    vib_speed : 0,
                    vib_depth : 0,
                    filt : 0
                });
                _m.sel_instr = array_length(_m.instruments) - 1;
                global.undo_dirty      = true;
                global.addresses_dirty = true;

            } else if (_btns[_bi] == "- REMOVE") {
                var _rm_idx = _m.sel_instr;
                array_delete(_m.instruments, _rm_idx, 1);
                if(variable_struct_exists(_m,"sfx_asset_name")) {
                    var _sfx_asset_name=_m.sfx_asset_name;
                    with(obj_c64_node) if(node_type=="MACRO_SFX" && string(instructions[0][1])==_sfx_asset_name) {
                        var _old_index=real(instructions[0][2]);
                        if(_old_index==_rm_idx) instructions[0][2]=-1;
                        else if(_old_index>_rm_idx) instructions[0][2]=_old_index-1;
                    }
                }

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
                    pulse_width: _cp_src.pulse_width,
                    vib_delay: scr_sid64_instr_field(_cp_src, "vib_delay", 0),
                    vib_speed: scr_sid64_instr_field(_cp_src, "vib_speed", 0),
                    vib_depth: scr_sid64_instr_field(_cp_src, "vib_depth", 0),
                    filt: scr_sid64_instr_field(_cp_src, "filt", 0),
                    sfx_note: variable_struct_exists(_cp_src,"sfx_note")?_cp_src.sfx_note:"C-5",
                    sfx_priority: variable_struct_exists(_cp_src,"sfx_priority")?_cp_src.sfx_priority:1
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
                    pulse_width : _pc.pulse_width,
                    vib_delay : scr_sid64_instr_field(_pc, "vib_delay", 0),
                    vib_speed : scr_sid64_instr_field(_pc, "vib_speed", 0),
                    vib_depth : scr_sid64_instr_field(_pc, "vib_depth", 0),
                    filt : scr_sid64_instr_field(_pc, "filt", 0),
                    sfx_note: variable_struct_exists(_pc,"sfx_note")?_pc.sfx_note:"C-5",
                    sfx_priority: variable_struct_exists(_pc,"sfx_priority")?_pc.sfx_priority:1
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
    if (!_m.instr_edit_active && (!variable_struct_exists(_m, "instr_format_source") || _m.instr_format_source != _sel_instr.text)) {
        var _formatted = scr_instrument_format(_sel_instr.text);
        _m.instr_format_source = _formatted;
        if (_formatted != _sel_instr.text) {
            _sel_instr.text = _formatted;
            _sel_instr.compiled = scr_instrument_parse(_formatted);
            global.addresses_dirty = true;
        }
    }
    if (!variable_struct_exists(_m, "instr_text_scroll") || !variable_struct_exists(_m, "instr_scroll_sel") || _m.instr_scroll_sel != _m.sel_instr) {
        _m.instr_text_scroll = 0;
        _m.instr_scroll_sel = _m.sel_instr;
    }
    var _dy        = _iby + _btn_h + 20;

    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text_l(_ix0, _dy, "NAME:");
    var _nm_x1  = _ix0 + 50;
    var _nm_x2  = _nm_x1 + 180;
    var _nm_hov = point_in_rectangle(_mx, _my, _nm_x1, _dy - 2, _nm_x2, _dy + 16);

    if (_m.instr_name_edit_active) {
        var _nm_blink = (current_time mod 600) < 300;
        var _nm_disp  = _nm_blink ? string_insert("|", _m.instr_name_edit_buf, _m.instr_name_edit_cursor + 1) : _m.instr_name_edit_buf;
        draw_set_color(c_lime);
        draw_text_l(_nm_x1, _dy, _nm_disp);
    } else {
        draw_set_color(_nm_hov ? c_aqua : c_white);
        draw_text_l(_nm_x1, _dy, _sel_instr.name);
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
    draw_text_l(_ix0, _adsr_y, "ADSR:");
    var _adsr_x = _ix0 + 50;
    for (var _adi = 0; _adi < 4; _adi++) {
        var _ad_val = _sel_instr[$ _adsr_key[_adi]];

        draw_set_color(make_color_rgb(180, 180, 200));
        draw_text_l(_adsr_x, _adsr_y, _adsr_lbl[_adi] + ":");

        var _ad_dnx1 = _adsr_x + 16;
        var _ad_dnx2 = _ad_dnx1 + 14;
        var _ad_hov_dn = point_in_rectangle(_mx, _my, _ad_dnx1, _adsr_y - 2, _ad_dnx2, _adsr_y + 14);
        draw_set_color(_ad_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text_l(_ad_dnx1 + 2, _adsr_y, "-");
        if (_ad_hov_dn && mouse_check_button_pressed(mb_left)) {
            _sel_instr[$ _adsr_key[_adi]] = max(0, _ad_val - 1);
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }

        draw_set_color(c_white);
        var _ad_str = string(_ad_val);
        while (string_length(_ad_str) < 2) { _ad_str = "0" + _ad_str; }
        draw_text_l(_ad_dnx2 + 4, _adsr_y, _ad_str);

        var _ad_upx1 = _ad_dnx2 + 26;
        var _ad_upx2 = _ad_upx1 + 14;
        var _ad_hov_up = point_in_rectangle(_mx, _my, _ad_upx1, _adsr_y - 2, _ad_upx2, _adsr_y + 14);
        draw_set_color(_ad_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
        draw_text_l(_ad_upx1 + 2, _adsr_y, "+");
        if (_ad_hov_up && mouse_check_button_pressed(mb_left)) {
            _sel_instr[$ _adsr_key[_adi]] = min(15, _ad_val + 1);
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }

        _adsr_x = _ad_upx2 + 16;
        // Two-column layout: S and R wrap onto a second row so the left
        // column stays inside its own width.
        if (_two_col && _adi == 1) {
            _adsr_x = _ix0 + 50;
            _adsr_y += 22;
        }
    }

    // ── PULSE WIDTH ──
    var _pw_y = _adsr_y + 24;
    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text_l(_ix0, _pw_y, "PULSE:");

    var _pw_val = _sel_instr.pulse_width;

    var _pw_dnx1 = _ix0 + 50;
    var _pw_dnx2 = _pw_dnx1 + 14;
    var _pw_hov_dn = point_in_rectangle(_mx, _my, _pw_dnx1, _pw_y - 2, _pw_dnx2, _pw_y + 14);
    draw_set_color(_pw_hov_dn ? c_aqua : make_color_rgb(100, 100, 100));
    draw_text_l(_pw_dnx1 + 2, _pw_y, "-");
    if (_pw_hov_dn && mouse_check_button_pressed(mb_left)) {
        var _step = keyboard_check(vk_shift) ? 16 : 128;
        _sel_instr.pulse_width = max(0, _pw_val - _step);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_color(c_white);
    var _pw_str = string(_pw_val);
    while (string_length(_pw_str) < 4) { _pw_str = "0" + _pw_str; }
    draw_text_l(_pw_dnx2 + 4, _pw_y, _pw_str);

    var _pw_upx1 = _pw_dnx2 + 42;
    var _pw_upx2 = _pw_upx1 + 14;
    var _pw_hov_up = point_in_rectangle(_mx, _my, _pw_upx1, _pw_y - 2, _pw_upx2, _pw_y + 14);
    draw_set_color(_pw_hov_up ? c_aqua : make_color_rgb(100, 100, 100));
    draw_text_l(_pw_upx1 + 2, _pw_y, "+");
    if (_pw_hov_up && mouse_check_button_pressed(mb_left)) {
        var _step = keyboard_check(vk_shift) ? 16 : 128;
        _sel_instr.pulse_width = min(4095, _pw_val + _step);
        global.undo_dirty      = true;
        global.addresses_dirty = true;
    }

    draw_set_color(make_color_rgb(110, 110, 130));
    draw_set_font_l(fnt_c64_pico);
    draw_text_l(_pw_upx2 + 8, _pw_y + 2, "(SHIFT: FINE)");
    draw_set_font_l(fnt_c64_tiny);

    // ── VIBRATO (Music Maker only — the SFX player has no vibrato) ──
    // DL = frames before it starts, SP = frames per half-cycle, DP = depth.
    // A 4XY command in the pattern overrides it while active.
    if (_two_col) {
        var _vb_y = _pw_y + 24;
        draw_set_color(make_color_rgb(120, 120, 160));
        draw_text_l(_ix0, _vb_y, "VIB:");
        var _vb_lbl = ["DL", "SP", "DP"];
        var _vb_key = ["vib_delay", "vib_speed", "vib_depth"];
        var _vb_max = [255, 15, 15];
        var _vb_x   = _ix0 + 50;
        for (var _vbi = 0; _vbi < 3; _vbi++) {
            var _vb_val = scr_sid64_instr_field(_sel_instr, _vb_key[_vbi], 0);
            draw_set_color(make_color_rgb(180, 180, 200));
            draw_text_l(_vb_x, _vb_y, _vb_lbl[_vbi]);

            var _vb_dnx1 = _vb_x + 20;
            var _vb_dnx2 = _vb_dnx1 + 14;
            var _vb_hov_dn = point_in_rectangle(_mx, _my, _vb_dnx1, _vb_y - 2, _vb_dnx2, _vb_y + 14);
            draw_set_color(make_color_rgb(100, 100, 100));
            if (_vb_hov_dn) {
                draw_set_color(c_aqua);
            }
            draw_text_l(_vb_dnx1 + 2, _vb_y, "-");
            if (_vb_hov_dn && mouse_check_button_pressed(mb_left)) {
                var _vb_step_dn = 1;
                if (_vbi == 0 && keyboard_check(vk_shift)) {
                    _vb_step_dn = 10;
                }
                _sel_instr[$ _vb_key[_vbi]] = max(0, _vb_val - _vb_step_dn);
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }

            draw_set_color(c_white);
            var _vb_str = string(_vb_val);
            while (string_length(_vb_str) < 2) { _vb_str = "0" + _vb_str; }
            draw_text_l(_vb_dnx2 + 3, _vb_y, _vb_str);

            var _vb_upx1 = _vb_dnx2 + 26;
            var _vb_upx2 = _vb_upx1 + 14;
            var _vb_hov_up = point_in_rectangle(_mx, _my, _vb_upx1, _vb_y - 2, _vb_upx2, _vb_y + 14);
            draw_set_color(make_color_rgb(100, 100, 100));
            if (_vb_hov_up) {
                draw_set_color(c_aqua);
            }
            draw_text_l(_vb_upx1 + 2, _vb_y, "+");
            if (_vb_hov_up && mouse_check_button_pressed(mb_left)) {
                var _vb_step_up = 1;
                if (_vbi == 0 && keyboard_check(vk_shift)) {
                    _vb_step_up = 10;
                }
                _sel_instr[$ _vb_key[_vbi]] = min(_vb_max[_vbi], _vb_val + _vb_step_up);
                global.undo_dirty      = true;
                global.addresses_dirty = true;
            }
            _vb_x = _vb_upx2 + 8;
        }

        if (point_in_rectangle(_mx, _my, _ix0, _vb_y - 2, _vb_x, _vb_y + 16)) {
            _m.pattern_hover_tip = scr_sound_editor_vibrato_help();
        }

        // ── FILTER ON/OFF: route this instrument's voice through the song filter ──
        var _fi_y = _vb_y + 24;
        var _fi_on = (scr_sid64_instr_field(_sel_instr, "filt", 0) != 0);
        draw_set_color(make_color_rgb(120, 120, 160));
        draw_text_l(_ix0, _fi_y, "FILTER:");
        var _fi_bx = _ix0 + 64;
        var _fi_hov = point_in_rectangle(_mx, _my, _fi_bx, _fi_y - 2, _fi_bx + 40, _fi_y + 14);
        if (_fi_on) {
            draw_set_color(make_color_rgb(40, 110, 170));
        } else if (_fi_hov) {
            draw_set_color(make_color_rgb(65, 80, 100));
        } else {
            draw_set_color(make_color_rgb(30, 38, 52));
        }
        draw_rectangle(_fi_bx, _fi_y - 2, _fi_bx + 40, _fi_y + 14, false);
        draw_set_color(c_white);
        if (_fi_on) {
            draw_text_l(_fi_bx + 8, _fi_y, "ON");
        } else {
            draw_text_l(_fi_bx + 6, _fi_y, "OFF");
        }
        if (_fi_hov && mouse_check_button_pressed(mb_left)) {
            if (_fi_on) {
                _sel_instr.filt = 0;
            } else {
                _sel_instr.filt = 1;
            }
            global.undo_dirty      = true;
            global.addresses_dirty = true;
        }
        // Routed through a filter with no mode set = silence on the SID.
        if (_fi_on && (_m.filt_mode & 0x07) == 0) {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text_l(_fi_bx + 50, _fi_y, "SET A FILTER MODE - SILENT");
        }
    }

    // ── SOURCE TEXT BOX ──
    var _wave_click = false;   // the command dropdowns / help used this frame's click
    var _tb_x0 = _ix0;
    var _tb_w  = _list_w;
    var _tb_y1 = _pw_y + 24;
    var _tb_h  = 340;
    if (_two_col) {
        // Right column: header, box down to the compiled/legend block.
        _tb_x0 = _ix0 + _list_w + 20;
        _tb_w  = _ix1 - _tb_x0 - 4;
        _tb_y1 = _iy0;
        _tb_h  = _iy1 - _iy0 - 160;   // room for compiled size, 3 error lines, legend
        // WAVE / NOTE / HOLD / LOOP / END dropdowns + ? help, on the header row
        // (the COMMANDS title makes way for them).
        _wave_click = scr_sound_editor_cmd_bar(_m, _sel_instr, _tb_x0, _tb_x0 + _tb_w + 4, _iy0 - 22,
                                               _tb_x0 - 4, _tb_y1 - 2, _tb_x0 + _tb_w + 4, _tb_y1 + _tb_h + 2, _mx, _my, false);
    }
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_tb_x0 - 4, _tb_y1 - 2, _tb_x0 + _tb_w + 4, _tb_y1 + _tb_h + 2, false);
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_rectangle(_tb_x0 - 4, _tb_y1 - 2, _tb_x0 + _tb_w + 4, _tb_y1 + _tb_h + 2, true);

    var _tb_hov = point_in_rectangle(_mx, _my, _tb_x0 - 4, _tb_y1 - 2, _tb_x0 + _tb_w + 4, _tb_y1 + _tb_h + 2);
    if (!_tb_hov && mouse_check_button_pressed(mb_left) && _m.instr_edit_active && !_wave_click) {
        scr_sound_editor_commit_instrument(_m, _sel_instr);
    }
    var _visible_lines = max(1, floor((_tb_h - 18) / 16));
    var _source_lines = string_split(_m.instr_edit_active ? _m.instr_edit_buf : _sel_instr.text, "\n");
    if (_tb_hov) {
        if (mouse_wheel_up()) _m.instr_text_scroll -= 3;
        if (mouse_wheel_down()) _m.instr_text_scroll += 3;
    }
    _m.instr_text_scroll = clamp(_m.instr_text_scroll, 0, max(0, array_length(_source_lines) - _visible_lines));
    _m.instr_text_scroll = scr_sound_editor_scrollbar(_m, "instr_text_drag", _m.instr_text_scroll,
        array_length(_source_lines), _visible_lines, _tb_x0 + _tb_w - 12, _tb_y1, 12, _tb_h, _mx, _my);
    var _tb_content_hov = _tb_hov && _mx < _tb_x0 + _tb_w - 14;

    // ── DIVIDER ── between the code column and the notes column; drag it.
    var _div = clamp(_m.instr_div, 80, max(80, _tb_w - 100));
    var _div_x = _tb_x0 + _div;
    var _div_hov = point_in_rectangle(_mx, _my, _div_x - 4, _tb_y1, _div_x + 4, _tb_y1 + _tb_h);
    if (_div_hov && mouse_check_button_pressed(mb_left) && !_wave_click) {
        _m.instr_div_drag = true;
    }
    if (_m.instr_div_drag) {
        if (mouse_check_button(mb_left)) {
            _m.instr_div = clamp(_mx - _tb_x0, 80, max(80, _tb_w - 100));
            _div = _m.instr_div;
            _div_x = _tb_x0 + _div;
        } else {
            _m.instr_div_drag = false;
            global.undo_dirty = true;   // saved with the song (instr_div)
        }
    }
    // Notes column: x range, and the horizontal scrollbar under it.
    var _nt_x0 = _div_x + 8;
    var _nt_x1 = _tb_x0 + _tb_w - 16;
    var _nt_w  = max(20, _nt_x1 - _nt_x0);
    var _hs_y  = _tb_y1 + _tb_h - 11;
    var _in_notes = _tb_content_hov && _mx > _div_x + 4 && _my < _hs_y - 2;
    var _in_code  = _tb_content_hov && _mx < _div_x - 4;
    var _in_hbar  = point_in_rectangle(_mx, _my, _div_x + 4, _hs_y, _nt_x1, _tb_y1 + _tb_h);
    var _box_busy = _div_hov || _m.instr_div_drag || _in_hbar || _m.instr_note_hdrag >= 0;

    // ── NOTE EDITING ── a line's note is generated from its command; typing
    // over it stores an override for that command text (instr.note_overrides,
    // saved with the instrument). Enter keeps it, an empty note goes back to
    // the generated one, Esc cancels.
    if (_m.instr_note_edit_active) {
        var _ne_done = false;
        var _ne_keep = false;
        if (keyboard_check_pressed(vk_enter)) {
            _ne_done = true;
            _ne_keep = true;
        } else if (keyboard_check_pressed(vk_escape)) {
            _ne_done = true;
            keyboard_clear(vk_escape);
        } else if (mouse_check_button_pressed(mb_left) && !_in_notes) {
            _ne_done = true;
            _ne_keep = true;
        } else {
            if (keyboard_check_pressed(vk_backspace) && string_length(_m.instr_note_edit_buf) > 0) {
                _m.instr_note_edit_buf = string_delete(_m.instr_note_edit_buf, string_length(_m.instr_note_edit_buf), 1);
            }
            if (keyboard_string != "") {
                var _ne_add = scr_strip_key_ghosts(keyboard_string);
                if (string_length(_m.instr_note_edit_buf) + string_length(_ne_add) <= 120) {
                    _m.instr_note_edit_buf += _ne_add;
                }
            }
        }
        keyboard_string = "";
        if (_ne_done) {
            if (_ne_keep) {
                var _ovr = _sel_instr[$ "note_overrides"];
                if (is_undefined(_ovr)) {
                    _ovr = {};
                    _sel_instr.note_overrides = _ovr;
                }
                if (string_trim(_m.instr_note_edit_buf) == "") {
                    variable_struct_remove(_ovr, _m.instr_note_edit_key);   // back to the generated note
                } else {
                    _ovr[$ _m.instr_note_edit_key] = _m.instr_note_edit_buf;
                }
                global.undo_dirty = true;
            }
            _m.instr_note_edit_active = false;
        }
    }
    // Right-click a line to delete it from the instrument program. If the text
    // wasn't open it's committed straight away; if it was, the edit continues.
    if (_tb_content_hov && mouse_check_button_pressed(mb_right) && !_wave_click && !_box_busy && !_m.instr_note_edit_active) {
        var _rc_src = _sel_instr.text;
        if (_m.instr_edit_active) {
            _rc_src = _m.instr_edit_buf;
        }
        var _rc_lines = string_split(_rc_src, "\n");
        var _rc_line  = (floor((_my - _tb_y1 - 4) / 16) + _m.instr_text_scroll);
        if (_rc_line >= 0 && _rc_line < array_length(_rc_lines)) {
            array_delete(_rc_lines, _rc_line, 1);
            var _rc_new = string_join_ext("\n", _rc_lines);
            if (_m.instr_edit_active) {
                _m.instr_edit_buf    = _rc_new;
                _m.instr_edit_cursor = min(_m.instr_edit_cursor, string_length(_rc_new));
            } else {
                _m.instr_edit_active      = true;
                _m.instr_edit_buf         = _rc_new;
                _m.instr_edit_cursor      = 0;
                _m.instr_name_edit_active = false;
                scr_sound_editor_commit_instrument(_m, _sel_instr);
            }
        }
    }
    if (_in_notes && mouse_check_button_pressed(mb_left) && !_wave_click && !_box_busy) {
        // Click a line's note to edit it.
        var _nl_src = _sel_instr.text;
        if (_m.instr_edit_active) {
            _nl_src = _m.instr_edit_buf;
            scr_sound_editor_commit_instrument(_m, _sel_instr);
        }
        var _nl_lines = string_split(_nl_src, "\n");
        var _nl_line = floor((_my - _tb_y1 - 4) / 16) + _m.instr_text_scroll;
        if (_nl_line >= 0 && _nl_line < array_length(_nl_lines) && string_trim(_nl_lines[_nl_line]) != "") {
            var _nl_key = string_trim(_nl_lines[_nl_line]);
            var _nl_ovr = _sel_instr[$ "note_overrides"];
            var _nl_txt = scr_sound_editor_instr_comment(_nl_lines[_nl_line], _nl_lines).text;
            if (!is_undefined(_nl_ovr) && !is_undefined(_nl_ovr[$ _nl_key])) {
                _nl_txt = _nl_ovr[$ _nl_key];
            }
            _m.instr_note_edit_active = true;
            _m.instr_note_edit_key    = _nl_key;
            _m.instr_note_edit_buf    = _nl_txt;
            _m.instr_name_edit_active = false;
            keyboard_string = "";
        }
    }
    if (_in_code && mouse_check_button_pressed(mb_left) && !_wave_click && !_box_busy) {
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
            var _click_line = clamp((floor((_my - _tb_y1 - 4) / 16) + _m.instr_text_scroll), 0, array_length(_cl_lines) - 1);
            var _cl_prefix = string(_click_line);
            while (string_length(_cl_prefix) < 2) { _cl_prefix = "0" + _cl_prefix; }
            _cl_prefix += ": ";
            var _cl_prefix_w  = string_width_l(_cl_prefix);
            var _cl_line_txt  = _cl_lines[_click_line];
            var _cl_best_col  = string_length(_cl_line_txt);
            for (var _cci = 0; _cci <= string_length(_cl_line_txt); _cci++) {
                var _cl_sub_w = string_width_l(string_copy(_cl_line_txt, 1, _cci));
                if (_tb_x0 + 4 + _cl_prefix_w + _cl_sub_w >= _mx) {
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
    if (!variable_struct_exists(_m, "instr_lines_source") || _m.instr_lines_source != _tb_disp) {
        _m.instr_lines_source = _tb_disp;
        _m.instr_lines_cache = string_split(_tb_disp, "\n");
        _m.instr_comments_cache = array_create(array_length(_m.instr_lines_cache), undefined);
    }
    var _tb_lines = _m.instr_lines_cache;

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

    if (_m.instr_edit_active) {
        if (!variable_struct_exists(_m, "instr_last_cursor") || _m.instr_last_cursor != _m.instr_edit_cursor) {
            if (_tb_cursor_line < _m.instr_text_scroll) _m.instr_text_scroll = _tb_cursor_line;
            if (_tb_cursor_line >= _m.instr_text_scroll + _visible_lines) _m.instr_text_scroll = _tb_cursor_line - _visible_lines + 1;
            _m.instr_last_cursor = _m.instr_edit_cursor;
        }
    }
    var _live_lines = [];
    var _table_lines = [];   // table records being run right now (~PULSE etc.)
    var _follow_line = -1;
    for (var _fv = 0; _fv < array_length(_follow); _fv++) {
        var _live = _follow[_fv];
        if (!is_struct(_live) || _live.instr != _sel_instr || !is_struct(_live.compiled)) continue;
        // Suppress stale positions while the source is being changed.
        if (_live.compiled.source != _tb_disp) continue;
        for (var _fp = 0; _fp < array_length(_live.pcs); _fp++) {
            var _pc = _live.pcs[_fp];
            if (_pc < 0 || _pc >= array_length(_live.compiled.byte_lines)) continue;
            var _line = _live.compiled.byte_lines[_pc];
            if (_line >= 0) { array_push(_live_lines, _line); if (_follow_line < 0) _follow_line = _line; }
        }
        var _tpcs = _live[$ "tpcs"];
        if (is_array(_tpcs)) {
            for (var _tp = 0; _tp < array_length(_tpcs); _tp++) {
                var _tpc = _tpcs[_tp];
                if (_tpc < 0 || _tpc >= array_length(_live.compiled.byte_lines)) {
                    continue;
                }
                var _tline = _live.compiled.byte_lines[_tpc];
                if (_tline >= 0) {
                    array_push(_table_lines, _tline);
                }
            }
        }
    }
    if (_follow_line >= 0 && _m.instr_text_drag < 0 && !_m.instr_edit_active && !point_in_rectangle(_mx, _my, _tb_x0, _tb_y1, _tb_x0 + _tb_w, _tb_y1 + _tb_h)) {
        if (_follow_line < _m.instr_text_scroll || _follow_line >= _m.instr_text_scroll + _visible_lines) {
            _m.instr_text_scroll = clamp(_follow_line - 2, 0, max(0, array_length(_tb_lines) - _visible_lines));
        }
    }
    // ── STEP-NUMBER GUTTER, DIVIDER LINE, & AUTOMATED SIDE COMMENTS ──
    var _tb_blink = (current_time mod 600) < 300;
    
    // The divider: brighter while hovered or dragged.
    draw_set_color(make_color_rgb(45, 45, 65));
    if (_div_hov || _m.instr_div_drag) {
        draw_set_color(make_color_rgb(120, 140, 200));
    }
    draw_line(_div_x, _tb_y1 + 2, _div_x, _tb_y1 + _tb_h - 2);
    var _nt_maxw = 0;   // widest visible note, for the horizontal scrollbar
    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();

    // ── TABLE SECTIONS ── everything from the first "~" line on is table
    // data (the parser's rule). Each table gets a tinted band, its "~" header
    // a rule above it and its own colour, so it reads apart from the program.
    var _tb_tab = array_create(array_length(_tb_lines), 0);   // 0 program, 1 table line, 2 table header
    var _tb_in_tab = false;
    for (var _tti = 0; _tti < array_length(_tb_lines); _tti++) {
        if (string_char_at(string_trim(_tb_lines[_tti]), 1) == "~") {
            _tb_in_tab = true;
            _tb_tab[_tti] = 2;
        } else if (_tb_in_tab) {
            _tb_tab[_tti] = 1;
        }
    }

    for (var _tli = _m.instr_text_scroll; _tli < min(array_length(_tb_lines), _m.instr_text_scroll + _visible_lines); _tli++) {
        // Lines past the bottom of the box aren't drawn — the box never spills.
        if (4 + ((_tli - _m.instr_text_scroll) * 16) + 14 > _tb_h) {
            break;
        }
        if (_tb_tab[_tli] > 0) {
            var _tab_y = _tb_y1 + 3 + (_tli - _m.instr_text_scroll) * 16;
            draw_set_color(make_color_rgb(22, 20, 38));
            draw_rectangle(_tb_x0 + 2, _tab_y, _tb_x0 + _tb_w - 14, _tab_y + 16, false);
            draw_set_color(make_color_rgb(120, 90, 170));
            draw_line(_tb_x0 + 2, _tab_y, _tb_x0 + 2, _tab_y + 16);           // left edge bar
            if (_tb_tab[_tli] == 2) {
                draw_set_color(make_color_rgb(150, 110, 210));
                draw_line(_tb_x0 + 2, _tab_y, _tb_x0 + _tb_w - 14, _tab_y);   // rule above the header
            }
        }
        var _line_live = false;
        for (var _fl = 0; _fl < array_length(_live_lines); _fl++) if (_live_lines[_fl] == _tli) _line_live = true;
        // A running table's current record: its own (purple) highlight, so the
        // program's green step and the table's step show at the same time.
        var _line_tab = false;
        for (var _ftl = 0; _ftl < array_length(_table_lines); _ftl++) {
            if (_table_lines[_ftl] == _tli) {
                _line_tab = true;
                draw_set_color(make_color_rgb(95, 55, 150));
                var _tl_y = _tb_y1 + 3 + (_tli - _m.instr_text_scroll) * 16;
                draw_rectangle(_tb_x0 + 2, _tl_y, _tb_x0 + _tb_w - 14, _tl_y + 16, false);
            }
        }
        if (_line_live) {
            draw_set_color(make_color_rgb(25, 80, 48));
            var _live_y = _tb_y1 + 3 + (_tli - _m.instr_text_scroll) * 16;
            draw_rectangle(_tb_x0 + 2, _live_y, _tb_x0 + _tb_w - 14, _live_y + 16, false);
        }
        var _tb_prefix = string(_tli);
        while (string_length(_tb_prefix) < 2) { _tb_prefix = "0" + _tb_prefix; }
        _tb_prefix += ": ";
        var _tb_prefix_w = string_width_l(_tb_prefix);

        draw_set_color(make_color_rgb(90, 90, 120));
        draw_text_l(_tb_x0 + 4, _tb_y1 + 4 + (_tli - _m.instr_text_scroll) * 16, _tb_prefix);

        var _tb_line_txt = _tb_lines[_tli];
        if (_m.instr_edit_active && _tb_blink && _tli == _tb_cursor_line) {
            _tb_line_txt = string_insert("|", _tb_line_txt, _tb_cursor_col + 1);
        }
        draw_set_color(_line_live ? c_white : (_m.instr_edit_active ? c_lime : make_color_rgb(160, 160, 180)));
        if (_line_tab) {
            draw_set_color(c_white);
        }
        if (!_line_live && !_line_tab && _tb_tab[_tli] == 2) {
            draw_set_color(make_color_rgb(200, 160, 255));   // ~PULSE / ~PITCH / ~FILTER header
        }
        while (string_length(_tb_line_txt) > 0 && string_width_l(_tb_line_txt) > _div - 12 - _tb_prefix_w) _tb_line_txt = string_delete(_tb_line_txt, string_length(_tb_line_txt), 1);
        draw_text_l(_tb_x0 + 4 + _tb_prefix_w, _tb_y1 + 4 + (_tli - _m.instr_text_scroll) * 16, _tb_line_txt);

        // Plain-English side note for every line, live while typing too
        // (see scr_sound_editor_instr_comment). Mid-blue; problems in red.
        // Resolve visible help once per source edit, not once per redraw.
        if (is_undefined(_m.instr_comments_cache[_tli])) {
            _m.instr_comments_cache[_tli] = scr_sound_editor_instr_comment(_tb_lines[_tli], _tb_lines);
        }
        var _cm = _m.instr_comments_cache[_tli];
        var _comment = _cm.text;
        var _cm_col = make_color_rgb(90, 150, 230);
        if (_cm.bad) {
            _cm_col = make_color_rgb(230, 90, 90);
        }
        var _cm_key = string_trim(_tb_lines[_tli]);
        var _cm_ovr = _sel_instr[$ "note_overrides"];
        if (!is_undefined(_cm_ovr) && _cm_key != "" && !is_undefined(_cm_ovr[$ _cm_key])) {
            _comment = _cm_ovr[$ _cm_key];                  // your own note
            _cm_col = make_color_rgb(230, 200, 120);
        }
        var _cm_y = _tb_y1 + 4 + (_tli - _m.instr_text_scroll) * 16;
        var _cm_editing = _m.instr_note_edit_active && _cm_key == _m.instr_note_edit_key;
        if (_cm_editing) {
            _comment = _m.instr_note_edit_buf;
            if (_tb_blink) {
                _comment += "|";
            }
            _cm_col = c_white;
            draw_set_color(make_color_rgb(40, 40, 70));
            draw_rectangle(_nt_x0 - 4, _cm_y - 1, _nt_x1, _cm_y + 14, false);
        }
        if (_comment != "") {
            // The notes column scrolls sideways (scrollbar below) and is
            // clipped to its own area, so long notes read in full.
            var _cw = string_width_l(_comment);
            _nt_maxw = max(_nt_maxw, _cw);
            var _cx = _nt_x0 - _m.instr_note_hscroll;
            if (_cm_editing) {
                _cx = _nt_x0 - max(0, _cw - _nt_w);       // keep the typing end in view
            }
            gpu_set_scissor(floor(_nt_x0 * _sx_sc), floor(_tb_y1 * _sy_sc), ceil(_nt_w * _sx_sc), ceil(_tb_h * _sy_sc));
            draw_set_color(_cm_col);
            draw_text_l(_cx, _cm_y, _comment);
            gpu_set_scissor(0, 0, window_get_width(), window_get_height());
        }
    }

    // ── NOTES HORIZONTAL SCROLLBAR ──
    _m.instr_note_hscroll = scr_sound_editor_hscrollbar(_m, "instr_note_hdrag", _m.instr_note_hscroll,
        _nt_maxw, _nt_w, _div_x + 4, _hs_y, _nt_x1 - _div_x - 4, 9, _mx, _my);

    // Space while editing an instrument previews it: C in the current
    // octave, played from the text as typed (not yet committed).
    if (_m.instr_edit_active && keyboard_check_pressed(vk_space)) {
        keyboard_string = string_replace_all(keyboard_string, " ", "");
        var _sp_oct = 4;
        var _sp_o = _m[$ "cur_octave"];
        if (!is_undefined(_sp_o)) {
            _sp_oct = real(_sp_o);
        }
        var _sp_ins = {
            follow_owner: _sel_instr,
            text        : _m.instr_edit_buf,
            attack      : _sel_instr.attack,
            decay       : _sel_instr.decay,
            sustain     : _sel_instr.sustain,
            release     : _sel_instr.release,
            pulse_width : _sel_instr.pulse_width,
            vib_delay   : scr_sid64_instr_field(_sel_instr, "vib_delay", 0),
            vib_speed   : scr_sid64_instr_field(_sel_instr, "vib_speed", 0),
            vib_depth   : scr_sid64_instr_field(_sel_instr, "vib_depth", 0)
        };
        scr_sound_instrument_preview_play(_sp_ins, "C-" + string(_sp_oct), 0);
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
            if (_tb_added != "" && string_length(_m.instr_edit_buf) < 200000) {
                _m.instr_edit_buf    = string_insert(_tb_added, _m.instr_edit_buf, _m.instr_edit_cursor + 1);
                _m.instr_edit_cursor += string_length(_tb_added);
            }
            keyboard_string = "";
        }
    }

    // ── COMPILED PREVIEW / ERRORS ──
    scr_instrument_ensure_compiled(_sel_instr);
    var _pv_y = _tb_y1 + _tb_h + 16;
    draw_set_color(make_color_rgb(120, 120, 160));
    draw_text_l(_tb_x0, _pv_y, L("COMMANDS: ") + string(array_length(_sel_instr.compiled.bytes)) + L(" BYTES"));
    if (_two_col && _tb_w >= 360) {
        if (scr_sfx_maker_button(_tb_x0 + _tb_w - 124, _pv_y - 4, 124, "TABLE SIZE", _mx, _my)) {
            if (_m.instr_edit_active) scr_sound_editor_commit_instrument(_m, _sel_instr);
            var _pack = scr_music_table_pack(_m.instruments);
            show_message("MUSIC MAKER SHARED TABLES\n\n"
                + "Instrument commands: " + string(_pack.raw_bytes) + " bytes\n"
                + "Stored commands + tables: " + string(_pack.stored_bytes) + " bytes\n"
                + "Shared tables: " + string(array_length(_pack.tables)) + "\n"
                + "Command data saved: " + string(_pack.raw_bytes - _pack.stored_bytes) + " bytes\n\n"
                + "Export automatically shares repeated command sequences.\n"
                + "Edit the instrument commands normally; tables rebuild on export.\n"
                + "These figures exclude instrument headers, patterns and player code.\n"
                + "Pattern GXX: fine tune; HXX: pitch sweep; IXX: pulse sweep.");
        }
    }
    var _err_n = array_length(_sel_instr.compiled.errors);
    if (_err_n > 0) {
        draw_set_font_l(fnt_c64_pico);
        draw_set_color(c_red);
        // At most three error lines are shown so the legend keeps its place.
        _err_n = min(_err_n, 3);
        for (var _eri = 0; _eri < _err_n; _eri++) {
            var _err_text = _sel_instr.compiled.errors[_eri];
            while (string_length(_err_text) > 0 && string_width_l(_err_text) > _tb_w) _err_text = string_delete(_err_text, string_length(_err_text), 1);
            draw_text_l(_tb_x0, _pv_y + 18 + _eri * 12, _err_text);
        }
        draw_set_font_l(fnt_c64_tiny);
    }

    // ── COMMAND LEGEND ──
    var _lg_y = _pv_y + 32 + (_err_n * 12) + 10;
    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(110, 110, 130));
    // Quick guide; the ? button above has the full version with examples.
    var _qg = [
        "$xx WAVE   N  N+n  N-n NOTE   Dn HOLD n FRAMES   --- END",
        "Ln LOOP TO STEP n   Rc:n REPEAT FROM STEP n, c MORE TIMES",
        "F+n FINE   S+n SLIDE   P$xxx PULSE   Q+n PULSE SWEEP",
        "G$xx RAW GATE/WAVE   H0 NO HARD RESTART   C$xxx CUTOFF   V$xy VIBRATO",
        "~PITCH  ~PULSE  ~FILTER: TABLES OF S / Q / C + D + L LINES",
        "  + KEEPS RUNNING   4 STEPS 4X A FRAME   >nn USES INSTR nn'S TABLE",
        "FULL GUIDE: ? BUTTON"
    ];
    for (var _qgi = 0; _qgi < array_length(_qg); _qgi++) {
        draw_text_l(_tb_x0, _lg_y + _qgi * 12, _qg[_qgi]);
    }
    draw_set_font_l(fnt_c64_tiny);

    // Dropdown list / help table last, so they sit over the command box.
    if (_two_col) {
        scr_sound_editor_cmd_bar(_m, _sel_instr, _tb_x0, _tb_x0 + _tb_w + 4, _iy0 - 22,
                                 _tb_x0 - 4, _tb_y1 - 2, _tb_x0 + _tb_w + 4, _tb_y1 + _tb_h + 2, _mx, _my, true);
    }

    draw_set_color(c_white);
}
/// Factory definitions use the existing instrument language and runtime fields.
/// Filter routing is per instrument; mode/cutoff/resonance remain song-wide.
function scr_sound_editor_presets() {
    return [
        { name: "LEAD PULSE", text: "$41\nD255\nL1", attack: 0, decay: 7, sustain: 12, release: 5,
          pulse_width: 1536, vib_delay: 10, vib_speed: 5, vib_depth: 2, filt: 0,
          hint: "BRIGHT PULSE + DELAYED VIBRATO. TRY C-4." },
        { name: "BASS FILTERED", text: "$41\nD255\nL1", attack: 0, decay: 9, sustain: 7, release: 3,
          pulse_width: 1024, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 1,
          hint: "SHORT ATTACK, NARROW PULSE, FILTER ON. TRY C-2." },
        { name: "ARP MAJOR", text: "$21\nN\nD2\nN+4\nD2\nN+7\nD2\nL1", attack: 0, decay: 6, sustain: 10, release: 4,
          pulse_width: 2048, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 0,
          hint: "ROOT / MAJOR THIRD / FIFTH. TRY C-3." },
        { name: "ARP MINOR", text: "$21\nN\nD2\nN+3\nD2\nN+7\nD2\nL1", attack: 0, decay: 6, sustain: 10, release: 4,
          pulse_width: 2048, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 0,
          hint: "ROOT / MINOR THIRD / FIFTH. TRY C-3." },
        { name: "KICK", text: "$81\nD1\n$11\nN+24\nD1\nN+12\nD1\nN+5\nD1\nN\nD8\n---", attack: 0, decay: 6, sustain: 0, release: 2,
          pulse_width: 2048, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 0,
          hint: "NOISE CLICK + FALLING TRIANGLE THUMP. TRY C-2." },
        { name: "SNARE", text: "$81\nD2\n$11\nN+12\nD2\n$81\nD10\n---", attack: 0, decay: 8, sustain: 0, release: 2,
          pulse_width: 2048, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 0,
          hint: "NOISE SNAP + TONAL BODY. TRY C-3." },
        { name: "TING", text: "$11\nN+12\nD2\nN\nD18\n---", attack: 0, decay: 10, sustain: 0, release: 6,
          pulse_width: 2048, vib_delay: 2, vib_speed: 3, vib_depth: 1, filt: 0,
          hint: "HIGH TRIANGLE CHIME + LIGHT VIBRATO. TRY C-5." },
        { name: "FLUTE", text: "$11\nD255\nL1", attack: 3, decay: 5, sustain: 11, release: 7,
          pulse_width: 2048, vib_delay: 14, vib_speed: 6, vib_depth: 1, filt: 1,
          hint: "SOFT TRIANGLE + DELAYED VIBRATO, FILTER ON. TRY C-4." },
        // A long pulse-width sweep: the ~PULSE table runs beside the held note,
        // +12 a frame for 150 frames (3 s, $100 -> $808), then back down.
        // The program holds (D255 / L1) so the table keeps running.
        { name: "BASS PWM SWEEP", text: "$41\nD255\nL1\n~PULSE\nQ+12\nD150\nQ-12\nD150\nL4",
          attack: 0, decay: 9, sustain: 10, release: 4,
          pulse_width: 256, vib_delay: 0, vib_speed: 0, vib_depth: 0, filt: 0,
          hint: "HELD PULSE BASS, WIDTH SWEEPS UP AND DOWN EVERY 6 SECONDS. TRY C-2, LONG NOTES." }
    ];
}

function scr_sound_editor_add_preset(_m, _preset) {
    if (array_length(_m.instruments) >= 255) return false;
    var _compiled = scr_instrument_parse(_preset.text);
    if (array_length(_compiled.errors) > 0) return false;
    array_push(_m.instruments, {
        name: _preset.name, text: _preset.text, compiled: _compiled, ins_name: "", dirty: false,
        attack: _preset.attack, decay: _preset.decay, sustain: _preset.sustain, release: _preset.release,
        pulse_width: _preset.pulse_width, vib_delay: _preset.vib_delay,
        vib_speed: _preset.vib_speed, vib_depth: _preset.vib_depth, filt: _preset.filt
    });
    // A routed voice with no filter mode is silent. Initialise only an off filter.
    if (_preset.filt != 0 && _m.filt_mode == 0) {
        _m.filt_mode = 1;
        _m.filt_res = 4;
        _m.filt_cut = 900;
    }
    _m.sel_instr = array_length(_m.instruments) - 1;
    _m.instr_edit_active = false;
    _m.instr_name_edit_active = false;
    global.undo_dirty = true;
    global.addresses_dirty = true;
    return true;
}

function scr_sound_editor_preset_picker(_m, _x, _y, _w, _visible, _mx, _my) {
    var _presets = scr_sound_editor_presets();
    var _count = array_length(_presets);
    var _added = 0;
    draw_set_color(make_color_rgb(14, 14, 22));
    draw_rectangle(_x - 4, _y - 2, _x + _w + 4, _y + (_count + 1) * 26 + 76, false);
    for (var _p = 0; _p < _count; _p++) {
        var _py = _y + _p * 26;
        var _room = array_length(_m.instruments) < 255;
        if (scr_sfx_maker_button(_x, _py, _w, "+ " + _presets[_p].name, _mx, _my) && _room) {
            if (scr_sound_editor_add_preset(_m, _presets[_p])) _added = 1;
        }
        if (point_in_rectangle(_mx, _my, _x, _py, _x + _w, _py + 24)) {
            _m.pattern_hover_tip = _presets[_p].hint
                + "\nCLICK TO ADD AN EDITABLE COPY. EXISTING INSTRUMENTS STAY IN PLACE.";
        }
    }
    var _all_room = array_length(_m.instruments) + _count <= 255;
    var _all_lab = "NEED " + string(_count) + " FREE INSTRUMENT SLOTS";
    if (_all_room) {
        _all_lab = "+ ADD ALL " + string(_count) + " PRESETS";
    }
    if (scr_sfx_maker_button(_x, _y + _count * 26, _w, _all_lab, _mx, _my) && _all_room) {
        for (var _a = 0; _a < _count; _a++) {
            if (scr_sound_editor_add_preset(_m, _presets[_a])) _added += 1;
        }
    }
    draw_set_font_l(fnt_c64_pico);
    draw_set_color(make_color_rgb(180, 190, 210));
    draw_text_ext_l(_x, _y + (_count + 1) * 26 + 4,
        "HOVER FOR SOUND / NOTE TIPS.\nFILTERED PRESETS ENABLE LOW-PASS IF OFF.\nTHE SONG FILTER IS SHARED; ACTIVE SETTINGS ARE KEPT.\nESC OR CLOSE PRESETS TO RETURN.", -1, _w);
    draw_set_font_l(fnt_c64_tiny);
    if (_added > 0) {
        _m.instr_list_scroll = max(0, _m.sel_instr - _visible + 1);
        _m.preset_picker_open = false;
        _m.warn_msg = "ADDED " + string(_added) + " PRESET INSTRUMENT(S)";
        _m.warn_timer = game_get_speed(gamespeed_fps) * 3;
    }
    if (keyboard_check_pressed(vk_escape)) _m.preset_picker_open = false;
    keyboard_string = "";
    draw_set_color(c_white);
}

/// Shared vertical scrollbar. Dragging never changes the editor's text cursor.
function scr_sound_editor_scrollbar(_m, _key, _value, _total, _visible, _sx, _sy, _sw, _sh, _mx, _my) {
    if (!variable_struct_exists(_m, _key)) _m[$ _key] = -1;
    var _limit = max(0, _total - _visible);
    _value = clamp(_value, 0, _limit);
    var _thumb = min(_sh, max(22, _sh * _visible / max(1, _total)));
    var _travel = max(0, _sh - _thumb);
    var _top = _sy + (_limit > 0 ? _travel * _value / _limit : 0);
    var _hover = point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh);
    if (!mouse_check_button(mb_left)) _m[$ _key] = -1;
    if (_limit > 0 && _hover && mouse_check_button_pressed(mb_left)) {
        _m[$ _key] = (_my >= _top && _my <= _top + _thumb) ? _my - _top : _thumb * 0.5;
    }
    if (_m[$ _key] >= 0 && _travel > 0) {
        _value = round(clamp((_my - _sy - _m[$ _key]) / _travel, 0, 1) * _limit);
        _top = _sy + _travel * _value / _limit;
    }
    draw_set_color(make_color_rgb(24, 26, 40));
    draw_rectangle(_sx, _sy, _sx + _sw, _sy + _sh, false);
    draw_set_color(_limit == 0 ? make_color_rgb(48, 50, 64) :
        ((_hover || _m[$ _key] >= 0) ? make_color_rgb(150, 190, 240) : make_color_rgb(85, 105, 145)));
    draw_rectangle(_sx + 2, _top + 1, _sx + _sw - 2, _top + _thumb - 1, false);
    return _value;
}

/// Horizontal twin of scr_sound_editor_scrollbar, in pixels: _content is the
/// widest thing, _view the visible width. Returns the new scroll offset.
function scr_sound_editor_hscrollbar(_m, _key, _value, _content, _view, _sx, _sy, _sw, _sh, _mx, _my) {
    var _limit = max(0, _content - _view);
    _value = clamp(_value, 0, _limit);
    var _thumb = min(_sw, max(22, _sw * _view / max(1, _content)));
    var _travel = max(0, _sw - _thumb);
    var _left = _sx;
    if (_limit > 0) {
        _left = _sx + _travel * _value / _limit;
    }
    var _hover = point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh);
    if (!mouse_check_button(mb_left)) {
        _m[$ _key] = -1;
    }
    if (_limit > 0 && _hover && mouse_check_button_pressed(mb_left)) {
        if (_mx >= _left && _mx <= _left + _thumb) {
            _m[$ _key] = _mx - _left;
        } else {
            _m[$ _key] = _thumb * 0.5;
        }
    }
    if (_m[$ _key] >= 0 && _travel > 0) {
        _value = round(clamp((_mx - _sx - _m[$ _key]) / _travel, 0, 1) * _limit);
        _left = _sx + _travel * _value / _limit;
    }
    draw_set_color(make_color_rgb(24, 26, 40));
    draw_rectangle(_sx, _sy, _sx + _sw, _sy + _sh, false);
    var _tc = make_color_rgb(48, 50, 64);
    if (_limit > 0) {
        _tc = make_color_rgb(85, 105, 145);
        if (_hover || _m[$ _key] >= 0) {
            _tc = make_color_rgb(150, 190, 240);
        }
    }
    draw_set_color(_tc);
    draw_rectangle(_left + 1, _sy + 2, _left + _thumb - 1, _sy + _sh - 2, false);
    return _value;
}
