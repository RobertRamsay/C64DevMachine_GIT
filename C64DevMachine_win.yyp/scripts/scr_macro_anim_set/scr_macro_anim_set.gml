/// ====================================================================
/// MACRO_ANIM_SET — several animation sequences sharing ONE player.
///
/// Where MACRO_ANIM compiles a full player per node, ANIM SET compiles one
/// player plus flat tables. A SELECT byte picks the row to play; when it
/// changes, the new row restarts from its first frame automatically, so
/// no hand-written reset stubs are needed.
///
/// instructions[0] layout (flat, single row, so every generic system that
/// only looks at instructions[0] keeps working):
///   [0] "macro_anim_set"
///   [1] SELECT source — "$02C8", "712" or a variable name. "" = row 0 always
///   [2] slot count shown in the editor (1..8)
///   [3] reserved
///   row r starts at 4 + r * 12:
///     +0 name   +1 delay (1..255)   +2 loop "1"/"0"
///     +3..+10 frame list per sprite slot 0..7 ("0,16,32,48")   +11 reserved
///
/// Entry labels: <alias>_sub (call once per frame), <alias>_reset (restart
/// the current row on the next call). <alias>_done reads 1 once a one-shot
/// row has reached its last frame.
/// ====================================================================

#macro ANIMSET_HDR     4
#macro ANIMSET_STRIDE  12
#macro ANIMSET_MAXROWS 32

function scr_anim_set_row_count(_n) {
    var _len = array_length(_n.instructions[0]);
    if (_len <= ANIMSET_HDR) return 0;
    return floor((_len - ANIMSET_HDR) / ANIMSET_STRIDE);
}

function scr_anim_set_new_row(_name) {
    return [_name, 8, "1", "", "", "", "", "", "", "", "", ""];
}

function scr_anim_set_add_row(_n) {
    var _rows = scr_anim_set_row_count(_n);
    if (_rows >= ANIMSET_MAXROWS) return;
    var _row = scr_anim_set_new_row("SEQ" + string(_rows));
    for (var _i = 0; _i < ANIMSET_STRIDE; _i++) {
        array_push(_n.instructions[0], _row[_i]);
    }
}

function scr_anim_set_delete_row(_n, _r) {
    var _rows = scr_anim_set_row_count(_n);
    if (_rows <= 1) return;
    array_delete(_n.instructions[0], ANIMSET_HDR + _r * ANIMSET_STRIDE, ANIMSET_STRIDE);
}

function scr_anim_set_slot_count(_n) {
    var _v = _n.instructions[0][2];
    if (!is_real(_v)) {
        _v = real(string_digits(string(_v)) + "0") / 10;
    }
    return clamp(floor(_v), 1, 8);
}

function scr_anim_set_alias(_n) {
    if (_n.anim_alias == "") {
        _n.anim_alias = "aset" + string(real(_n.id));
    }
    return _n.anim_alias;
}

/// Parse "0,16,-8,$10" into an array of bytes.
function scr_anim_set_parse_list(_s) {
    var _out = [];
    _s = string(_s);
    if (_s == "") return _out;
    var _parts = string_split(_s, ",");
    for (var _i = 0; _i < array_length(_parts); _i++) {
        var _t = string_replace_all(_parts[_i], " ", "");
        if (_t == "") continue;
        var _v = 0;
        if (string_char_at(_t, 1) == "$") {
            _v = hex_to_decimal(string_delete(_t, 1, 1));
        } else {
            _v = scr_safe_num(_t);
        }
        array_push(_out, _v & 0xFF);
    }
    return _out;
}

/// Height of the node body in pixels, snapped to the 20px grid.
function scr_anim_set_height(_n) {
    var _px = 82 + scr_anim_set_row_count(_n) * 36 + 60;
    return ceil(_px / 20) * 20;
}

