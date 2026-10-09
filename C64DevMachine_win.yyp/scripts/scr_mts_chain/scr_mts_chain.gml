/// MAP CHAINS for META_TILESET.
///
/// A chain is an ordered list of maps - a level, a course section, a wave -
/// for engines that build their playfield from pieces (segment scrollers).
/// Each map has a repeat count and, in RAW ROWS tilesets, an optional fixed
/// address. Each chain can carry extra bytes in user-named columns (next
/// section, palette, speed ...). With EMIT TABLES on, the build writes:
///
///   <TS>_MAPLO / _MAPHI     address of every map (lo / hi)
///   <TS>_MAPROWS            char rows of every map
///   <TS>_MAPREPS            repeat count of every map
///   <TS>_CHAINLO / _CHAINHI address of every chain's map list
///   <TS>_CHAINLEN           number of maps in every chain
///   <TS>_<COLUMN>           one byte per chain for every extra column
///   <TS>_CHAIN<n>           the map numbers of chain n
///
/// Meta fields (initialised in scr_asset_meta_tileset_create):
///   map_reps[]  map_addr[] (-1 = straight after the previous map)
///   chains[]    { name, maps[], cols[] }
///   chain_cols[] column names   chain_dir 0 UP 1 DOWN 2 LEFT 3 RIGHT
///   chain_emit 0/1              chain_tab_addr (-1 = after the last map)

/// @desc Pad the per-map arrays to the map count, and every chain's columns
///       to the column count.
function scr_mts_maps_sync(_m) {
    var _n = array_length(_m.maps);
    while (array_length(_m.map_names) < _n) {
        array_push(_m.map_names, "");
    }
    while (array_length(_m.map_reps) < _n) {
        array_push(_m.map_reps, 1);
    }
    while (array_length(_m.map_addr) < _n) {
        array_push(_m.map_addr, -1);
    }
    while (array_length(_m.chain_col_link) < array_length(_m.chain_cols)) {
        array_push(_m.chain_col_link, 0);
    }
    for (var _ci = 0; _ci < array_length(_m.chains); _ci++) {
        while (array_length(_m.chains[_ci].cols) < array_length(_m.chain_cols)) {
            array_push(_m.chains[_ci].cols, 0);
        }
    }
}

/// @desc A map was deleted: drop its per-map entries and its uses in chains
///       (later maps move down one, so chain references are renumbered).
function scr_mts_map_removed(_m, _idx) {
    if (_idx < array_length(_m.map_w)) {
        array_delete(_m.map_w, _idx, 1);
    }
    if (_idx < array_length(_m.map_h)) {
        array_delete(_m.map_h, _idx, 1);
    }
    if (_idx < array_length(_m.map_names)) {
        array_delete(_m.map_names, _idx, 1);
    }
    if (_idx < array_length(_m.map_reps)) {
        array_delete(_m.map_reps, _idx, 1);
    }
    if (_idx < array_length(_m.map_addr)) {
        array_delete(_m.map_addr, _idx, 1);
    }
    for (var _ci = 0; _ci < array_length(_m.chains); _ci++) {
        var _cm = _m.chains[_ci].maps;
        for (var _ei = array_length(_cm) - 1; _ei >= 0; _ei--) {
            if (_cm[_ei] == _idx) {
                array_delete(_cm, _ei, 1);
            } else if (_cm[_ei] > _idx) {
                _cm[_ei] = _cm[_ei] - 1;
            }
        }
    }
}

/// @desc Map size in chars: [width, height].
function scr_mts_map_dims(_m, _mi) {
    var _cols = 1;
    if (_mi < array_length(_m.map_w)) {
        _cols = max(1, floor(_m.map_w[_mi] / _m.stamp_w));
    }
    var _rows = floor(array_length(_m.maps[_mi]) / _cols);
    return [_cols * _m.stamp_w, _rows * _m.stamp_h];
}

/// @desc Char at (x, y) of map _mi, -1 for an empty cell.
function scr_mts_map_char(_m, _mi, _x, _y) {
    var _sw   = _m.stamp_w;
    var _sh   = _m.stamp_h;
    var _cols = 1;
    if (_mi < array_length(_m.map_w)) {
        _cols = max(1, floor(_m.map_w[_mi] / _sw));
    }
    var _gx = floor(_x / _sw);
    var _gy = floor(_y / _sh);
    var _gi = _gy * _cols + _gx;
    var _grid = _m.maps[_mi];
    if (_gi < 0 || _gi >= array_length(_grid)) {
        return -1;
    }
    var _mt = _grid[_gi];
    if (_mt < 0 || _mt >= _m.stamp_count) {
        return -1;
    }
    var _db = _mt * _sw * _sh + (_y - _gy * _sh) * _sw + (_x - _gx * _sw);
    if (_db >= array_length(_m.stamp_data)) {
        return -1;
    }
    return _m.stamp_data[_db];
}

/// @desc "$C000" -> 49152, "123" -> 123, anything else (or "") -> -1.
function scr_mts_parse_num(_s) {
    var _t = string_upper(string_trim(_s));
    if (_t == "") {
        return -1;
    }
    if (string_char_at(_t, 1) == "$") {
        var _h = string_delete(_t, 1, 1);
        if (_h == "") {
            return -1;
        }
        for (var _i = 1; _i <= string_length(_h); _i++) {
            if (string_pos(string_char_at(_h, _i), "0123456789ABCDEF") == 0) {
                return -1;
            }
        }
        return hex_to_decimal(_h);
    }
    for (var _j = 1; _j <= string_length(_t); _j++) {
        if (string_pos(string_char_at(_t, _j), "0123456789") == 0) {
            return -1;
        }
    }
    return real(_t);
}

