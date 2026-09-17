/// @desc scr_node_draw_macro_hud(_draw_x, _y)
/// instructions[0]: ["macro_hud",
///   1 asset_name, 2 screen_base, 3 colour_base, 4 auto_draw, 5 write_colour]
///
/// The HUD asset carries the picture and the field list; this node says where
/// on the machine it lands and reports the entry points it will publish, so a
/// code block can be written against them before the first build.
function scr_node_draw_macro_hud(_draw_x, _y) {

    var _ins = instructions[0];

    var _asset_name = "";
    if (array_length(_ins) > 1) {
        _asset_name = string(_ins[1]);
    }
    var _scr_base = 0x0400;
    if (array_length(_ins) > 2 && is_real(_ins[2])) {
        _scr_base = real(_ins[2]) & 0xFFFF;
    }
    var _col_base = 0xD800;
    if (array_length(_ins) > 3 && is_real(_ins[3])) {
        _col_base = real(_ins[3]) & 0xFFFF;
    }
    var _auto_draw = 0;
    if (array_length(_ins) > 4 && is_real(_ins[4])) {
        _auto_draw = real(_ins[4]);
    }
    var _do_col = 1;
    if (array_length(_ins) > 5 && is_real(_ins[5])) {
        _do_col = real(_ins[5]);
    }

    var _lh = 14;
    var _ly = _y + 28;

    var _c_lbl  = make_color_rgb(140, 160, 200);
    var _c_dim  = make_color_rgb(90, 90, 100);
    var _c_ast  = make_color_rgb(255, 190, 90);
    var _c_bad  = make_color_rgb(230, 90, 90);
    var _c_info = make_color_rgb(80, 150, 140);

    draw_set_font_l(fnt_c64_tiny);

    // ── Resolve the asset so the node can report real numbers ──
    var _hu = noone;
    if (_asset_name != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "HUD" && _a.name == _asset_name) {
                _hu = _a;
                break;
            }
        }
    }

    // ===== HUD asset picker =====
    draw_set_color(_c_lbl);
    draw_text_l(_draw_x + 10, _ly, "HUD:");
    if (_asset_name == "" || _asset_name == "[clear]") {
        draw_set_color(_c_bad);
        draw_text_l(_draw_x + 62, _ly, "< PICK HUD >");
    } else if (_hu == noone) {
        draw_set_color(_c_bad);
        draw_text_l(_draw_x + 62, _ly, _asset_name + " ?");
    } else {
        draw_set_color(_c_ast);
        var _disp = _asset_name;
        if (string_length(_disp) > 14) {
            _disp = string_copy(_disp, 1, 14) + "...";
        }
        draw_text_l(_draw_x + 62, _ly, _disp);
    }
    _ly += _lh;

    // ===== SCREEN / COLOUR base =====
    var _scr_edit = (obj_workspace_manager.is_entering_text &&
                     obj_workspace_manager.input_target_node  == id &&
                     obj_workspace_manager.input_target_index == 2);
    var _col_edit = (obj_workspace_manager.is_entering_text &&
                     obj_workspace_manager.input_target_node  == id &&
                     obj_workspace_manager.input_target_index == 3);

    draw_set_color(_c_lbl);
    draw_text_l(_draw_x + 10, _ly, "SCR:");
    if (_scr_edit) {
        draw_set_color(c_lime);
        draw_text_l(_draw_x + 46, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _sh = decimal_to_hex(_scr_base);
        while (string_length(_sh) < 4) { _sh = "0" + _sh; }
        draw_set_color(c_aqua);
        draw_text_l(_draw_x + 46, _ly, "$" + string_upper(_sh));
    }

    draw_set_color(_c_lbl);
    draw_text_l(_draw_x + 120, _ly, "COL:");
    if (_col_edit) {
        draw_set_color(c_lime);
        draw_text_l(_draw_x + 156, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _ch = decimal_to_hex(_col_base);
        while (string_length(_ch) < 4) { _ch = "0" + _ch; }
        draw_set_color(c_aqua);
        draw_text_l(_draw_x + 156, _ly, "$" + string_upper(_ch));
    }
    _ly += _lh;

    // ===== AUTO DRAW + WRITE COLOUR =====
    var _cbx = _draw_x + 10;
    if (_auto_draw == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_auto_draw == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text_l(_cbx + 18, _ly, "AUTO DRAW");

    var _cbx2 = _draw_x + 120;
    if (_do_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    draw_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, true);
    if (_do_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    draw_text_l(_cbx2 + 18, _ly, "COLOUR");
    _ly += _lh;

    // ===== WHAT IT WILL EMIT =====
    if (_hu == noone) {
        draw_set_color(_c_dim);
        draw_text_l(_draw_x + 10, _ly, "NO HUD ASSET - NOTHING EMITTED");
        _ly += _lh;
    } else {
        var _hm = _hu.meta;
        var _cells = _hm.hud_w * _hm.hud_h;
        var _bytes = _cells;
        if (_do_col == 1) {
            _bytes = _cells * 2;
        }

        draw_set_color(_c_info);
        draw_text_l(_draw_x + 10, _ly,
            string(_hm.hud_w) + "x" + string(_hm.hud_h) + L(" AT ") + string(_hm.hud_x) + "," + string(_hm.hud_y)
            + "   " + string(_bytes) + L(" BYTES"));
        _ly += _lh;

        // First screen address the panel touches — the number a code block
        // needs when it poking cells directly.
        var _first = (_scr_base + (_hm.hud_y * 40) + _hm.hud_x) & 0xFFFF;
        var _fh = decimal_to_hex(_first);
        while (string_length(_fh) < 4) { _fh = "0" + _fh; }
        draw_set_color(_c_dim);
        draw_text_l(_draw_x + 10, _ly, L("TOP LEFT $") + string_upper(_fh));
        _ly += _lh;

        // ===== ENTRY POINTS =====
        var _key = "hud" + string(stable_uid) + "_";
        draw_set_color(make_color_rgb(120, 220, 160));
        draw_text_l(_draw_x + 10, _ly, _key + "draw");
        _ly += _lh;

        var _fields = [];
        if (variable_struct_exists(_hm, "fields") && is_array(_hm.fields)) {
            _fields = _hm.fields;
        }
        var _shown = 0;
        for (var _fi = 0; _fi < array_length(_fields); _fi++) {
            if (_shown >= 4) {
                draw_set_color(_c_dim);
                draw_text_l(_draw_x + 10, _ly, "+" + string(array_length(_fields) - _shown) + L(" MORE"));
                break;
            }
            var _f = _fields[_fi];
            var _fa = (_scr_base + ((_hm.hud_y + real(_f.fy)) * 40) + _hm.hud_x + real(_f.fx)) & 0xFFFF;
            var _fah = decimal_to_hex(_fa);
            while (string_length(_fah) < 4) { _fah = "0" + _fah; }

            if (real(_f.kind) == 0) {
                // TEXT: a position, no routine — show the address instead.
                draw_set_color(_c_dim);
                draw_text_l(_draw_x + 10, _ly, _f.name + "  $" + string_upper(_fah));
            } else {
                draw_set_color(make_color_rgb(120, 220, 160));
                draw_text_l(_draw_x + 10, _ly, _key + _f.name);
                draw_set_color(_c_dim);
                draw_text_l(_draw_x + 150, _ly, "A=VAL");
            }
            _ly += _lh;
            _shown += 1;
        }
    }
}