// --------------------------------------------------------------------
// DRAW
// --------------------------------------------------------------------
function scr_node_draw_macro_anim_set(_draw_x) {
    var _alias  = scr_anim_set_alias(id);
    var _rows   = scr_anim_set_row_count(id);
    var _slots  = scr_anim_set_slot_count(id);
    var _fld_h  = 16;
    var _lbl_x  = _draw_x + 6;
    var _x2     = _draw_x + width - 6;

    // ---- SELECT + SLOTS ----
    var _sy = y + 28;
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(160, 160, 160));
    scr_node_macro_text_l(_lbl_x, _sy, "SELECT:");
    var _sel = string(instructions[0][1]);
    var _sel_show = _sel;
    if (_sel == "") {
        _sel_show = "(ROW 0)";
    }
    scr_anim_set_draw_box(_draw_x + 54, _sy, _draw_x + 130, _sy + _fld_h, _sel_show, c_yellow);
    draw_set_color(make_color_rgb(160, 160, 160));
    scr_node_macro_text_l(_draw_x + 136, _sy, "SLOTS");
    scr_anim_set_draw_box(_draw_x + 172, _sy, _x2, _sy + _fld_h, string(_slots), c_lime);

    // ---- ALIAS ----
    var _ay = y + 48;
    draw_set_color(make_color_rgb(160, 160, 160));
    scr_node_macro_text_l(_lbl_x, _ay, "ALIAS:");
    scr_anim_set_draw_box(_draw_x + 54, _ay, _x2, _ay + _fld_h, _alias, make_color_rgb(120, 220, 255));

    // ---- Column header ----
    draw_set_font_l(fnt_c64_nano);
    draw_set_color(make_color_rgb(140, 140, 140));
    scr_node_macro_text_l(_lbl_x, y + 70, "#  NAME               DLY  LOOP");

    // ---- Rows ----
    var _box_gap = 2;
    var _box_w   = (width - 8 - (_slots - 1) * _box_gap) / _slots;
    for (var _r = 0; _r < _rows; _r++) {
        var _b  = ANIMSET_HDR + _r * ANIMSET_STRIDE;
        var _ry = y + 82 + _r * 36;

        draw_set_font_l(fnt_c64_nano);
        draw_set_color(c_gray);
        scr_node_macro_text_l(_lbl_x, _ry + 3, string(_r));

        scr_anim_set_draw_box(_draw_x + 18, _ry, _draw_x + 110, _ry + _fld_h, string(instructions[0][_b]), c_white);
        scr_anim_set_draw_box(_draw_x + 114, _ry, _draw_x + 142, _ry + _fld_h, string(instructions[0][_b + 1]), c_lime);

        // Loop checkbox
        var _loop_on = (string(instructions[0][_b + 2]) == "1");
        var _cbx = _draw_x + 150;
        var _cby = _ry + 3;
        if (_loop_on) {
            draw_set_color(make_color_rgb(60, 160, 60));
        } else {
            draw_set_color(make_color_rgb(40, 40, 40));
        }
        scr_macro_body_rectangle(_cbx, _cby, _cbx + 10, _cby + 10, false);
        draw_set_color(make_color_rgb(90, 90, 90));
        scr_macro_body_rectangle(_cbx, _cby, _cbx + 10, _cby + 10, true);

        // Delete row
        if (_rows > 1) {
            var _dx = _x2 - 12;
            var _dhov = point_in_rectangle(mouse_x, mouse_y, _dx, _ry + 2, _dx + 12, _ry + 14);
            if (_dhov) {
                draw_set_color(c_red);
            } else {
                draw_set_color(make_color_rgb(140, 60, 60));
            }
            draw_set_font_l(fnt_c64_tiny);
            scr_node_macro_text_l(_dx + 2, _ry, "X");
        }

        // Slot frame boxes
        var _sy2 = _ry + 18;
        for (var _si = 0; _si < _slots; _si++) {
            var _bx1 = _draw_x + 4 + _si * (_box_w + _box_gap);
            var _txt = string(instructions[0][_b + 3 + _si]);
            if (_txt == "") {
                _txt = "S" + string(_si) + " -";
            }
            scr_anim_set_draw_box(_bx1, _sy2, _bx1 + _box_w, _sy2 + 14, _txt, make_color_rgb(140, 230, 140));
        }
    }

    // ---- + ROW ----
    var _by = y + 82 + _rows * 36 + 2;
    var _bhov = point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _by, _draw_x + 70, _by + 14);
    if (_bhov) {
        draw_set_color(make_color_rgb(60, 110, 200));
    } else {
        draw_set_color(make_color_rgb(20, 60, 110));
    }
    scr_macro_body_rectangle(_draw_x + 4, _by, _draw_x + 70, _by + 14, false);
    draw_set_color(c_white);
    draw_set_font_l(fnt_c64_tiny);
    scr_node_macro_text_l(_draw_x + 12, _by, "+ ROW");

    // ---- Entry labels ----
    var _fy = _by + 20;
    draw_set_color(make_color_rgb(60, 160, 180));
    scr_node_macro_text_l(_lbl_x, _fy, "JSR:");
    draw_set_color(c_yellow);
    scr_node_macro_text_l(_draw_x + 54, _fy, _alias + "_sub");
    draw_set_color(make_color_rgb(180, 100, 60));
    scr_node_macro_text_l(_lbl_x, _fy + 14, "RST:");
    draw_set_color(c_yellow);
    scr_node_macro_text_l(_draw_x + 54, _fy + 14, _alias + "_reset");
}