/// @desc A column name as a label part: A-Z 0-9 _ only.
function scr_mts_col_label(_name) {
    var _s = string_upper(string_trim(_name));
    var _o = "";
    for (var _i = 1; _i <= string_length(_s); _i++) {
        var _c = string_char_at(_s, _i);
        if (string_pos(_c, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") > 0) {
            _o += _c;
        } else {
            _o += "_";
        }
    }
    if (_o == "") {
        _o = "COL";
    }
    return _o;
}

/// @desc Bytes the EMIT TABLES block takes.
function scr_mts_chain_table_size(_m) {
    var _n  = array_length(_m.maps);
    var _nc = array_length(_m.chains);
    var _sz = _n * 4 + _nc * 3 + _nc * array_length(_m.chain_cols);
    for (var _ci = 0; _ci < _nc; _ci++) {
        _sz += array_length(_m.chains[_ci].maps);
    }
    return _sz;
}

/// @desc Memory the RAW ROWS output occupies, as [[addr, size], ...] - one
///       range per run of maps, plus the tables when EMIT TABLES is on.
function scr_mts_raw_rows_ranges(_a) {
    var _m   = _a.meta;
    var _out = [];
    var _pc  = _a.address;
    var _r0  = _pc;
    var _rs  = 0;
    for (var _mi = 0; _mi < array_length(_m.maps); _mi++) {
        if (_mi < array_length(_m.map_addr)) {
            if (_m.map_addr[_mi] >= 0) {
                if (_rs > 0) {
                    array_push(_out, [_r0, _rs]);
                }
                _pc = _m.map_addr[_mi];
                _r0 = _pc;
                _rs = 0;
            }
        }
        var _d  = scr_mts_map_dims(_m, _mi);
        var _sz = _d[0] * _d[1];
        _pc += _sz;
        _rs += _sz;
    }
    if (_m.chain_emit == 1) {
        if (_m.chain_tab_addr >= 0) {
            if (_rs > 0) {
                array_push(_out, [_r0, _rs]);
            }
            _r0 = _m.chain_tab_addr;
            _rs = 0;
        }
        _rs += scr_mts_chain_table_size(_m);
    }
    if (_rs > 0) {
        array_push(_out, [_r0, _rs]);
    }
    return _out;
}

/// @desc EMIT TABLES (PASS 3, after the maps). See the header for the labels.
function scr_mts_chain_emit(_list, _a) {
    var _m  = _a.meta;
    var _nm = _a.name;
    var _n  = array_length(_m.maps);
    var _nc = array_length(_m.chains);
    if (_m.chain_tab_addr >= 0) {
        array_push(_list, ["org", _m.chain_tab_addr]);
    }
    array_push(_list, ["label", _nm + "_MAPLO"]);
    for (var _i = 0; _i < _n; _i++) {
        array_push(_list, ["byte_lab_lo", _nm + "_MAP" + string(_i)]);
    }
    array_push(_list, ["label", _nm + "_MAPHI"]);
    for (var _i2 = 0; _i2 < _n; _i2++) {
        array_push(_list, ["byte_lab_hi", _nm + "_MAP" + string(_i2)]);
    }
    array_push(_list, ["label", _nm + "_MAPROWS"]);
    for (var _i3 = 0; _i3 < _n; _i3++) {
        var _d = scr_mts_map_dims(_m, _i3);
        array_push(_list, ["byte", _d[1] & 0xFF]);
    }
    array_push(_list, ["label", _nm + "_MAPREPS"]);
    for (var _i4 = 0; _i4 < _n; _i4++) {
        var _rp = 1;
        if (_i4 < array_length(_m.map_reps)) {
            _rp = _m.map_reps[_i4];
        }
        array_push(_list, ["byte", _rp & 0xFF]);
    }
    array_push(_list, ["label", _nm + "_CHAINLO"]);
    for (var _c = 0; _c < _nc; _c++) {
        array_push(_list, ["byte_lab_lo", _nm + "_CHAIN" + string(_c)]);
    }
    array_push(_list, ["label", _nm + "_CHAINHI"]);
    for (var _c2 = 0; _c2 < _nc; _c2++) {
        array_push(_list, ["byte_lab_hi", _nm + "_CHAIN" + string(_c2)]);
    }
    array_push(_list, ["label", _nm + "_CHAINLEN"]);
    for (var _c3 = 0; _c3 < _nc; _c3++) {
        array_push(_list, ["byte", array_length(_m.chains[_c3].maps) & 0xFF]);
    }
    for (var _k = 0; _k < array_length(_m.chain_cols); _k++) {
        array_push(_list, ["label", _nm + "_" + scr_mts_col_label(_m.chain_cols[_k])]);
        for (var _c4 = 0; _c4 < _nc; _c4++) {
            var _v = 0;
            if (_k < array_length(_m.chains[_c4].cols)) {
                _v = _m.chains[_c4].cols[_k];
            }
            array_push(_list, ["byte", _v & 0xFF]);
        }
    }
    for (var _c5 = 0; _c5 < _nc; _c5++) {
        array_push(_list, ["label", _nm + "_CHAIN" + string(_c5)]);
        var _cm = _m.chains[_c5].maps;
        for (var _e = 0; _e < array_length(_cm); _e++) {
            array_push(_list, ["byte", _cm[_e] & 0xFF]);
        }
    }
}

/// @desc The chain as preview slices along the scroll direction: an array of
///       [map, line, entry, chain] in the order the engine meets them (repeats
///       expanded). line = char row (UP / DOWN) or char column (LEFT / RIGHT),
///       already in the order it is fed in.
function scr_mts_chain_slices(_m, _ci) {
    var _out = [];
    if (_ci < 0 || _ci >= array_length(_m.chains)) {
        return _out;
    }
    var _cm = _m.chains[_ci].maps;
    var _ne = array_length(_cm);
    for (var _ei = 0; _ei < _ne; _ei++) {
        // chain_rev: the engine reads the list from its end (e.g. a counter
        // that counts down), so the LAST entry is the first one fed in
        var _e = _ei;
        if (_m.chain_rev == 1) {
            _e = _ne - 1 - _ei;
        }
        var _mi = _cm[_e];
        if (_mi < 0 || _mi >= array_length(_m.maps)) {
            continue;
        }
        var _d   = scr_mts_map_dims(_m, _mi);
        var _rp  = 1;
        if (_mi < array_length(_m.map_reps)) {
            _rp = max(1, _m.map_reps[_mi]);
        }
        var _len = _d[1];
        if (_m.chain_dir >= 2) {
            _len = _d[0];
        }
        for (var _r = 0; _r < _rp; _r++) {
            for (var _l = 0; _l < _len; _l++) {
                var _line = _l;
                // UP feeds the bottom row first, LEFT the right-hand column first
                if (_m.chain_dir == 0 || _m.chain_dir == 2) {
                    _line = _len - 1 - _l;
                }
                array_push(_out, [_mi, _line, _e, _ci]);
            }
        }
    }
    return _out;
}

/// @desc Every chain joined up in chain order - the whole course / level set
///       as one continuous strip. Same slice format: [map, line, entry, chain].
function scr_mts_course_slices(_m) {
    var _out = [];
    for (var _ci = 0; _ci < array_length(_m.chains); _ci++) {
        var _cs = scr_mts_chain_slices(_m, _ci);
        for (var _i = 0; _i < array_length(_cs); _i++) {
            array_push(_out, _cs[_i]);
        }
    }
    return _out;
}

/// @desc First slice of chain _ci in the course strip.
function scr_mts_course_start(_m, _ci) {
    var _n = 0;
    for (var _c = 0; _c < min(_ci, array_length(_m.chains)); _c++) {
        _n += array_length(scr_mts_chain_slices(_m, _c));
    }
    return _n;
}

/// @desc Small flat button. Returns true on the click.
function scr_mts_ui_button(_x1, _y1, _x2, _y2, _label, _on, _mx, _my, _info = "") {
    var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2);
    if (_info != "") {
        scr_ui_info(_hov, _info);
    }
    if (_on) {
        draw_set_color(make_color_rgb(20, 70, 50));
    } else {
        draw_set_color(make_color_rgb(30, 32, 44));
    }
    if (_hov) {
        draw_set_color(make_color_rgb(40, 110, 80));
    }
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(80, 200, 140));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    // Small font, centred both ways in the button
    draw_set_font_l(fnt_c64_nano);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_l(round((_x1 + _x2) * 0.5), round((_y1 + _y2) * 0.5) + 1, _label);
    draw_set_valign(fa_top);
    draw_set_halign(fa_left);
    draw_set_font_l(fnt_c64_tiny);
    return (_hov && mouse_check_button_pressed(mb_left));
}

/// @desc Start typing into a MAP CHAINS field (finished in obj_asset_manager Step).
function scr_mts_chain_edit_start(_field, _text, _idx, _col) {
    editing_map_dim       = true;
    editing_map_field     = _field;
    editing_map_string    = _text;
    editing_map_asset_idx = viewer_asset;
    editing_map_name_idx  = _idx;
    editing_map_col_idx   = _col;
    keyboard_string       = "";
}

/// @desc Text shown for a field: what's being typed if it is the one being edited.
function scr_mts_chain_field_text(_field, _idx, _col, _text) {
    if (editing_map_dim && editing_map_field == _field && editing_map_name_idx == _idx && editing_map_col_idx == _col) {
        return editing_map_string + "_";
    }
    return _text;
}

