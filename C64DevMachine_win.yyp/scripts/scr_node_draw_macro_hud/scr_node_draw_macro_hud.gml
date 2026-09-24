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
    scr_node_macro_text_l(_draw_x + 10, _ly, "HUD:");
    if (_asset_name == "" || _asset_name == "[clear]") {
        draw_set_color(_c_bad);
        scr_node_macro_text_l(_draw_x + 62, _ly, "< PICK HUD >");
    } else if (_hu == noone) {
        draw_set_color(_c_bad);
        scr_node_macro_text_l(_draw_x + 62, _ly, _asset_name + " ?");
    } else {
        draw_set_color(_c_ast);
        var _disp = _asset_name;
        if (string_length(_disp) > 14) {
            _disp = string_copy(_disp, 1, 14) + "...";
        }
        scr_node_macro_text_l(_draw_x + 62, _ly, _disp);
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
    scr_node_macro_text_l(_draw_x + 10, _ly, "SCR:");
    if (_scr_edit) {
        draw_set_color(c_lime);
        scr_node_macro_text_l(_draw_x + 46, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _sh = decimal_to_hex(_scr_base);
        while (string_length(_sh) < 4) { _sh = "0" + _sh; }
        draw_set_color(c_aqua);
        scr_node_macro_text_l(_draw_x + 46, _ly, "$" + string_upper(_sh));
    }

    draw_set_color(_c_lbl);
    scr_node_macro_text_l(_draw_x + 120, _ly, "COL:");
    if (_col_edit) {
        draw_set_color(c_lime);
        scr_node_macro_text_l(_draw_x + 156, _ly, obj_workspace_manager.current_input_string);
    } else {
        var _ch = decimal_to_hex(_col_base);
        while (string_length(_ch) < 4) { _ch = "0" + _ch; }
        draw_set_color(c_aqua);
        scr_node_macro_text_l(_draw_x + 156, _ly, "$" + string_upper(_ch));
    }
    _ly += _lh;

    // ===== AUTO DRAW + WRITE COLOUR =====
    var _cbx = _draw_x + 10;
    if (_auto_draw == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    scr_macro_body_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, false);
    draw_set_color(c_gray);
    scr_macro_body_rectangle(_cbx, _ly + 1, _cbx + 12, _ly + 13, true);
    if (_auto_draw == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    scr_node_macro_text_l(_cbx + 18, _ly, "AUTO DRAW");

    var _cbx2 = _draw_x + 120;
    if (_do_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(make_color_rgb(60, 60, 60));
    }
    scr_macro_body_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, false);
    draw_set_color(c_gray);
    scr_macro_body_rectangle(_cbx2, _ly + 1, _cbx2 + 12, _ly + 13, true);
    if (_do_col == 1) {
        draw_set_color(c_lime);
    } else {
        draw_set_color(c_gray);
    }
    scr_node_macro_text_l(_cbx2 + 18, _ly, "COLOUR");
    _ly += _lh;

    // ===== WHAT IT WILL EMIT =====
    if (_hu == noone) {
        draw_set_color(_c_dim);
        scr_node_macro_text_l(_draw_x + 10, _ly, "NO HUD ASSET ASSIGNED");
        _ly += _lh;
    } else {
        var _hm = _hu.meta;
        var _cells = _hm.hud_w * _hm.hud_h;
        var _bytes = _cells;
        if (_do_col == 1) {
            _bytes = _cells * 2;
        }

        draw_set_color(_c_info);
        scr_node_macro_text_l(_draw_x + 10, _ly,
            string(_hm.hud_w) + "x" + string(_hm.hud_h) + L(" AT ") + string(_hm.hud_x) + "," + string(_hm.hud_y)
            + "   " + string(_bytes) + L(" BYTES"));
        _ly += _lh;

        // First screen address the panel touches — the number a code block
        // needs when it poking cells directly.
        var _first = (_scr_base + (_hm.hud_y * 40) + _hm.hud_x) & 0xFFFF;
        var _fh = decimal_to_hex(_first);
        while (string_length(_fh) < 4) { _fh = "0" + _fh; }
        draw_set_color(_c_dim);
        scr_node_macro_text_l(_draw_x + 10, _ly, L("TOP LEFT $") + string_upper(_fh));
        _ly += _lh;

        // ===== ENTRY POINTS =====
        var _key = "hud" + string(stable_uid) + "_";
        draw_set_color(make_color_rgb(120, 220, 160));
        scr_node_macro_text_l(_draw_x + 10, _ly, _key + "draw");
        _ly += _lh;

        var _fields = [];
        if (variable_struct_exists(_hm, "fields") && is_array(_hm.fields)) {
            _fields = _hm.fields;
        }
        var _shown = 0;
        for (var _fi = 0; _fi < array_length(_fields); _fi++) {
            if (_shown >= 4) {
                draw_set_color(_c_dim);
                scr_node_macro_text_l(_draw_x + 10, _ly, "+" + string(array_length(_fields) - _shown) + L(" MORE"));
                break;
            }
            var _f = _fields[_fi];
            var _fa = (_scr_base + ((_hm.hud_y + real(_f.fy)) * 40) + _hm.hud_x + real(_f.fx)) & 0xFFFF;
            var _fah = decimal_to_hex(_fa);
            while (string_length(_fah) < 4) { _fah = "0" + _fah; }

            if (real(_f.kind) == 0) {
                // TEXT: a position, no routine — show the address instead.
                draw_set_color(_c_dim);
                scr_node_macro_text_l(_draw_x + 10, _ly, _f.name + "  $" + string_upper(_fah));
            } else {
                draw_set_color(make_color_rgb(120, 220, 160));
                scr_node_macro_text_l(_draw_x + 10, _ly, _key + _f.name, 132);
                draw_set_color(_c_dim);
                scr_node_macro_text_l(_draw_x + 150, _ly, "A=VAL");
            }
            _ly += _lh;
            _shown += 1;
        }
    }
}

/// Keep macro body labels within the node, with optional space for a neighbour.
/// Called in the node's draw context (x already includes the drawing indent).
function scr_node_macro_text_l(_tx, _ty, _text, _limit = -1) {
    var _row_h = string_height(L(_text));
    var _va = draw_get_valign();
    scr_macro_measure_bottom(_ty + ((_va == fa_top) ? _row_h : ((_va == fa_middle) ? _row_h / 2 : 0)));
    var _align = draw_get_halign();
    var _left = x + 4;
    var _right = x + width - 4;
    var _room = _right - _tx;
    if (_align == fa_right) _room = _tx - _left;
    if (_align == fa_center) _room = 2 * min(_tx - _left, _right - _tx);
    if (_limit >= 0) _room = min(_room, _limit);
    if (_room <= 0) return;
    var _label = L(_text);
    var _scale = 1;
    var _text_width = string_width(_label);
    if (_text_width > _room) {
        // Slightly smaller text first; abbreviate extreme names instead of
        // squeezing them into unreadably narrow lettering. Source stays intact.
        _scale = max(0.85, _room / max(1, _text_width));
        if (_text_width * _scale > _room) {
            while (string_length(_label) > 0 && string_width(_label + "...") * _scale > _room) {
                _label = string_delete(_label, string_length(_label), 1);
            }
            _label += "...";
            if (string_width(_label) * _scale > _room) return;
        }
    }
    draw_text_transformed(_tx, _ty - scr_lang_lift() * _scale, _label, _scale, _scale, 0);
}



/// Commit only real layout changes. Also correct heights restored by undo/load.
function scr_macro_apply_height(_n, _wanted) {
    _wanted = max(40, ceil(_wanted / 20) * 20);
    _n.macro_layout_type = _n.node_type;
    _n.macro_layout_height = _wanted;
    if (_n.height != _wanted || _n.cached_height != _wanted) {
        _n.height = _wanted;
        _n.cached_height = _wanted;
        _n.height_dirty = true;
        global.addresses_dirty = true;
    }
}

/// Run before culling/input: HUD asset edits also resize off-screen nodes.
function scr_macro_sync_height(_n) {
    if (_n.node_type == "MACRO_HUD") {
        var _name = "";
        if (array_length(_n.instructions) > 0 && array_length(_n.instructions[0]) > 1)
            _name = string(_n.instructions[0][1]);
        var _rows = 4; // asset, addresses, toggles, empty-state message
        if (_name != "" && instance_exists(obj_asset_manager)) {
            var _assets = obj_asset_manager.asset_list;
            for (var _i = 0; _i < ds_list_size(_assets); _i++) {
                var _a = ds_list_find_value(_assets, _i);
                if (_a.type != "HUD" || _a.name != _name) continue;
                var _fields = 0;
                if (variable_struct_exists(_a.meta, "fields") && is_array(_a.meta.fields))
                    _fields = array_length(_a.meta.fields);
                // Three controls + size, address and draw routine; four fields
                // maximum, followed by a MORE row when there are extra fields.
                _rows = 6 + min(4, _fields) + ((_fields > 4) ? 1 : 0);
                break;
            }
        }
        scr_macro_apply_height(_n, 28 + _rows * 14 + 6);
    } else if (variable_instance_exists(_n, "macro_layout_height")
    && _n.macro_layout_type == _n.node_type) {
        scr_macro_apply_height(_n, _n.macro_layout_height);
    }
}

/// Observe content only, never node backgrounds or height-anchored footers.
function scr_macro_measure_bottom(_bottom) {
    if (variable_instance_exists(id, "macro_measure_active") && macro_measure_active)
        macro_content_bottom = max(macro_content_bottom, _bottom - y);
}

function scr_macro_body_rectangle(_x1, _y1, _x2, _y2, _outline) {
    scr_macro_measure_bottom(max(_y1, _y2));
    draw_rectangle(_x1, _y1, _x2, _y2, _outline);
}

function scr_macro_body_line(_x1, _y1, _x2, _y2) {
    scr_macro_measure_bottom(max(_y1, _y2));
    draw_line(_x1, _y1, _x2, _y2);
}

function scr_macro_body_transformed_text(_tx, _ty, _text, _sx, _sy, _angle) {
    // Existing transformed macro labels are unrotated and retain their sizing.
    var _h = string_height(L(_text)) * abs(_sy);
    var _va = draw_get_valign();
    scr_macro_measure_bottom(_ty + ((_va == fa_top) ? _h : ((_va == fa_middle) ? _h / 2 : 0)));
    draw_text_transformed_l(_tx, _ty, _text, _sx, _sy, _angle);
}