function scr_anim_set_draw_box(_x1, _y1, _x2, _y2, _txt, _col) {
    var _hov = point_in_rectangle(mouse_x, mouse_y, _x1, _y1, _x2, _y2);
    if (_hov) {
        draw_set_color(make_color_rgb(40, 55, 40));
    } else {
        draw_set_color(make_color_rgb(22, 32, 22));
    }
    scr_macro_body_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(60, 100, 60));
    scr_macro_body_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_font_l(fnt_c64_nano);
    draw_set_color(_col);
    draw_set_halign(fa_center);
    var _w  = string_width_l(_txt);
    var _sc = 1;
    if (_w > (_x2 - _x1 - 4)) {
        _sc = (_x2 - _x1 - 4) / _w;
    }
    scr_macro_body_transformed_text((_x1 + _x2) * 0.5, _y1 + 2, _txt, _sc, 1, 0);
    draw_set_halign(fa_left);
}

// --------------------------------------------------------------------
// STEP (left click)
// --------------------------------------------------------------------
function scr_anim_set_open_field(_n, _idx, _text) {
    with (obj_workspace_manager) {
        is_entering_text     = true;
        input_target_node    = _n;
        input_target_index   = _idx;
        current_input_string = _text;
        keyboard_string      = "";
        cursor_pos           = string_length(current_input_string);
    }
}

function scr_node_step_macro_anim_set(_draw_x) {
    var _rows  = scr_anim_set_row_count(id);
    var _slots = scr_anim_set_slot_count(id);
    var _fld_h = 16;
    var _x2    = _draw_x + width - 6;

    var _sy = y + 28;
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 54, _sy, _draw_x + 130, _sy + _fld_h)) {
        scr_anim_set_open_field(id, 1, string(instructions[0][1]));
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 172, _sy, _x2, _sy + _fld_h)) {
        scr_anim_set_open_field(id, 2, string(_slots));
        exit;
    }
    var _ay = y + 48;
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 54, _ay, _x2, _ay + _fld_h)) {
        scr_anim_set_open_field(id, -50, scr_anim_set_alias(id));
        exit;
    }

    var _box_gap = 2;
    var _box_w   = (width - 8 - (_slots - 1) * _box_gap) / _slots;
    for (var _r = 0; _r < _rows; _r++) {
        var _b  = ANIMSET_HDR + _r * ANIMSET_STRIDE;
        var _ry = y + 82 + _r * 36;

        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 18, _ry, _draw_x + 110, _ry + _fld_h)) {
            scr_anim_set_open_field(id, _b, string(instructions[0][_b]));
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 114, _ry, _draw_x + 142, _ry + _fld_h)) {
            scr_anim_set_open_field(id, _b + 1, string(instructions[0][_b + 1]));
            exit;
        }
        var _cbx = _draw_x + 150;
        if (point_in_rectangle(mouse_x, mouse_y, _cbx, _ry + 3, _cbx + 10, _ry + 13)) {
            scr_undo_snapshot();
            if (string(instructions[0][_b + 2]) == "1") {
                instructions[0][_b + 2] = "0";
            } else {
                instructions[0][_b + 2] = "1";
            }
            global.addresses_dirty = true;
            exit;
        }
        if (_rows > 1) {
            var _dx = _x2 - 12;
            if (point_in_rectangle(mouse_x, mouse_y, _dx, _ry + 2, _dx + 12, _ry + 14)) {
                scr_undo_snapshot();
                scr_anim_set_delete_row(id, _r);
                height_dirty = true;
                global.addresses_dirty = true;
                global.relayout_frames = max(global.relayout_frames, 3);
                exit;
            }
        }
        var _sy2 = _ry + 18;
        for (var _si = 0; _si < _slots; _si++) {
            var _bx1 = _draw_x + 4 + _si * (_box_w + _box_gap);
            if (point_in_rectangle(mouse_x, mouse_y, _bx1, _sy2, _bx1 + _box_w, _sy2 + 14)) {
                scr_anim_set_open_field(id, _b + 3 + _si, string(instructions[0][_b + 3 + _si]));
                exit;
            }
        }
    }

    var _by = y + 82 + _rows * 36 + 2;
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _by, _draw_x + 70, _by + 14)) {
        scr_undo_snapshot();
        scr_anim_set_add_row(id);
        height_dirty = true;
        global.addresses_dirty = true;
        global.relayout_frames = max(global.relayout_frames, 3);
        exit;
    }
    exit;
}