/// @desc Hex text for an address, or AUTO for -1.
function scr_mts_addr_text(_a) {
    if (_a < 0) {
        return "AUTO";
    }
    var _h = string_upper(decimal_to_hex(_a));
    while (string_length(_h) < 4) {
        _h = "0" + _h;
    }
    return "$" + _h;
}

/// @desc The CHAINS panel of the tileset editor: chain list, the maps in the
///       active chain, its columns, map settings, export settings, and a
///       preview of the chain drawn the way the engine feeds it in.
/// @param {struct} _m      tileset meta
/// @param {struct} _asset  the tileset asset
/// @param {real}   _x1,_y1,_x2,_y2  panel rectangle
/// @param {real}   _mx,_my mouse (GUI)
/// @param {struct} _gx     glyph context { bg, mixed, eff_mixed, ecm, ecm_cols, atlas_ok, mc1, mc2 }
function scr_mts_chain_panel(_m, _asset, _x1, _y1, _x2, _y2, _mx, _my, _gx) {
    scr_mts_maps_sync(_m);
    var _nc = array_length(_m.chains);
    if (_m.active_chain >= _nc) {
        _m.active_chain = _nc - 1;
    }
    if (_m.active_chain < 0 && _nc > 0) {
        _m.active_chain = 0;
    }
    var _ac = _m.active_chain;

    draw_set_color(make_color_rgb(10, 12, 18));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(45, 70, 80));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);

    var _rh  = 17;                  // row height
    var _lx1 = _x1 + 6;
    var _lx2 = _x1 + 250;           // left column
    var _y   = _y1 + 4;
    var _bw  = 46;

    // ===== CHAINS: [+ NEW] [DELETE] [UP] [DN] =====  (own sub-panel)
    scr_mts_subpanel(_lx1 - 4, _y - 3, _lx2 + 3, _y + _rh + 8 * 14 + 3);
    // The list is drawn in the order the course is drawn: with DIR UP the
    // first chain sits at the bottom and later ones stack on top of it.
    draw_set_color(make_color_rgb(80, 200, 255));
    draw_text_l(_lx1, _y + 1, L("CHAINS"));
    var _cbx = _lx1 + 56;
    if (scr_mts_ui_button(_cbx, _y, _cbx + 46, _y + _rh - 3, L("+ NEW"), false, _mx, _my, "NEW CHAIN: ADD AN EMPTY CHAIN AND SELECT IT")) {
        var _cols0 = array_create(array_length(_m.chain_cols), 0);
        array_push(_m.chains, { name: L("CHAIN ") + string(_nc), maps: [], cols: _cols0 });
        _m.active_chain     = _nc;
        mts_chain_sel_entry = -1;
        mts_chain_scroll    = 0;
        _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
    }
    _cbx += 50;
    if (_ac >= 0) {
        if (scr_mts_ui_button(_cbx, _y, _cbx + 50, _y + _rh - 3, L("DELETE"), false, _mx, _my, "DELETE THE SELECTED CHAIN (LINK COLUMNS ARE RENUMBERED)")) {
            scr_mts_chain_delete(_m, _ac);
            _m.active_chain     = min(_ac, array_length(_m.chains) - 1);
            mts_chain_sel_entry = -1;
            _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
            return;
        }
        _cbx += 54;
        // UP / DN move the chain one row up / down in the list as drawn
        var _cdisp = scr_mts_chain_display(_m);
        var _cpos  = -1;
        for (var _cp = 0; _cp < array_length(_cdisp); _cp++) {
            if (_cdisp[_cp] == _ac) {
                _cpos = _cp;
            }
        }
        if (scr_mts_ui_button(_cbx, _y, _cbx + 28, _y + _rh - 3, L("UP"), false, _mx, _my, "MOVE THE SELECTED CHAIN UP ONE ROW IN THE LIST")) {
            if (_cpos > 0) {
                scr_mts_chain_swap(_m, _ac, _cdisp[_cpos - 1]);
                _m.active_chain = _cdisp[_cpos - 1];
                _m.is_dirty = true; global.undo_dirty = true; global.addresses_dirty = true;
            }
        }
        _cbx += 32;
        if (scr_mts_ui_button(_cbx, _y, _cbx + 28, _y + _rh - 3, L("DN"), false, _mx, _my, "MOVE THE SELECTED CHAIN DOWN ONE ROW IN THE LIST")) {
            if (_cpos >= 0 && _cpos < array_length(_cdisp) - 1) {
                scr_mts_chain_swap(_m, _ac, _cdisp[_cpos + 1]);
                _m.active_chain = _cdisp[_cpos + 1];
                _m.is_dirty = true; global.undo_dirty = true; global.addresses_dirty = true;
            }
        }
    }
    _y += _rh;
    _nc = array_length(_m.chains);
    _ac = _m.active_chain;

    // Chain list (double-click a name to rename it), with a scroll bar
    var _vis_c = 8;
    var _cl_y0 = _y;
    var _cl_x2 = _lx2 - 10;
    var _cdl   = scr_mts_chain_display(_m);
    if (point_in_rectangle(_mx, _my, _lx1, _cl_y0, _lx2, _cl_y0 + _vis_c * 14)) {
        if (mouse_wheel_up())   { mts_chain_list_scroll -= 1; }
        if (mouse_wheel_down()) { mts_chain_list_scroll += 1; }
    }
    mts_chain_list_scroll = scr_mts_list_scrollbar(_cl_x2 + 3, _cl_y0, _lx2, _cl_y0 + _vis_c * 14 - 1, _nc, _vis_c, mts_chain_list_scroll, _mx, _my);
    for (var _r = 0; _r < _vis_c; _r++) {
        var _di = mts_chain_list_scroll + _r;
        if (_di >= _nc) {
            break;
        }
        var _ci  = _cdl[_di];
        var _cy  = _cl_y0 + _r * 14;
        var _hov = point_in_rectangle(_mx, _my, _lx1, _cy, _cl_x2, _cy + 13);
        scr_ui_info(_hov, "CLICK TO SELECT THIS CHAIN, DOUBLE-CLICK TO RENAME IT");
        if (_ci == _ac) {
            draw_set_color(make_color_rgb(30, 90, 50));
            draw_rectangle(_lx1, _cy, _cl_x2, _cy + 13, false);
        } else if (_hov) {
            draw_set_color(make_color_rgb(30, 45, 40));
            draw_rectangle(_lx1, _cy, _cl_x2, _cy + 13, false);
        }
        draw_set_color(c_white);
        var _ctxt = scr_mts_chain_field_text("CHAIN", _ci, -1, _m.chains[_ci].name);
        draw_text_l(_lx1 + 4, _cy, string(_ci) + "  " + _ctxt);
        draw_set_color(make_color_rgb(120, 160, 140));
        draw_set_halign(fa_right);
        draw_text_l(_cl_x2 - 4, _cy, string(array_length(_m.chains[_ci].maps)) + L(" MAPS"));
        draw_set_halign(fa_left);
        if (_hov && mouse_check_button_pressed(mb_left)) {
            if (mts_tab_click_map == 100000 + _ci && current_time - mts_tab_click_time < 400) {
                scr_mts_chain_edit_start("CHAIN", _m.chains[_ci].name, _ci, -1);
                mts_tab_click_map = -1;
            } else {
                mts_tab_click_map  = 100000 + _ci;
                mts_tab_click_time = current_time;
                if (_ci != _ac) {
                    _m.active_chain        = _ci;
                    mts_chain_sel_entry    = -1;
                    mts_chain_entry_scroll = 0;
                    mts_chain_scroll       = 0;
                    if (mts_chain_view == 0) {
                        mts_chain_scroll = scr_mts_course_start(_m, _ci);
                    }
                }
            }
        }
    }
    _y = _cl_y0 + _vis_c * 14 + 12;
    _ac = _m.active_chain;

    // ===== MAPS IN THE CHAIN: [+ MAP] [DEL] [UP] [DN] =====  (own sub-panel)
    scr_mts_subpanel(_lx1 - 4, _y - 3, _lx2 + 3, _y + _rh + 8 * 14 + 3);
    // Drawn in the order the preview draws them (feed order, DIR UP = the
    // first map fed at the bottom), so UP / DN move a map up / down on screen.
    draw_set_color(make_color_rgb(80, 200, 255));
    draw_text_l(_lx1, _y + 1, L("MAPS"));
    if (_ac >= 0) {
        var _cm   = _m.chains[_ac].maps;
        var _edl  = scr_mts_entry_display(_m, _ac);
        var _epos = -1;
        for (var _ep = 0; _ep < array_length(_edl); _ep++) {
            if (_edl[_ep] == mts_chain_sel_entry) {
                _epos = _ep;
            }
        }
        var _bx  = _lx1 + 46;
        var _sbw = 46;
        if (scr_mts_ui_button(_bx, _y, _bx + _sbw, _y + _rh - 3, L("+ MAP"), false, _mx, _my, "ADD THE ACTIVE MAP TAB TO THIS CHAIN, AFTER THE SELECTED ENTRY")) {
            if (_m.active_map >= 0 && _m.active_map < array_length(_m.maps)) {
                // the new map goes straight after the selected one in feed order
                // (on screen: next to it, on the side the chain grows towards)
                var _at = array_length(_cm);
                if (_m.chain_rev == 1) {
                    _at = 0;
                }
                if (mts_chain_sel_entry >= 0 && mts_chain_sel_entry < array_length(_cm)) {
                    _at = mts_chain_sel_entry + 1;
                    if (_m.chain_rev == 1) {
                        _at = mts_chain_sel_entry;
                    }
                }
                array_insert(_cm, _at, _m.active_map);
                mts_chain_sel_entry = _at;
                _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
            }
        }
        _bx += _sbw + 4;
        if (scr_mts_ui_button(_bx, _y, _bx + 36, _y + _rh - 3, L("DEL"), false, _mx, _my, "REMOVE THE SELECTED ENTRY FROM THIS CHAIN (THE MAP ITSELF IS KEPT)")) {
            if (mts_chain_sel_entry >= 0 && mts_chain_sel_entry < array_length(_cm)) {
                array_delete(_cm, mts_chain_sel_entry, 1);
                mts_chain_sel_entry = min(mts_chain_sel_entry, array_length(_cm) - 1);
                _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
            }
        }
        _bx += 40;
        if (scr_mts_ui_button(_bx, _y, _bx + 28, _y + _rh - 3, L("UP"), false, _mx, _my, "MOVE THE SELECTED ENTRY UP ONE ROW")) {
            if (_epos > 0) {
                var _ea = _edl[_epos];
                var _eb = _edl[_epos - 1];
                var _t  = _cm[_ea];
                _cm[_ea] = _cm[_eb];
                _cm[_eb] = _t;
                mts_chain_sel_entry = _eb;
                _m.is_dirty = true; global.undo_dirty = true;
            }
        }
        _bx += 32;
        if (scr_mts_ui_button(_bx, _y, _bx + 28, _y + _rh - 3, L("DN"), false, _mx, _my, "MOVE THE SELECTED ENTRY DOWN ONE ROW")) {
            if (_epos >= 0 && _epos < array_length(_edl) - 1) {
                var _ea2 = _edl[_epos];
                var _eb2 = _edl[_epos + 1];
                var _t2  = _cm[_ea2];
                _cm[_ea2] = _cm[_eb2];
                _cm[_eb2] = _t2;
                mts_chain_sel_entry = _eb2;
                _m.is_dirty = true; global.undo_dirty = true;
            }
        }
        _y += _rh;
        // Entry list, with a scroll bar
        var _vis_e = 8;
        var _el_y0 = _y;
        var _el_x2 = _lx2 - 10;
        var _ne    = array_length(_edl);
        if (point_in_rectangle(_mx, _my, _lx1, _el_y0, _lx2, _el_y0 + _vis_e * 14)) {
            if (mouse_wheel_up())   { mts_chain_entry_scroll -= 1; }
            if (mouse_wheel_down()) { mts_chain_entry_scroll += 1; }
        }
        mts_chain_entry_scroll = scr_mts_list_scrollbar(_el_x2 + 3, _el_y0, _lx2, _el_y0 + _vis_e * 14 - 1, _ne, _vis_e, mts_chain_entry_scroll, _mx, _my);
        for (var _r2 = 0; _r2 < _vis_e; _r2++) {
            var _dj = mts_chain_entry_scroll + _r2;
            if (_dj >= _ne) {
                break;
            }
            var _ei   = _edl[_dj];
            var _ey   = _el_y0 + _r2 * 14;
            var _ehov = point_in_rectangle(_mx, _my, _lx1, _ey, _el_x2, _ey + 13);
            scr_ui_info(_ehov, "CLICK TO SELECT THIS ENTRY AND SHOW ITS MAP");
            if (_ei == mts_chain_sel_entry) {
                draw_set_color(make_color_rgb(70, 60, 20));
                draw_rectangle(_lx1, _ey, _el_x2, _ey + 13, false);
            } else if (_ehov) {
                draw_set_color(make_color_rgb(30, 45, 40));
                draw_rectangle(_lx1, _ey, _el_x2, _ey + 13, false);
            }
            var _emi = _cm[_ei];
            var _enm = L("MAP ") + string(_emi);
            if (_emi >= 0 && _emi < array_length(_m.map_names)) {
                if (_m.map_names[_emi] != "") {
                    _enm = _m.map_names[_emi];
                }
            }
            var _erp = 1;
            if (_emi >= 0 && _emi < array_length(_m.map_reps)) {
                _erp = _m.map_reps[_emi];
            }
            draw_set_color(c_white);
            draw_text_l(_lx1 + 4, _ey, string(_ei) + "  " + _enm);
            draw_set_color(make_color_rgb(120, 160, 140));
            draw_set_halign(fa_right);
            draw_text_l(_el_x2 - 4, _ey, "x" + string(_erp));
            draw_set_halign(fa_left);
            if (_ehov && mouse_check_button_pressed(mb_left)) {
                mts_chain_sel_entry = _ei;
                if (_emi >= 0 && _emi < array_length(_m.maps)) {
                    _m.active_map = _emi;
                }
            }
        }
        _y = _el_y0 + _vis_e * 14 + 12;
    } else {
        _y += _rh;
        draw_set_color(make_color_rgb(110, 110, 130));
        draw_text_l(_lx1, _y, L("+ NEW MAKES A CHAIN"));
        _y += 8 * 14 + 12 - _rh;
    }

    // ===== COLUMNS: a byte per chain each (right-click a column to remove it) =====
    var _vis_k = 4;
    scr_mts_subpanel(_lx1 - 4, _y - 3, _lx2 + 3, _y + _rh + _vis_k * 14 + 3);
    draw_set_color(make_color_rgb(80, 200, 255));
    draw_text_l(_lx1, _y + 1, L("COLUMNS"));
    if (scr_mts_ui_button(_lx2 - 50, _y, _lx2, _y + _rh - 3, L("+ COL"), false, _mx, _my, "ADD A COLUMN (ONE BYTE PER CHAIN): TYPE ITS NAME")) {
        scr_mts_chain_edit_start("COLNAME", "", -1, -1);
    }
    if (editing_map_dim && editing_map_field == "COLNAME" && editing_map_name_idx == -1) {
        // the name being typed for a new column, in the header
        draw_set_color(make_color_rgb(255, 220, 80));
        draw_text_l(_lx1 + 74, _y + 1, editing_map_string + "_");
    }
    _y += _rh;
    var _kl_y0 = _y;
    var _nk    = array_length(_m.chain_cols);
    if (point_in_rectangle(_mx, _my, _lx1, _kl_y0, _lx2, _kl_y0 + _vis_k * 14)) {
        if (mouse_wheel_up())   { mts_chain_col_scroll -= 1; }
        if (mouse_wheel_down()) { mts_chain_col_scroll += 1; }
    }
    mts_chain_col_scroll = scr_mts_list_scrollbar(_lx2 - 7, _kl_y0, _lx2, _kl_y0 + _vis_k * 14 - 1, _nk, _vis_k, mts_chain_col_scroll, _mx, _my);
    _lx2 -= 10;   // rows stop short of the scroll bar
    for (var _k = mts_chain_col_scroll; _k < min(_nk, mts_chain_col_scroll + _vis_k); _k++) {
        var _ky   = _kl_y0 + (_k - mts_chain_col_scroll) * 14;
        var _khov = point_in_rectangle(_mx, _my, _lx1, _ky, _lx2, _ky + 13);
        scr_ui_info(_khov, "CLICK NAME TO RENAME, CLICK VALUE (RIGHT) TO TYPE THIS CHAIN'S BYTE, R-CLICK DELETE");
        if (_khov) {
            draw_set_color(make_color_rgb(30, 45, 40));
            draw_rectangle(_lx1, _ky, _lx2, _ky + 13, false);
        }
        draw_set_color(make_color_rgb(200, 200, 220));
        draw_text_l(_lx1 + 4, _ky, scr_mts_chain_field_text("COLNAME", _k, -1, _m.chain_cols[_k]));
        // LINK: this column holds chain numbers (next section ...) - they are
        // renumbered when chains are moved or deleted
        var _lk_on = false;
        if (_k < array_length(_m.chain_col_link)) {
            if (_m.chain_col_link[_k] == 1) {
                _lk_on = true;
            }
        }
        if (scr_mts_ui_button(_lx2 - 110, _ky, _lx2 - 72, _ky + 12, L("LINK"), _lk_on, _mx, _my, "LINK: COLUMN HOLDS CHAIN NUMBERS, RENUMBERED WHEN CHAINS MOVE OR ARE DELETED")) {
            if (_lk_on) {
                _m.chain_col_link[_k] = 0;
            } else {
                _m.chain_col_link[_k] = 1;
            }
            _m.is_dirty = true;
        }
        var _kv = L("-");
        if (_ac >= 0) {
            _kv = string(_m.chains[_ac].cols[_k]);
        }
        draw_set_color(c_lime);
        draw_set_halign(fa_right);
        draw_text_l(_lx2 - 4, _ky, scr_mts_chain_field_text("COLVAL", _ac, _k, _kv));
        draw_set_halign(fa_left);
        if (_khov && mouse_check_button_pressed(mb_left) && !point_in_rectangle(_mx, _my, _lx2 - 110, _ky, _lx2 - 72, _ky + 12)) {
            if (_mx > _lx2 - 70) {
                if (_ac >= 0) {
                    scr_mts_chain_edit_start("COLVAL", string(_m.chains[_ac].cols[_k]), _ac, _k);
                }
            } else {
                scr_mts_chain_edit_start("COLNAME", _m.chain_cols[_k], _k, -1);
            }
        }
        if (_khov && mouse_check_button_pressed(mb_right)) {
            array_delete(_m.chain_cols, _k, 1);
            if (_k < array_length(_m.chain_col_link)) {
                array_delete(_m.chain_col_link, _k, 1);
            }
            for (var _kc = 0; _kc < array_length(_m.chains); _kc++) {
                if (_k < array_length(_m.chains[_kc].cols)) {
                    array_delete(_m.chains[_kc].cols, _k, 1);
                }
            }
            _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
            return;
        }
    }
    _lx2 += 10;
    _y = _kl_y0 + _vis_k * 14 + 12;

    // ===== SETTINGS: selected map + export  (own sub-panel) =====
    var _set_h = (_rh + 4) + _rh + _rh;
    if (_m.chain_emit == 1) {
        _set_h += 14;
    }
    scr_mts_subpanel(_lx1 - 4, _y - 3, _lx2 + 3, _y + _set_h + 3);

    // ===== SELECTED MAP: repeat count + address =====
    draw_set_color(make_color_rgb(80, 200, 255));
    if (_m.active_map >= 0 && _m.active_map < array_length(_m.maps)) {
        var _am = _m.active_map;
        draw_text_l(_lx1, _y + 1, L("MAP ") + string(_am));
        // REPS: - [xN] +   (shift = steps of 10)
        var _rp_step = 1;
        if (keyboard_check(vk_shift)) {
            _rp_step = 10;
        }
        if (scr_mts_ui_button(_lx1 + 50, _y, _lx1 + 66, _y + _rh - 3, "-", false, _mx, _my, "MAP REPEAT COUNT - 1 (SHIFT: - 10, MIN 1)")) {
            _m.map_reps[_am] = max(1, _m.map_reps[_am] - _rp_step);
            _m.is_dirty = true; global.undo_dirty = true; global.addresses_dirty = true;
        }
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_l(_lx1 + 90, _y + 1, "x" + string(_m.map_reps[_am]));
        draw_set_halign(fa_left);
        if (scr_mts_ui_button(_lx1 + 114, _y, _lx1 + 130, _y + _rh - 3, "+", false, _mx, _my, "MAP REPEAT COUNT + 1 (SHIFT: + 10, MAX 255)")) {
            _m.map_reps[_am] = min(255, _m.map_reps[_am] + _rp_step);
            _m.is_dirty = true; global.undo_dirty = true; global.addresses_dirty = true;
        }
        var _ad_txt = scr_mts_chain_field_text("ADDR", _am, -1, scr_mts_addr_text(_m.map_addr[_am]));
        if (scr_mts_ui_button(_lx1 + 136, _y, _lx2, _y + _rh - 3, L("AT ") + _ad_txt, (_m.map_addr[_am] >= 0), _mx, _my, "CLICK TO TYPE A FIXED ADDRESS FOR THIS MAP (EMPTY = AUTO)")) {
            scr_mts_chain_edit_start("ADDR", "", _am, -1);
        }
    } else {
        draw_text_l(_lx1, _y + 1, L("PICK A MAP TAB"));
    }
    _y += _rh + 4;

    // ===== EXPORT: direction, tables on/off, table address =====
    var _dir_names = ["UP", "DOWN", "LEFT", "RIGHT"];
    if (scr_mts_ui_button(_lx1, _y, _lx1 + 76, _y + _rh - 3, L("DIR ") + _dir_names[clamp(_m.chain_dir, 0, 3)], false, _mx, _my, "DIRECTION THE CHAINS ARE FED IN: CYCLES UP / DOWN / LEFT / RIGHT")) {
        _m.chain_dir = (_m.chain_dir + 1) mod 4;
        mts_chain_scroll = 0;
        _m.is_dirty = true;
    }
    var _tl = L("TABLES OFF");
    if (_m.chain_emit == 1) {
        _tl = L("TABLES ON");
    }
    if (scr_mts_ui_button(_lx1 + 80, _y, _lx1 + 160, _y + _rh - 3, _tl, (_m.chain_emit == 1), _mx, _my, "TABLES: EMIT THE CHAIN LOOKUP TABLES (_MAPLO ...). NEEDS RAW ROWS ON")) {
        if (_m.chain_emit == 1) {
            _m.chain_emit = 0;
        } else {
            _m.chain_emit = 1;
        }
        _m.is_dirty = true; global.undo_dirty = true; global.memory_bar_dirty = true; global.addresses_dirty = true;
    }
    var _ta_txt = scr_mts_chain_field_text("TABADDR", 0, -1, scr_mts_addr_text(_m.chain_tab_addr));
    if (scr_mts_ui_button(_lx1 + 164, _y, _lx2, _y + _rh - 3, L("AT ") + _ta_txt, (_m.chain_tab_addr >= 0), _mx, _my, "CLICK TO TYPE A FIXED ADDRESS FOR THE CHAIN TABLES (EMPTY = AUTO)")) {
        scr_mts_chain_edit_start("TABADDR", "", 0, -1);
    }
    _y += _rh;
    // Which end of a chain's list the engine reads first (preview only - the
    // list is stored as it is shown either way).
    var _fd = L("FEED FIRST > LAST");
    if (_m.chain_rev == 1) {
        _fd = L("FEED LAST > FIRST");
    }
    if (scr_mts_ui_button(_lx1, _y, _lx2, _y + _rh - 3, _fd, (_m.chain_rev == 1), _mx, _my, "WHICH END OF EACH CHAIN THE ENGINE READS FIRST (PREVIEW ONLY)")) {
        if (_m.chain_rev == 1) {
            _m.chain_rev = 0;
        } else {
            _m.chain_rev = 1;
        }
        mts_chain_scroll = 0;
        _m.is_dirty = true;
    }
    _y += _rh;
    if (_m.chain_emit == 1 && _m.raw_rows == 0) {
        draw_set_color(make_color_rgb(255, 140, 80));
        draw_text_l(_lx1, _y, L("TABLES NEED RAW ROWS ON"));
        _y += 14;
    } else if (_m.chain_emit == 1) {
        draw_set_color(make_color_rgb(120, 160, 140));
        draw_text_l(_lx1, _y, string(scr_mts_chain_table_size(_m)) + L("B TABLES  ") + _asset.name + "_MAPLO ...");
        _y += 14;
    }

    // ===== PREVIEW: the course (every chain joined) or one section, fed in the way
    //       the engine does, with a slider. Click a piece to select its chain / map.
    var _px1 = _lx2 + 12;
    var _px2 = _x2 - 6;
    var _py1 = _y1 + 4;
    var _py2 = _y2 - 6;
    // header: view toggle + where the active chain sits
    if (scr_mts_ui_button(_px1, _py1, _px1 + 64, _py1 + 14, L("COURSE"), (mts_chain_view == 0), _mx, _my, "PREVIEW THE WHOLE COURSE: EVERY CHAIN JOINED")) {
        mts_chain_view   = 0;
        mts_chain_scroll = scr_mts_course_start(_m, _ac);
    }
    if (scr_mts_ui_button(_px1 + 68, _py1, _px1 + 132, _py1 + 14, L("SECTION"), (mts_chain_view == 1), _mx, _my, "PREVIEW ONLY THE SELECTED CHAIN")) {
        mts_chain_view   = 1;
        mts_chain_scroll = 0;
    }
    // ZOOM OUT: - [Nx] +  (1 = fit the widest map, 4 = a quarter of that)
    if (scr_mts_ui_button(_px1 + 144, _py1, _px1 + 160, _py1 + 14, "-", false, _mx, _my, "ZOOM THE PREVIEW OUT (UP TO 4X)")) {
        mts_chain_zoom = min(4, mts_chain_zoom + 1);
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text_l(_px1 + 182, _py1, L("ZOOM ") + string(mts_chain_zoom) + "x");
    draw_set_halign(fa_left);
    if (scr_mts_ui_button(_px1 + 206, _py1, _px1 + 222, _py1 + 14, "+", false, _mx, _my, "ZOOM THE PREVIEW IN (1X FITS THE WIDEST MAP)")) {
        mts_chain_zoom = max(1, mts_chain_zoom - 1);
    }
    _py1 += 18;
    var _vert = (_m.chain_dir < 2);
    // slider track: right edge (UP / DOWN) or bottom edge (LEFT / RIGHT)
    var _sb = 12;
    var _tx1 = _px2 - _sb;
    var _ty1 = _py1;
    var _tx2 = _px2;
    var _ty2 = _py2;
    if (_vert) {
        _px2 -= _sb + 4;
    } else {
        _tx1 = _px1;
        _ty1 = _py2 - _sb;
        _py2 -= _sb + 4;
    }
    scr_mts_subpanel(_px1 - 3, _py1 - 3, _x2 - 3, _y2 - 3);
    draw_set_color(c_black);
    draw_rectangle(_px1, _py1, _px2, _py2, false);
    var _sl;
    if (mts_chain_view == 0) {
        _sl = scr_mts_course_slices(_m);
    } else {
        _sl = scr_mts_chain_slices(_m, _ac);
    }
    var _ns   = array_length(_sl);
    var _cross = 1;
    for (var _q = 0; _q < _ns; _q += 1) {
        // widest map in view decides the zoom (sampled on entry starts only)
        if (_q == 0 || _sl[_q][2] != _sl[_q - 1][2]) {
            var _qd = scr_mts_map_dims(_m, _sl[_q][0]);
            if (_vert) {
                _cross = max(_cross, _qd[0]);
            } else {
                _cross = max(_cross, _qd[1]);
            }
        }
    }
    var _span = _py2 - _py1;
    var _side = _px2 - _px1;
    if (!_vert) {
        _span = _px2 - _px1;
        _side = _py2 - _py1;
    }
    var _cs  = clamp(floor(floor(_side / _cross) / mts_chain_zoom), 1, 16);
    var _vis = max(1, floor(_span / _cs));
    var _maxs = max(0, _ns - _vis);
    scr_ui_info(point_in_rectangle(_mx, _my, _px1, _py1, _px2, _py2), "PREVIEW: CLICK A PIECE TO SELECT ITS CHAIN AND MAP. WHEEL SCROLLS (SHIFT: A PAGE)");
    if (point_in_rectangle(_mx, _my, _px1, _py1, _px2, _py2)) {
        var _step = 4;
        if (keyboard_check(vk_shift)) {
            _step = _vis;
        }
        var _fwd_up = (_m.chain_dir == 0 || _m.chain_dir == 2);
        if (mouse_wheel_up()) {
            if (_fwd_up) { mts_chain_scroll += _step; } else { mts_chain_scroll -= _step; }
        }
        if (mouse_wheel_down()) {
            if (_fwd_up) { mts_chain_scroll -= _step; } else { mts_chain_scroll += _step; }
        }
    }
    // ---- slider ----
    var _trk = _ty2 - _ty1;
    if (!_vert) {
        _trk = _tx2 - _tx1;
    }
    var _thumb = max(16, floor(_trk * min(1, _vis / max(1, _ns))));
    scr_ui_info(point_in_rectangle(_mx, _my, _tx1, _ty1, _tx2, _ty2), "CLICK OR DRAG TO SCROLL THE PREVIEW ALONG THE CHAIN");
    if (point_in_rectangle(_mx, _my, _tx1, _ty1, _tx2, _ty2) && mouse_check_button_pressed(mb_left)) {
        mts_chain_drag = true;
    }
    if (!mouse_check_button(mb_left)) {
        mts_chain_drag = false;
    }
    if (mts_chain_drag && _maxs > 0) {
        // where the mouse is along the track -> 0..1 from the chain's start
        var _t = 0;
        if (_vert) {
            _t = (_my - _ty1 - _thumb * 0.5) / max(1, _trk - _thumb);
            if (_m.chain_dir == 0) {
                _t = 1 - _t;          // UP: the start is at the bottom
            }
        } else {
            _t = (_mx - _tx1 - _thumb * 0.5) / max(1, _trk - _thumb);
            if (_m.chain_dir == 2) {
                _t = 1 - _t;          // LEFT: the start is at the right
            }
        }
        mts_chain_scroll = round(clamp(_t, 0, 1) * _maxs);
    }
    mts_chain_scroll = clamp(mts_chain_scroll, 0, _maxs);
    var _tp = 0;
    if (_maxs > 0) {
        _tp = mts_chain_scroll / _maxs;
    }
    if (_m.chain_dir == 0 || _m.chain_dir == 2) {
        _tp = 1 - _tp;
    }
    draw_set_color(make_color_rgb(30, 32, 44));
    draw_rectangle(_tx1, _ty1, _tx2, _ty2, false);
    draw_set_color(make_color_rgb(80, 200, 140));
    if (_vert) {
        var _thy = _ty1 + floor(_tp * (_trk - _thumb));
        draw_rectangle(_tx1 + 2, _thy, _tx2 - 2, _thy + _thumb, false);
    } else {
        var _thx = _tx1 + floor(_tp * (_trk - _thumb));
        draw_rectangle(_thx, _ty1 + 2, _thx + _thumb, _ty2 - 2, false);
    }
    // the active chain's span, marked on the track
    if (mts_chain_view == 0 && _ac >= 0 && _ns > 0) {
        var _as = scr_mts_course_start(_m, _ac);
        var _al = array_length(scr_mts_chain_slices(_m, _ac));
        var _f0 = _as / _ns;
        var _f1 = (_as + _al) / _ns;
        if (_m.chain_dir == 0 || _m.chain_dir == 2) {
            var _ft = _f0;
            _f0 = 1 - _f1;
            _f1 = 1 - _ft;
        }
        draw_set_color(make_color_rgb(255, 220, 80));
        if (_vert) {
            draw_rectangle(_tx1, _ty1 + _f0 * _trk, _tx1 + 2, _ty1 + _f1 * _trk, false);
        } else {
            draw_rectangle(_tx1 + _f0 * _trk, _ty1, _tx1 + _f1 * _trk, _ty1 + 2, false);
        }
    }

    if (_ns == 0) {
        draw_set_color(make_color_rgb(110, 110, 130));
        draw_text_l(_px1 + 8, _py1 + 6, L("EMPTY - + NEW MAKES A CHAIN, PICK A MAP TAB, THEN + MAP"));
    } else {
        var _clip_sx = window_get_width()  / global.gui_w;
        var _clip_sy = window_get_height() / display_get_gui_height();
        gpu_set_scissor(floor(_px1 * _clip_sx), floor(_py1 * _clip_sy), ceil((_px2 - _px1) * _clip_sx), ceil((_py2 - _py1) * _clip_sy));
        scr_mts_glyph_begin();
        for (var _k2 = 0; _k2 < _vis; _k2++) {
            var _s = mts_chain_scroll + _k2;
            if (_s >= _ns) {
                break;
            }
            var _mi   = _sl[_s][0];
            var _line = _sl[_s][1];
            var _md   = scr_mts_map_dims(_m, _mi);
            var _n2   = _md[0];
            if (!_vert) {
                _n2 = _md[1];
            }
            // Where this slice sits: UP / LEFT feed from the far edge
            var _sx = _px1;
            var _sy = _py1;
            if (_m.chain_dir == 0) { _sy = _py2 - (_k2 + 1) * _cs; }
            if (_m.chain_dir == 1) { _sy = _py1 + _k2 * _cs; }
            if (_m.chain_dir == 2) { _sx = _px2 - (_k2 + 1) * _cs; }
            if (_m.chain_dir == 3) { _sx = _px1 + _k2 * _cs; }
            for (var _j = 0; _j < _n2; _j++) {
                var _cx = _sx + _j * _cs;
                var _cy2 = _sy;
                var _ch;
                if (_vert) {
                    _ch = scr_mts_map_char(_m, _mi, _j, _line);
                } else {
                    _cx  = _sx;
                    _cy2 = _sy + _j * _cs;
                    _ch  = scr_mts_map_char(_m, _mi, _line, _j);
                }
                var _bgc = scr_c64_pepto_colour(_gx.bg);
                if (_ch < 0) {
                    draw_set_color(_bgc);
                    draw_rectangle(_cx, _cy2, _cx + _cs - 1, _cy2 + _cs - 1, false);
                    continue;
                }
                var _rc = _ch;
                if (_gx.ecm) {
                    _rc  = _ch mod 64;
                    _bgc = scr_c64_pepto_colour(_gx.ecm_cols[_ch div 64]);
                }
                var _col = 0;
                var _cmc = false;
                if (_ch < array_length(_m.char_lut)) {
                    _col = _m.char_lut[_ch] & 0x0F;
                    if (_gx.mixed && ((_m.char_lut[_ch] >> 4) & 0x01) == 1) {
                        _cmc = true;
                    }
                }
                if (_gx.atlas_ok) {
                    if (_cmc) {
                        scr_mts_draw_glyph(_rc, _cx, _cy2, _cs, _cs, true, _bgc, scr_c64_pepto_colour(_col & 0x07), _gx.mc1, _gx.mc2);
                    } else {
                        var _hc = _col & 0x0F;
                        if (_gx.eff_mixed) {
                            _hc = _col & 0x07;
                        }
                        scr_mts_draw_glyph(_rc, _cx, _cy2, _cs, _cs, false, _bgc, scr_c64_pepto_colour(_hc), _gx.mc1, _gx.mc2);
                    }
                } else {
                    draw_set_color(scr_c64_pepto_colour(_col));
                    draw_rectangle(_cx, _cy2, _cx + _cs - 1, _cy2 + _cs - 1, false);
                }
            }
        }
        scr_mts_glyph_end();
        // Chain / entry boundaries, the selection, and click-to-select
        for (var _k3 = 0; _k3 < _vis; _k3++) {
            var _s3 = mts_chain_scroll + _k3;
            if (_s3 >= _ns) {
                break;
            }
            var _e3 = _sl[_s3][2];
            var _c3 = _sl[_s3][3];
            var _bx1 = _px1;
            var _by1 = _py1;
            var _bx2 = _px2;
            var _by2 = _py2;
            if (_m.chain_dir == 0) { _by1 = _py2 - (_k3 + 1) * _cs; _by2 = _by1 + _cs - 1; }
            if (_m.chain_dir == 1) { _by1 = _py1 + _k3 * _cs;       _by2 = _by1 + _cs - 1; }
            if (_m.chain_dir == 2) { _bx1 = _px2 - (_k3 + 1) * _cs; _bx2 = _bx1 + _cs - 1; }
            if (_m.chain_dir == 3) { _bx1 = _px1 + _k3 * _cs;       _bx2 = _bx1 + _cs - 1; }
            if (_c3 == _ac && mts_chain_view == 0) {
                // the active chain, lightly marked in the course
                draw_set_alpha(0.12);
                draw_set_color(make_color_rgb(80, 200, 255));
                draw_rectangle(_bx1, _by1, _bx2, _by2, false);
                draw_set_alpha(1);
            }
            if (_c3 == _ac && _e3 == mts_chain_sel_entry) {
                draw_set_alpha(0.25);
                draw_set_color(make_color_rgb(255, 220, 80));
                draw_rectangle(_bx1, _by1, _bx2, _by2, false);
                draw_set_alpha(1);
            }
            var _new_chain = (_s3 == 0);
            var _first     = (_s3 == 0);
            if (_s3 > 0) {
                if (_sl[_s3 - 1][3] != _c3) {
                    _new_chain = true;
                    _first     = true;
                } else if (_sl[_s3 - 1][2] != _e3) {
                    _first = true;
                }
            }
            if (_first) {
                // the edge where this entry starts; a new chain gets its name too
                var _emi3 = _sl[_s3][0];
                var _lbl3 = string(_e3) + " " + L("MAP ") + string(_emi3);
                if (_emi3 < array_length(_m.map_names)) {
                    if (_m.map_names[_emi3] != "") {
                        _lbl3 = string(_e3) + " " + _m.map_names[_emi3];
                    }
                }
                if (_new_chain) {
                    _lbl3 = _m.chains[_c3].name + "  /  " + _lbl3;
                    draw_set_color(make_color_rgb(80, 200, 255));
                } else {
                    draw_set_color(make_color_rgb(255, 220, 80));
                }
                var _lcol = draw_get_colour();
                var _ltx  = _px1 + 2;
                var _lty  = _by1 + 1;
                if (_m.chain_dir == 0) {
                    draw_line(_px1, _by2 + 1, _px2, _by2 + 1);
                    _lty = _by2 - 12;
                } else if (_m.chain_dir == 1) {
                    draw_line(_px1, _by1, _px2, _by1);
                } else if (_m.chain_dir == 2) {
                    draw_line(_bx2 + 1, _py1, _bx2 + 1, _py2);
                    _ltx = _bx2 - 60;
                    _lty = _py1 + 2;
                } else {
                    draw_line(_bx1, _py1, _bx1, _py2);
                    _ltx = _bx1 + 2;
                    _lty = _py1 + 2;
                }
                // 50% black backing so the name reads over the map
                draw_set_alpha(0.5);
                draw_set_colour(c_black);
                draw_rectangle(_ltx - 3, _lty - 1, _ltx + string_width_l(_lbl3) + 3, _lty + string_height("X") + 1, false);
                draw_set_alpha(1);
                draw_set_colour(_lcol);
                draw_text_l(_ltx, _lty, _lbl3);
            }
            if (point_in_rectangle(_mx, _my, _bx1, _by1, _bx2, _by2) && mouse_check_button_pressed(mb_left)) {
                // select that chain, entry and map
                if (_c3 != _m.active_chain) {
                    _m.active_chain        = _c3;
                    mts_chain_entry_scroll = 0;
                }
                mts_chain_sel_entry = _e3;
                _m.active_map       = _sl[_s3][0];
            }
        }
        gpu_set_scissor(0, 0, window_get_width(), window_get_height());
        // position readout
        draw_set_color(make_color_rgb(120, 160, 140));
        draw_set_halign(fa_right);
        draw_text_l(_x2 - 6, _y1 + 5, string(mts_chain_scroll) + "/" + string(_ns) + L(" LINES"));
        draw_set_halign(fa_left);
    }
}


