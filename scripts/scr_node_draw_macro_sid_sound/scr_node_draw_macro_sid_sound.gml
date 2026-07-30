/// @desc scr_node_draw_macro_sid_sound(_draw_x, _y)
/// instructions[0]: ["macro_sid_sound",
///   1 voice_mode 2 voice_lit 3 voice_var,
///   4 note_mode  5 note_lit  6 note_var,
///   7 wave_mode  8 wave_lit  9 wave_var,
///   10 ad_mode   11 ad_lit   12 ad_var,
///   13 sr_mode   14 sr_lit   15 sr_var,
///   16 pulse_on,
///   17 pw_mode   18 pw_lit   19 pw_var,
///   20 zp_base]

function scr_node_draw_macro_sid_sound(_draw_x, _y) {

    var _ins = instructions[0];

    var _voice_mode = (array_length(_ins) > 1 && is_real(_ins[1]))  ? real(_ins[1]) : 0;
    var _voice_lit  = (array_length(_ins) > 2 && is_real(_ins[2]))  ? clamp(real(_ins[2]), 0, 2) : 0;
    var _voice_var  = (array_length(_ins) > 3)  ? string(_ins[3])  : "";
    var _note_mode  = (array_length(_ins) > 4 && is_real(_ins[4]))  ? real(_ins[4]) : 0;
    var _note_lit   = (array_length(_ins) > 5 && is_real(_ins[5]))  ? real(_ins[5]) & 0xFFFF : 0;
    var _note_var   = (array_length(_ins) > 6)  ? string(_ins[6])  : "";
    var _wave_mode  = (array_length(_ins) > 7 && is_real(_ins[7]))  ? real(_ins[7]) : 0;
    var _wave_lit   = (array_length(_ins) > 8 && is_real(_ins[8]))  ? real(_ins[8]) & 0xFF : 0;
    var _wave_var   = (array_length(_ins) > 9)  ? string(_ins[9])  : "";
    var _ad_mode    = (array_length(_ins) > 10 && is_real(_ins[10])) ? real(_ins[10]) : 0;
    var _ad_lit     = (array_length(_ins) > 11 && is_real(_ins[11])) ? real(_ins[11]) & 0xFF : 0;
    var _ad_var     = (array_length(_ins) > 12) ? string(_ins[12]) : "";
    var _sr_mode    = (array_length(_ins) > 13 && is_real(_ins[13])) ? real(_ins[13]) : 0;
    var _sr_lit     = (array_length(_ins) > 14 && is_real(_ins[14])) ? real(_ins[14]) & 0xFF : 0;
    var _sr_var     = (array_length(_ins) > 15) ? string(_ins[15]) : "";
    var _pulse_on   = (array_length(_ins) > 16 && is_real(_ins[16])) ? real(_ins[16]) : 0;
    var _pw_mode    = (array_length(_ins) > 17 && is_real(_ins[17])) ? real(_ins[17]) : 0;
    var _pw_lit     = (array_length(_ins) > 18 && is_real(_ins[18])) ? real(_ins[18]) & 0x0FFF : 0;
    var _pw_var     = (array_length(_ins) > 19) ? string(_ins[19]) : "";
    var _zp         = (array_length(_ins) > 20 && is_real(_ins[20])) ? real(_ins[20]) & 0xFF : 0xFC;
    var _note_ast   = (array_length(_ins) > 21) ? string(_ins[21]) : "";
    var _off_mode   = (array_length(_ins) > 22 && is_real(_ins[22])) ? real(_ins[22]) : 0;
    var _off_lit    = (array_length(_ins) > 23 && is_real(_ins[23])) ? real(_ins[23]) & 0xFF : 0;
    var _off_var    = (array_length(_ins) > 24) ? string(_ins[24]) : "";
    var _wave_ast   = (array_length(_ins) > 25) ? string(_ins[25]) : "";
    var _woff_mode  = (array_length(_ins) > 26 && is_real(_ins[26])) ? real(_ins[26]) : 0;
    var _woff_lit   = (array_length(_ins) > 27 && is_real(_ins[27])) ? real(_ins[27]) & 0xFF : 0;
    var _woff_var   = (array_length(_ins) > 28) ? string(_ins[28]) : "";

    var _lh = 14;
    var _ly = _y + 28;

    var _c_lbl  = make_color_rgb(140, 160, 200);
    var _c_dim  = make_color_rgb(90, 90, 100);
    var _vbtn_w = 28;
    var _vx     = _draw_x + width - 38;

    var _col_on  = make_color_rgb(180, 140, 30);
    var _col_off = make_color_rgb(50, 50, 60);
    var _txt_off = make_color_rgb(140, 140, 160);

    draw_set_font(fnt_c64_tiny);

    // ===== VOICE =====
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "VOICE:");
    if (_voice_mode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 62, _ly, (_voice_var != "") ? _voice_var : "<PICK>");
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 62, _ly, "V" + string(_voice_lit + 1));
    }
    draw_set_color((_voice_mode == 1) ? _col_on : _col_off);
    draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
    draw_set_color((_voice_mode == 1) ? c_yellow : _txt_off);
    draw_set_halign(fa_center);
    draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ===== NOTE =====
    // Mode cycles LIT -> VAR -> ASSET. The right-hand button shows the mode
    // it will switch TO, so one button drives all three states.
    var _note_edit = (obj_workspace_manager.is_entering_text &&
                      obj_workspace_manager.input_target_node  == id &&
                      obj_workspace_manager.input_target_index == 5);
    var _c_ast = make_color_rgb(255, 190, 90);
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "NOTE:");
    if (_note_mode == 2) {
        draw_set_color(_c_ast);
        draw_text(_draw_x + 62, _ly, "LIST");
    } else if (_note_mode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 62, _ly, (_note_var != "") ? _note_var : "<PICK>");
    } else if (_note_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _nh = decimal_to_hex(_note_lit);
        while (string_length(_nh) < 4) _nh = "0" + _nh;
        draw_set_color(c_aqua);
        draw_text(_draw_x + 62, _ly, "$" + string_upper(_nh));
    }
    var _nm_lbl = "LIT";
    if (_note_mode == 1) {
        _nm_lbl = "VAR";
    } else if (_note_mode == 2) {
        _nm_lbl = "AST";
    }
    if (_note_mode == 0) {
        draw_set_color(_col_off);
    } else {
        draw_set_color(_col_on);
    }
    draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
    if (_note_mode == 0) {
        draw_set_color(_txt_off);
    } else {
        draw_set_color(c_yellow);
    }
    draw_set_halign(fa_center);
    draw_text(_vx + (_vbtn_w * 0.5), _ly, _nm_lbl);
    draw_set_halign(fa_left);
    _ly += _lh;

    // ===== NOTE LIST + OFFSET (ASSET mode only) =====
    if (_note_mode == 2) {
        // TEXT_DATA asset holding the note names
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "LIST:");
        if (_note_ast == "" || _note_ast == "[clear]") {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text(_draw_x + 62, _ly, "< PICK TEXT >");
        } else {
            draw_set_color(_c_ast);
            var _ast_disp = _note_ast;
            if (string_length(_ast_disp) > 14) {
                _ast_disp = string_copy(_ast_disp, 1, 14) + "...";
            }
            draw_text(_draw_x + 62, _ly, _ast_disp);
        }
        _ly += _lh;

        // Note index into the list — literal or from a VAR
        var _off_edit = (obj_workspace_manager.is_entering_text &&
                         obj_workspace_manager.input_target_node  == id &&
                         obj_workspace_manager.input_target_index == 23);
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "IDX:");
        if (_off_mode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 62, _ly, (_off_var != "") ? _off_var : "<PICK>");
        } else if (_off_edit) {
            draw_set_color(c_lime);
            draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
        } else {
            draw_set_color(c_aqua);
            draw_text(_draw_x + 62, _ly, string(_off_lit));
        }
        if (_off_mode == 1) {
            draw_set_color(_col_on);
        } else {
            draw_set_color(_col_off);
        }
        draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
        if (_off_mode == 1) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(_txt_off);
        }
        draw_set_halign(fa_center);
        draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
        draw_set_halign(fa_left);
        _ly += _lh;

        // Parsed note count — the only compile-time feedback the user gets,
        // and it catches a mistyped asset name immediately.
        draw_set_font(fnt_c64_pico);
        var _n_found = false;
        var _n_count = 0;
        if (_note_ast != "" && _note_ast != "[clear]" && instance_exists(obj_asset_manager)) {
            var _am_nd = obj_asset_manager;
            for (var _ndi = 0; _ndi < ds_list_size(_am_nd.asset_list); _ndi++) {
                var _a_nd = ds_list_find_value(_am_nd.asset_list, _ndi);
                if (_a_nd.type == "TEXT_DATA" && _a_nd.name == _note_ast) {
                    _n_found = true;
                    if (variable_struct_exists(_a_nd.meta, "text")) {
                        _n_count = array_length(scr_sid_notes_parse(string(_a_nd.meta.text)));
                    }
                    break;
                }
            }
        }
        if (!_n_found) {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text(_draw_x + 8, _ly, "! LIST NOT FOUND");
        } else {
            draw_set_color(make_color_rgb(80, 120, 180));
            draw_text(_draw_x + 8, _ly, string(_n_count) + " NOTES   " + string(_n_count * 3) + "B TABLE");
        }
        draw_set_font(fnt_c64_tiny);
        _ly += _lh;
    }

    // ===== WAVE =====
    // Mode cycles LIT -> VAR -> ASSET, same as NOTE. ASSET reads a BYTE_DATA
    // list of control bytes, so a second index can walk instruments while the
    // note index walks the melody.
    var _wave_edit = (obj_workspace_manager.is_entering_text &&
                      obj_workspace_manager.input_target_node  == id &&
                      obj_workspace_manager.input_target_index == 8);
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "WAVE:");
    if (_wave_mode == 2) {
        draw_set_color(_c_ast);
        draw_text(_draw_x + 62, _ly, "LIST");
    } else if (_wave_mode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 62, _ly, (_wave_var != "") ? _wave_var : "<PICK>");
    } else if (_wave_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _wh = decimal_to_hex(_wave_lit);
        while (string_length(_wh) < 2) _wh = "0" + _wh;
        draw_set_color(c_aqua);
        draw_text(_draw_x + 62, _ly, "$" + string_upper(_wh));
    }
    var _wm_lbl = "LIT";
    if (_wave_mode == 1) {
        _wm_lbl = "VAR";
    } else if (_wave_mode == 2) {
        _wm_lbl = "AST";
    }
    if (_wave_mode == 0) {
        draw_set_color(_col_off);
    } else {
        draw_set_color(_col_on);
    }
    draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
    if (_wave_mode == 0) {
        draw_set_color(_txt_off);
    } else {
        draw_set_color(c_yellow);
    }
    draw_set_halign(fa_center);
    draw_text(_vx + (_vbtn_w * 0.5), _ly, _wm_lbl);
    draw_set_halign(fa_left);
    _ly += _lh;

    // ===== WAVE LIST + IDX (ASSET mode only) =====
    if (_wave_mode == 2) {
        // BYTE_DATA asset holding the control bytes
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "WLST:");
        if (_wave_ast == "" || _wave_ast == "[clear]") {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text(_draw_x + 62, _ly, "< PICK BYTE >");
        } else {
            draw_set_color(_c_ast);
            var _wast_disp = _wave_ast;
            if (string_length(_wast_disp) > 14) {
                _wast_disp = string_copy(_wast_disp, 1, 14) + "...";
            }
            draw_text(_draw_x + 62, _ly, _wast_disp);
        }
        _ly += _lh;

        // Wave index — literal or from a VAR, independent of the note index
        var _woff_edit = (obj_workspace_manager.is_entering_text &&
                          obj_workspace_manager.input_target_node  == id &&
                          obj_workspace_manager.input_target_index == 27);
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "WIDX:");
        if (_woff_mode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 62, _ly, (_woff_var != "") ? _woff_var : "<PICK>");
        } else if (_woff_edit) {
            draw_set_color(c_lime);
            draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
        } else {
            draw_set_color(c_aqua);
            draw_text(_draw_x + 62, _ly, string(_woff_lit));
        }
        if (_woff_mode == 1) {
            draw_set_color(_col_on);
        } else {
            draw_set_color(_col_off);
        }
        draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
        if (_woff_mode == 1) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(_txt_off);
        }
        draw_set_halign(fa_center);
        draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
        draw_set_halign(fa_left);
        _ly += _lh;

        // Byte count + the two reserved values, since neither is guessable.
        draw_set_font(fnt_c64_pico);
        var _w_found = false;
        var _w_size  = 0;
        if (_wave_ast != "" && _wave_ast != "[clear]" && instance_exists(obj_asset_manager)) {
            var _am_wd = obj_asset_manager;
            for (var _wdi = 0; _wdi < ds_list_size(_am_wd.asset_list); _wdi++) {
                var _a_wd = ds_list_find_value(_am_wd.asset_list, _wdi);
                if (_a_wd.type == "BYTE_DATA" && _a_wd.name == _wave_ast) {
                    _w_found = true;
                    if (buffer_exists(_a_wd.buffer)) {
                        _w_size = buffer_get_size(_a_wd.buffer);
                    }
                    break;
                }
            }
        }
        if (!_w_found) {
            draw_set_color(make_color_rgb(230, 90, 90));
            draw_text(_draw_x + 8, _ly, "! WAVE LIST NOT FOUND");
        } else {
            draw_set_color(make_color_rgb(80, 120, 180));
            draw_text(_draw_x + 8, _ly, string(_w_size) + "B   $00=OFF  $FF=SKIP");
        }
        draw_set_font(fnt_c64_tiny);
        _ly += _lh;
    }

    // ===== AD =====
    var _ad_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 11);
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "AD:");
    if (_ad_mode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 62, _ly, (_ad_var != "") ? _ad_var : "<PICK>");
    } else if (_ad_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _ah = decimal_to_hex(_ad_lit);
        while (string_length(_ah) < 2) _ah = "0" + _ah;
        draw_set_color(c_aqua);
        draw_text(_draw_x + 62, _ly, "$" + string_upper(_ah));
    }
    draw_set_color((_ad_mode == 1) ? _col_on : _col_off);
    draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
    draw_set_color((_ad_mode == 1) ? c_yellow : _txt_off);
    draw_set_halign(fa_center);
    draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ===== SR =====
    var _sr_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 14);
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "SR:");
    if (_sr_mode == 1) {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 62, _ly, (_sr_var != "") ? _sr_var : "<PICK>");
    } else if (_sr_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _sh = decimal_to_hex(_sr_lit);
        while (string_length(_sh) < 2) _sh = "0" + _sh;
        draw_set_color(c_aqua);
        draw_text(_draw_x + 62, _ly, "$" + string_upper(_sh));
    }
    draw_set_color((_sr_mode == 1) ? _col_on : _col_off);
    draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
    draw_set_color((_sr_mode == 1) ? c_yellow : _txt_off);
    draw_set_halign(fa_center);
    draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ===== PULSE checkbox =====
    var _cbx = _draw_x + 10;
    if (_pulse_on == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_pulse_on == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx + 18, _ly, "PULSE WIDTH");
    _ly += _lh;

    // ===== PW (interactive only if pulse on) =====
    var _pw_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 18);
    if (_pulse_on == 1) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "PW:");
        if (_pw_mode == 1) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + 62, _ly, (_pw_var != "") ? _pw_var : "<PICK>");
        } else if (_pw_edit) {
            draw_set_color(c_lime);
            draw_text(_draw_x + 62, _ly, obj_workspace_manager.current_input_string);
        } else {
            var _ph = decimal_to_hex(_pw_lit);
            while (string_length(_ph) < 3) _ph = "0" + _ph;
            draw_set_color(c_aqua);
            draw_text(_draw_x + 62, _ly, "$" + string_upper(_ph));
        }
        draw_set_color((_pw_mode == 1) ? _col_on : _col_off);
        draw_rectangle(_vx, _ly + 1, _vx + _vbtn_w, _ly + 12, false);
        draw_set_color((_pw_mode == 1) ? c_yellow : _txt_off);
        draw_set_halign(fa_center);
        draw_text(_vx + (_vbtn_w * 0.5), _ly, "VAR");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 10, _ly, "PW: -");
    }
    _ly += _lh;

    // ===== ZP =====
    var _zp_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 20);
    if (_voice_mode == 1) {
        draw_set_color(_c_lbl);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 10, _ly, "ZP:");
    if (_zp_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 46, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _zh = decimal_to_hex(_zp);
        while (string_length(_zh) < 2) _zh = "0" + _zh;
        if (_voice_mode == 1) {
            draw_set_color(c_aqua);
        } else {
            draw_set_color(_c_dim);
        }
        draw_text(_draw_x + 46, _ly, "$" + string_upper(_zh));
    }
    _ly += _lh;

    // ===== Footer =====
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    var _base_hex = decimal_to_hex(0xD400 + (_voice_mode == 0 ? _voice_lit * 7 : 0));
    while (string_length(_base_hex) < 4) _base_hex = "0" + _base_hex;
    if (_voice_mode == 1) {
        draw_text(_draw_x + 8, _ly, "SID VOICE=VAR  BASE $D400+v*7,X");
    } else {
        draw_text(_draw_x + 8, _ly, "SID V" + string(_voice_lit + 1) + "  BASE $" + string_upper(_base_hex));
    }
}