// --------------------------------------------------------------------
// COMMIT (called first thing from scr_node_commit)
// --------------------------------------------------------------------
function scr_anim_set_commit(_t, _idx, _input) {
    _input = string_trim(string(_input));

    if (_idx == -50) {
        // Alias: label-safe characters only
        var _clean = "";
        for (var _i = 1; _i <= string_length(_input); _i++) {
            var _ch = string_char_at(_input, _i);
            var _o  = ord(_ch);
            if ((_o >= 48 && _o <= 57) || (_o >= 65 && _o <= 90) || (_o >= 97 && _o <= 122) || _ch == "_") {
                _clean += _ch;
            }
        }
        if (_clean != "") {
            _t.anim_alias = _clean;
        }
    } else if (_idx == 1) {
        _t.instructions[0][1] = string_upper(_input);
    } else if (_idx == 2) {
        var _d = string_digits(_input);
        var _v = 2;
        if (_d != "") {
            _v = real(_d);
        }
        _t.instructions[0][2] = clamp(_v, 1, 8);
    } else if (_idx >= ANIMSET_HDR && _idx < array_length(_t.instructions[0])) {
        var _field = (_idx - ANIMSET_HDR) mod ANIMSET_STRIDE;
        if (_field == 0) {
            _t.instructions[0][_idx] = string_upper(_input);
        } else if (_field == 1) {
            var _d2 = string_digits(_input);
            var _v2 = 8;
            if (_d2 != "") {
                _v2 = real(_d2);
            }
            _t.instructions[0][_idx] = clamp(_v2, 1, 255);
        } else if (_field >= 3 && _field <= 10) {
            var _keep = "";
            for (var _j = 1; _j <= string_length(_input); _j++) {
                var _c = string_char_at(_input, _j);
                if ((_c >= "0" && _c <= "9") || _c == "-" || _c == "," || _c == "$" ||
                    (string_upper(_c) >= "A" && string_upper(_c) <= "F")) {
                    _keep += string_upper(_c);
                }
            }
            _t.instructions[0][_idx] = _keep;
        }
    }
    _t.height_dirty = true;
    global.addresses_dirty = true;
}