/// @desc Chain numbers in the order the list draws them, top row first: the
///       course order, flipped for DIR UP (first chain at the bottom).
function scr_mts_chain_display(_m) {
    var _n   = array_length(_m.chains);
    var _out = array_create(_n, 0);
    for (var _i = 0; _i < _n; _i++) {
        _out[_i] = _i;
        if (_m.chain_dir == 0) {
            _out[_i] = _n - 1 - _i;
        }
    }
    return _out;
}

/// @desc Entry numbers of chain _ci in the order the MAPS list draws them, top
///       row first: feed order (chain_rev = last entry first), flipped for DIR UP.
function scr_mts_entry_display(_m, _ci) {
    var _n   = array_length(_m.chains[_ci].maps);
    var _out = array_create(_n, 0);
    for (var _i = 0; _i < _n; _i++) {
        var _f = _i;                       // _i-th map fed in
        if (_m.chain_rev == 1) {
            _f = _n - 1 - _i;
        }
        var _row = _i;                     // its row on screen
        if (_m.chain_dir == 0) {
            _row = _n - 1 - _i;
        }
        _out[_row] = _f;
    }
    return _out;
}

/// @desc Swap chains _a and _b, renumbering every LINK column that points at them.
function scr_mts_chain_swap(_m, _a, _b) {
    if (_a == _b || _a < 0 || _b < 0 || _a >= array_length(_m.chains) || _b >= array_length(_m.chains)) {
        return;
    }
    var _t = _m.chains[_a];
    _m.chains[_a] = _m.chains[_b];
    _m.chains[_b] = _t;
    for (var _k = 0; _k < array_length(_m.chain_cols); _k++) {
        if (_k >= array_length(_m.chain_col_link)) {
            continue;
        }
        if (_m.chain_col_link[_k] != 1) {
            continue;
        }
        for (var _c = 0; _c < array_length(_m.chains); _c++) {
            if (_k < array_length(_m.chains[_c].cols)) {
                if (_m.chains[_c].cols[_k] == _a) {
                    _m.chains[_c].cols[_k] = _b;
                } else if (_m.chains[_c].cols[_k] == _b) {
                    _m.chains[_c].cols[_k] = _a;
                }
            }
        }
    }
}

