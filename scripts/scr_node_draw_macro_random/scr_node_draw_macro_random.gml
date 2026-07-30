/// @desc scr_node_draw_macro_random(_draw_x, _y)
/// instructions[0]: ["macro_random",
///   1 init_osc, 2 freq, 3 clamp_on,
///   4 clamp_min, 5 clamp_max,
///   6 dst_mode(0=A,1=VAR), 7 dst_var, 8 zp_base]

function scr_node_draw_macro_random(_draw_x, _y) {

    var _ins = instructions[0];

    var _init_osc = 1;
    if (array_length(_ins) > 1 && is_real(_ins[1])) { _init_osc = real(_ins[1]); }

    var _freq = 0xFFFF;
    if (array_length(_ins) > 2 && is_real(_ins[2])) { _freq = real(_ins[2]) & 0xFFFF; }

    var _clamp_on = 0;
    if (array_length(_ins) > 3 && is_real(_ins[3])) { _clamp_on = real(_ins[3]); }

    var _clamp_min = 0;
    if (array_length(_ins) > 4 && is_real(_ins[4])) { _clamp_min = real(_ins[4]) & 0xFF; }

    var _clamp_max = 255;
    if (array_length(_ins) > 5 && is_real(_ins[5])) { _clamp_max = real(_ins[5]) & 0xFF; }

    var _dst_mode = 0;
    if (array_length(_ins) > 6 && is_real(_ins[6])) { _dst_mode = real(_ins[6]); }

    var _dst_var = "";
    if (array_length(_ins) > 7) { _dst_var = string(_ins[7]); }

    var _zp = 0xFB;
    if (array_length(_ins) > 8 && is_real(_ins[8])) { _zp = real(_ins[8]) & 0xFF; }

    var _lh = 14;
    var _ly = _y + 28;

    var _c_lbl = make_color_rgb(140, 160, 200);
    var _c_dim = make_color_rgb(90, 90, 100);

    draw_set_font(fnt_c64_tiny);

    // ── Row 0: INIT OSC checkbox ──
    var _cbx = _draw_x + 10;
    if (_init_osc == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_init_osc == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx + 18, _ly, "SETUP NOISE OSC");
    _ly += _lh;

    // ── Row 1: FREQ hex ──
    var _freq_edit = (obj_workspace_manager.is_entering_text &&
                      obj_workspace_manager.input_target_node  == id &&
                      obj_workspace_manager.input_target_index == 2);
    if (_init_osc == 1) {
        draw_set_color(_c_lbl);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 10, _ly, "FREQ:");
    if (_freq_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 58, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _fq_hex = decimal_to_hex(_freq);
        while (string_length(_fq_hex) < 4) _fq_hex = "0" + _fq_hex;
        if (_init_osc == 1) {
            draw_set_color(c_aqua);
        } else {
            draw_set_color(_c_dim);
        }
        draw_text(_draw_x + 58, _ly, "$" + string_upper(_fq_hex));
    }
    _ly += _lh;

    // ── Row 2: CLAMP checkbox ──
    var _cbx2 = _draw_x + 10;
    if (_clamp_on == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, true);
    if (_clamp_on == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text(_cbx2 + 18, _ly, "CLAMP RANGE");
    _ly += _lh;

    // ── Row 3: MIN / MAX ──
    var _min_edit = (obj_workspace_manager.is_entering_text &&
                     obj_workspace_manager.input_target_node  == id &&
                     obj_workspace_manager.input_target_index == 4);
    var _max_edit = (obj_workspace_manager.is_entering_text &&
                     obj_workspace_manager.input_target_node  == id &&
                     obj_workspace_manager.input_target_index == 5);
    if (_clamp_on == 1) {
        draw_set_color(_c_lbl);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 10, _ly, "MIN:");
    if (_min_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, obj_workspace_manager.current_input_string);
    } else {
        if (_clamp_on == 1) {
            draw_set_color(c_aqua);
        } else {
            draw_set_color(_c_dim);
        }
        draw_text(_draw_x + 52, _ly, string(_clamp_min));
    }
    if (_clamp_on == 1) {
        draw_set_color(_c_lbl);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 118, _ly, "MAX:");
    if (_max_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 160, _ly, obj_workspace_manager.current_input_string);
    } else {
        if (_clamp_on == 1) {
            draw_set_color(c_aqua);
        } else {
            draw_set_color(_c_dim);
        }
        draw_text(_draw_x + 160, _ly, string(_clamp_max));
    }
    _ly += _lh;

    // ── Row 4: DEST toggle A / VAR ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "DEST:");
    var _ax0 = _draw_x + 58;
    if (_dst_mode == 0) {
        draw_set_color(make_color_rgb(30, 120, 60));
    } else {
        draw_set_color(make_color_rgb(45, 45, 55));
    }
    draw_rectangle(_ax0, _ly + 4, _ax0 + 28, _ly + 15, false);
    if (_dst_mode == 0) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(130, 130, 150));
    }
    draw_set_halign(fa_center);
    draw_text(_ax0 + 14, _ly, "A");
    var _vx0 = _draw_x + 92;
    if (_dst_mode == 1) {
        draw_set_color(make_color_rgb(30, 120, 60));
    } else {
        draw_set_color(make_color_rgb(45, 45, 55));
    }
    draw_rectangle(_vx0, _ly + 4, _vx0 + 48, _ly + 15, false);
    if (_dst_mode == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(130, 130, 150));
    }
    draw_text(_vx0 + 24, _ly, "VAR");
    draw_set_halign(fa_left);
    _ly += _lh;

    // ── Row 5: DEST VAR picker ──
    if (_dst_mode == 1) {
        draw_set_color(_c_lbl);
        draw_text(_draw_x + 10, _ly, "-> VAR:");
        if (_dst_var != "") {
            draw_set_color(c_lime);
            draw_text(_draw_x + 66, _ly, _dst_var);
        } else {
            draw_set_color(c_orange);
            draw_text(_draw_x + 66, _ly, "-pick var-");
        }
    } else {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 10, _ly, "-> A (accumulator)");
    }
    _ly += _lh;

    // ── Row 6: ZP ──
    var _zp_edit = (obj_workspace_manager.is_entering_text &&
                    obj_workspace_manager.input_target_node  == id &&
                    obj_workspace_manager.input_target_index == 8);
    if (_clamp_on == 1) {
        draw_set_color(_c_lbl);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 10, _ly, "ZP:");
    if (_zp_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 46, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _zp_hex = decimal_to_hex(_zp);
        while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;
        if (_clamp_on == 1) {
            draw_set_color(c_aqua);
        } else {
            draw_set_color(_c_dim);
        }
        draw_text(_draw_x + 46, _ly, "$" + string_upper(_zp_hex));
    }
    _ly += _lh;

    // ── Footer ──
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    var _dst_txt = "-> A";
    if (_dst_mode == 1) {
        if (_dst_var != "") {
            _dst_txt = "-> " + _dst_var;
        } else {
            _dst_txt = "-> (pick var)";
        }
    }
    if (_clamp_on == 1) {
        draw_text(_draw_x + 8, _ly, "RND $D41B  [" + string(_clamp_min) + ".." + string(_clamp_max) + "]  " + _dst_txt);
    } else {
        draw_text(_draw_x + 8, _ly, "RND $D41B  0..255  " + _dst_txt);
    }
}