// --------------------------------------------------------------------
// POINTER RESOLUTION — mirrors MACRO_ANIM exactly (copied, not shared,
// so MACRO_ANIM output stays byte-identical for existing projects).
// Returns { ptr: [8], alt: [8], base: n }
// --------------------------------------------------------------------
function scr_anim_set_resolve_ptrs(_id) {
    var _slot_ptr     = array_create(8, -1);
    var _slot_ptr_alt = array_create(8, -1);

    var _has_scroll = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SCROLL" && is_connected) {
            _has_scroll = true;
            break;
        }
    }

    var _org = _id.org_parent;
    with (obj_c64_node) {
        if (node_type != "MACRO_SPR" || !is_connected) continue;
        if (org_parent != _org) continue;
        var _sslot = 0;
        if (is_real(instructions[0][2])) {
            _sslot = real(instructions[0][2]);
        }
        if (_sslot < 0 || _sslot >= 8) continue;

        var _sn_asset   = string(instructions[0][1]);
        var _bank_addr  = 0x2800;
        var _screen_ram = -1;
        if (instance_exists(obj_asset_manager) && _sn_asset != "") {
            var _am2 = obj_asset_manager;
            for (var _ai2 = 0; _ai2 < ds_list_size(_am2.asset_list); _ai2++) {
                var _a2 = ds_list_find_value(_am2.asset_list, _ai2);
                if (_a2.type == "SPRITE_SET" && _a2.name == _sn_asset) {
                    _bank_addr = _a2.address;
                    if (variable_struct_exists(_a2.meta, "screen_ram")) {
                        _screen_ram = _a2.meta.screen_ram;
                    }
                    break;
                }
            }
        }
        var _map_wins = false;
        if ((_bank_addr >> 14) == 0) {
            with (obj_c64_node) {
                if (is_connected && (node_type == "MACRO_VIC" || node_type == "MACRO_MAP")) {
                    _map_wins = true;
                    break;
                }
            }
        }
        if (_screen_ram == -1 && _map_wins) {
            _screen_ram = 0x0400;
        }
        if (_screen_ram == -1) {
            with (obj_c64_node) {
                if (node_type == "MACRO_BMP" && is_connected) {
                    var _ba = 0x4000;
                    if (is_real(instructions[0][2])) {
                        _ba = real(instructions[0][2]);
                    }
                    var _bbk  = floor(_ba / 0x4000);
                    var _bscr = _ba + 0x2000;
                    if (_bbk == 2) _bscr = _bbk * 0x4000 + 0x3C00;
                    if (_bbk == 3) _bscr = _bbk * 0x4000 + 0x0400;
                    _screen_ram = _bscr;
                    break;
                }
            }
        }
        if (_screen_ram == -1) {
            _screen_ram = (_bank_addr >> 14) * 0x4000 + 0x0400;
        }
        _slot_ptr[_sslot] = _screen_ram + 0x03F8 + _sslot;

        if (_has_scroll) {
            if (_screen_ram == 0x0400) {
                _slot_ptr_alt[_sslot] = 0x0C00 + 0x03F8 + _sslot;
            } else if (_screen_ram == 0x0C00) {
                _slot_ptr_alt[_sslot] = 0x0400 + 0x03F8 + _sslot;
            } else {
                _slot_ptr[_sslot]     = 0x0400 + 0x03F8 + _sslot;
                _slot_ptr_alt[_sslot] = 0x0C00 + 0x03F8 + _sslot;
            }
        }
    }

    // Base pointer value from the slot-0 MACRO_SPR asset (same rule as MACRO_ANIM)
    var _vic_bank  = -1;
    var _base_addr = -1;
    with (obj_c64_node) {
        if (node_type == "MACRO_SPR" && is_connected) {
            var _sslot2 = 0;
            if (is_real(instructions[0][2])) {
                _sslot2 = real(instructions[0][2]);
            }
            if (_sslot2 == 0) {
                var _sn2 = string(instructions[0][1]);
                if (instance_exists(obj_asset_manager) && _sn2 != "") {
                    var _am3 = obj_asset_manager;
                    for (var _ai3 = 0; _ai3 < ds_list_size(_am3.asset_list); _ai3++) {
                        var _a3 = ds_list_find_value(_am3.asset_list, _ai3);
                        if (_a3.type == "SPRITE_SET" && _a3.name == _sn2) {
                            _vic_bank  = _a3.address >> 14;
                            _base_addr = _a3.address;
                            break;
                        }
                    }
                }
                break;
            }
        }
    }
    var _base_map_wins = false;
    if (_vic_bank == 0) {
        with (obj_c64_node) {
            if (is_connected && (node_type == "MACRO_VIC" || node_type == "MACRO_MAP")) {
                _base_map_wins = true;
                break;
            }
        }
    }
    var _base_ptr_val = 0xA0;
    if (_base_addr >= 0) {
        if (_base_map_wins) {
            _base_ptr_val = _base_addr / 64;
        } else {
            _base_ptr_val = (_base_addr - (_vic_bank * 0x4000)) / 64;
        }
    }

    return { ptr: _slot_ptr, alt: _slot_ptr_alt, base: _base_ptr_val & 0xFF };
}