/// @desc Delete chain _idx; LINK columns pointing past it move down one.
function scr_mts_chain_delete(_m, _idx) {
    if (_idx < 0 || _idx >= array_length(_m.chains)) {
        return;
    }
    array_delete(_m.chains, _idx, 1);
    for (var _k = 0; _k < array_length(_m.chain_cols); _k++) {
        if (_k >= array_length(_m.chain_col_link)) {
            continue;
        }
        if (_m.chain_col_link[_k] != 1) {
            continue;
        }
        for (var _c = 0; _c < array_length(_m.chains); _c++) {
            if (_k < array_length(_m.chains[_c].cols)) {
                if (_m.chains[_c].cols[_k] > _idx) {
                    _m.chains[_c].cols[_k] = _m.chains[_c].cols[_k] - 1;
                }
            }
        }
    }
}

/// @desc Thin vertical scroll bar for a list. Click or drag on the track to
///       move. Returns the clamped scroll (first visible row).
function scr_mts_list_scrollbar(_x1, _y1, _x2, _y2, _total, _vis, _scroll, _mx, _my) {
    var _max = max(0, _total - _vis);
    var _s   = clamp(_scroll, 0, _max);
    draw_set_color(make_color_rgb(30, 32, 44));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    if (_max <= 0) {
        return _s;
    }
    scr_ui_info(point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2), "CLICK OR DRAG TO SCROLL THE LIST (OR USE THE WHEEL OVER IT)");
    var _h  = _y2 - _y1;
    var _th = max(10, floor(_h * _vis / _total));
    if (point_in_rectangle(_mx, _my, _x1, _y1, _x2, _y2) && mouse_check_button(mb_left)) {
        var _t = (_my - _y1 - _th * 0.5) / max(1, _h - _th);
        _s = round(clamp(_t, 0, 1) * _max);
    }
    var _ty = _y1 + floor((_s / _max) * (_h - _th));
    draw_set_color(make_color_rgb(80, 200, 140));
    draw_rectangle(_x1 + 1, _ty, _x2 - 1, _ty + _th, false);
    return _s;
}


/// @desc A framed sub-panel background for the CHAINS panel sections.
function scr_mts_subpanel(_x1, _y1, _x2, _y2) {
    draw_set_color(make_color_rgb(16, 19, 28));
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_color(make_color_rgb(45, 70, 80));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
}