// --------------------------------------------------------------------
// CODEGEN — called from scr_compile_chain's MACRO_ANIM_SET case
// --------------------------------------------------------------------
function scr_anim_set_emit(_id, _list) {
    var _p    = scr_anim_set_alias(_id) + "_";
    var _rows = scr_anim_set_row_count(_id);

    var _lbl_sub  = _p + "sub";
    var _lbl_skip = _p + "skip";
    array_push(_list, ["jsr",     _lbl_sub,  _id]);
    array_push(_list, ["jmp_abs", _lbl_skip, _id]);
    array_push(_list, ["label",   _lbl_sub]);

    if (_rows == 0) {
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _p + "reset"]);
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _lbl_skip]);
        return;
    }

    // ── Gather rows into flat per-slot tables ─────────────────────────
    var _res     = scr_anim_set_resolve_ptrs(_id);
    var _st      = [];
    var _en      = [];
    var _dly     = [];
    var _lp      = [];
    var _flat    = [];
    var _slot_on = array_create(8, false);
    for (var _si = 0; _si < 8; _si++) {
        array_push(_flat, []);
    }
    var _pos = 0;
    for (var _r = 0; _r < _rows; _r++) {
        var _b     = ANIMSET_HDR + _r * ANIMSET_STRIDE;
        var _lists = [];
        var _len   = 0;
        for (var _si = 0; _si < 8; _si++) {
            var _l = scr_anim_set_parse_list(_id.instructions[0][_b + 3 + _si]);
            array_push(_lists, _l);
            if (array_length(_l) > 0) {
                _slot_on[_si] = true;
            }
            _len = max(_len, array_length(_l));
        }
        _len = max(_len, 1);
        if (_pos + _len > 255) {
            show_debug_message("MACRO_ANIM_SET " + _p + ": frame tables exceed 255 entries, rows from " + string(_r) + " dropped");
            _rows = _r;
            break;
        }
        var _loop = (string(_id.instructions[0][_b + 2]) == "1");
        for (var _si = 0; _si < 8; _si++) {
            var _l2 = _lists[_si];
            var _n2 = array_length(_l2);
            for (var _fi = 0; _fi < _len; _fi++) {
                var _v = 0;
                if (_n2 > 0) {
                    if (_loop) {
                        _v = _l2[_fi mod _n2];
                    } else {
                        _v = _l2[min(_fi, _n2 - 1)];
                    }
                }
                array_push(_flat[_si], _v);
            }
        }
        var _d = _id.instructions[0][_b + 1];
        if (!is_real(_d)) {
            _d = 8;
        }
        array_push(_st,  _pos);
        array_push(_en,  _pos + _len);
        array_push(_dly, clamp(floor(_d), 1, 255));
        if (_loop) {
            array_push(_lp, 1);
        } else {
            array_push(_lp, 0);
        }
        _pos += _len;
    }
    if (_rows == 0) {
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _p + "reset"]);
        array_push(_list, ["rts", 0, _id]);
        array_push(_list, ["label", _lbl_skip]);
        return;
    }

    // ── SELECT source ─────────────────────────────────────────────────
    var _sel_raw = string_trim(string(_id.instructions[0][1]));
    if (_sel_raw == "") {
        array_push(_list, ["lda_imm", 0, _id]);
    } else if (string_char_at(_sel_raw, 1) == "$") {
        array_push(_list, ["lda_abs", real(hex_to_decimal(string_upper(string_delete(_sel_raw, 1, 1)))), _id]);
    } else if (string_digits(_sel_raw) == _sel_raw) {
        array_push(_list, ["lda_abs", real(_sel_raw), _id]);
    } else {
        // Variable name — resolved by the assembler through named_loc_map
        array_push(_list, ["lda_abs", _sel_raw, _id]);
    }

    // ── Player ────────────────────────────────────────────────────────
    array_push(_list, ["cmp_imm", _rows,          _id]);
    array_push(_list, ["bcc",     _p + "ok",      _id]);
    array_push(_list, ["rts",     0,              _id]);   // out of range = idle
    array_push(_list, ["label",   _p + "ok"]);
    array_push(_list, ["cmp_lab", _p + "cur",     _id]);
    array_push(_list, ["beq",     _p + "same",    _id]);
    // Row changed: restart it (first advance lands on its first frame)
    array_push(_list, ["sta_lab", _p + "cur",     _id]);
    array_push(_list, ["tax",     0,              _id]);
    array_push(_list, ["lda_abx", _p + "st",      _id]);
    array_push(_list, ["sta_lab", _p + "fidx",    _id]);
    array_push(_list, ["dec_lab", _p + "fidx",    _id]);
    array_push(_list, ["lda_imm", 1,              _id]);
    array_push(_list, ["sta_lab", _p + "spd",     _id]);
    array_push(_list, ["lda_imm", 0,              _id]);
    array_push(_list, ["sta_lab", _p + "done",    _id]);
    array_push(_list, ["label",   _p + "same"]);
    array_push(_list, ["lda_lab", _p + "done",    _id]);
    array_push(_list, ["beq",     _p + "live",    _id]);
    array_push(_list, ["rts",     0,              _id]);
    array_push(_list, ["label",   _p + "live"]);
    array_push(_list, ["dec_lab", _p + "spd",     _id]);
    array_push(_list, ["beq",     _p + "tick",    _id]);
    array_push(_list, ["rts",     0,              _id]);
    array_push(_list, ["label",   _p + "tick"]);
    array_push(_list, ["ldx_lab", _p + "cur",     _id]);
    array_push(_list, ["lda_abx", _p + "dly",     _id]);
    array_push(_list, ["sta_lab", _p + "spd",     _id]);
    array_push(_list, ["inc_lab", _p + "fidx",    _id]);
    array_push(_list, ["lda_lab", _p + "fidx",    _id]);
    array_push(_list, ["cmp_abx", _p + "en",      _id]);
    array_push(_list, ["bcc",     _p + "apply",   _id]);
    array_push(_list, ["lda_abx", _p + "lp",      _id]);
    array_push(_list, ["beq",     _p + "hold",    _id]);
    array_push(_list, ["lda_abx", _p + "st",      _id]);
    array_push(_list, ["sta_lab", _p + "fidx",    _id]);
    array_push(_list, ["jmp_abs", _p + "apply",   _id]);
    // One-shot: stay on the last frame and latch done
    array_push(_list, ["label",   _p + "hold"]);
    array_push(_list, ["dec_lab", _p + "fidx",    _id]);
    array_push(_list, ["lda_imm", 1,              _id]);
    array_push(_list, ["sta_lab", _p + "done",    _id]);
    array_push(_list, ["rts",     0,              _id]);
    array_push(_list, ["label",   _p + "apply"]);
    array_push(_list, ["ldx_lab", _p + "fidx",    _id]);
    for (var _si = 0; _si < 8; _si++) {
        if (!_slot_on[_si]) continue;
        if (_res.ptr[_si] == -1) continue;
        array_push(_list, ["lda_abx", _p + "f" + string(_si), _id]);
        array_push(_list, ["clc",     0,                      _id]);
        array_push(_list, ["adc_imm", _res.base,              _id]);
        array_push(_list, ["sta_abs", _res.ptr[_si],          _id]);
        if (_res.alt[_si] != -1) {
            array_push(_list, ["sta_abs", _res.alt[_si], _id]);
        }
    }
    array_push(_list, ["rts", 0, _id]);

    // ── Reset entry: forget the current row so the next call restarts it ─
    array_push(_list, ["label",   _p + "reset"]);
    array_push(_list, ["lda_imm", 0xFF,        _id]);
    array_push(_list, ["sta_lab", _p + "cur",  _id]);
    array_push(_list, ["rts",     0,           _id]);

    // ── State ─────────────────────────────────────────────────────────
    array_push(_list, ["label", _p + "cur"]);
    array_push(_list, ["byte",  0xFF, _id]);
    array_push(_list, ["label", _p + "fidx"]);
    array_push(_list, ["byte",  0x00, _id]);
    array_push(_list, ["label", _p + "spd"]);
    array_push(_list, ["byte",  0x01, _id]);
    array_push(_list, ["label", _p + "done"]);
    array_push(_list, ["byte",  0x00, _id]);

    // ── Per-row tables ────────────────────────────────────────────────
    var _tabs  = [_st, _en, _dly, _lp];
    var _names = ["st", "en", "dly", "lp"];
    for (var _ti = 0; _ti < 4; _ti++) {
        array_push(_list, ["label", _p + _names[_ti]]);
        var _tab = _tabs[_ti];
        for (var _k = 0; _k < _rows; _k++) {
            array_push(_list, ["byte", _tab[_k] & 0xFF, _id]);
        }
    }

    // ── Flat frame tables, one per used slot ──────────────────────────
    for (var _si = 0; _si < 8; _si++) {
        if (!_slot_on[_si]) continue;
        if (_res.ptr[_si] == -1) continue;
        array_push(_list, ["label", _p + "f" + string(_si)]);
        var _fl = _flat[_si];
        for (var _k = 0; _k < _pos; _k++) {
            array_push(_list, ["byte", _fl[_k] & 0xFF, _id]);
        }
    }

    array_push(_list, ["label", _lbl_skip]);
}
