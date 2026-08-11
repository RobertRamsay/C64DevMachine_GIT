function scr_draw_memory_bar(_x1, _x2, _y) {
    // Clear the cross-object hover every frame. Nodes and the asset list use
    // these values only to draw a non-destructive ownership highlight.
    global.memory_bar_hover_node  = noone;
    global.memory_bar_hover_asset = -1;
	if obj_asset_manager.viewer_open exit
    var _map_w      = _x2 - _x1;
    var _map_h      = 15;
    var _addr_total = 65536;
    var _pulse      = abs(sin(current_time * 0.01));

    var _labels_visible = false;
    if (global.gui_mouse_y > 1000 and global.gui_mouse_x > 500) {
        _labels_visible = true;
    }

    draw_sprite_ext(spr_baseGradient, 0,
        0, _y + _map_h + 25,
        1920/sprite_get_width(spr_baseGradient), 1.6, 0, c_white, 1);

    // --- DANGER ZONES ---
    var _danger_zones = [
        [0x0000, 0x07FF, "FIXED"],
        [0xA000, 0xBFFF, "BASIC"],
        [0xD000, 0xFFFF, "KERNAL"]
    ];

    // -------------------------------------------------------
    // BASE BAR
    // -------------------------------------------------------
    draw_set_color(make_color_rgb(50, 60, 130));
    draw_rectangle(_x1, _y, _x2, _y + _map_h, false);

    // -------------------------------------------------------
    // DANGER ZONES
    // -------------------------------------------------------
    var _danger_r = 180;
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);

    var _fx1 = _x1 + (0x0000 / _addr_total) * _map_w;
    var _fx2 = _x1 + (0x07FF / _addr_total) * _map_w;
    draw_set_color(make_color_rgb(_danger_r, 30, 30));
    draw_rectangle(_fx1, _y, _fx2, _y + _map_h, false);
    draw_set_color(make_color_rgb(60, 0, 0));
    draw_text((_fx1 + _fx2) / 2, _y + _map_h / 2, "LOCKED");

    var _bx1 = _x1 + (0xA000 / _addr_total) * _map_w;
    var _bx2 = _x1 + (0xBFFF / _addr_total) * _map_w;
    draw_set_color(global.basic_unlocked ? make_color_rgb(40, 90, 110) : make_color_rgb(_danger_r, 30, 30));
    draw_rectangle(_bx1, _y, _bx2, _y + _map_h, false);
    draw_set_color(global.basic_unlocked ? make_color_rgb(80, 200, 220) : make_color_rgb(160, 160, 180));
    var _basic_locked_txt = "MACRO CONTROLLED";
    if (global.lite) {
        _basic_locked_txt = "MACRO CONTROLLED (PRO ONLY)";
    }
    draw_text((_bx1 + _bx2) / 2, _y + _map_h / 2, global.basic_unlocked ? "UNLOCKED" : _basic_locked_txt);

    var _kx1 = _x1 + (0xD000 / _addr_total) * _map_w;
    var _kx2 = _x1 + (0xFFFF / _addr_total) * _map_w;
    draw_set_color(global.kernal_unlocked ? make_color_rgb(40, 90, 110) : make_color_rgb(_danger_r, 30, 30));
    draw_rectangle(_kx1, _y, _kx2, _y + _map_h, false);
    draw_set_color(global.kernal_unlocked ? make_color_rgb(80, 200, 220) : make_color_rgb(160, 160, 180));
    var _kernal_locked_txt = "MACRO CONTROLLED";
    if (global.lite) {
        _kernal_locked_txt = "MACRO CONTROLLED (PRO ONLY)";
    }
    draw_text((_kx1 + _kx2) / 2, _y + _map_h / 2, global.kernal_unlocked ? "UNLOCKED" : _kernal_locked_txt);

    draw_set_halign(fa_left);
    draw_set_valign(fa_top);

    // -------------------------------------------------------
    // NODE CHAIN BLOCK (green)
    // -------------------------------------------------------
    if (!ds_list_empty(global.node_chain)) {
        var _first = ds_list_find_value(global.node_chain, 0);
        var _last  = ds_list_find_value(global.node_chain, ds_list_size(global.node_chain) - 1);
        if (instance_exists(_first) && instance_exists(_last)) {
            var _cbx1 = _x1 + (_first.pc_address / _addr_total) * _map_w;
            var _cbx2 = _x1 + ((_last.pc_address + _last.total_node_size) / _addr_total) * _map_w;
            draw_set_color(make_color_rgb(30, 200, 40));
            draw_rectangle(_cbx1, _y, _cbx2, _y + _map_h, false);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(30, 200, 40));
            draw_set_halign(fa_center);
            draw_line(_cbx1, _y - 10, _cbx1, _y);
            var _sh = string_upper(decimal_to_hex(_first.pc_address));
            while (string_length(_sh) < 4) _sh = "0" + _sh;
            draw_text(_cbx1, _y - 22, "$" + _sh);
            draw_set_halign(fa_left);
        }
    }

// -------------------------------------------------------
    // USE CACHED SEGMENTS & CONFLICTS
    // Rebuilt by scr_build_memory_bar_cache() which is called
    // at the end of scr_c64_do_update_addresses().
    // -------------------------------------------------------
    if (global.memory_bar_dirty) {
        scr_build_memory_bar_cache();
    }
    var _segments  = global.memory_bar_segments;
    var _conflicts = global.memory_bar_conflicts;
    var _seg_total = array_length(_segments);

    // -------------------------------------------------------
    // VIC BANK BRACKETS
    // -------------------------------------------------------
    var _by   = _y + _map_h + 4;
    var _leg  = 6;
    var _bcol = make_color_rgb(80, 220, 255);
    draw_set_font(fnt_c64_tiny);

    for (var _vb = 0; _vb < 4; _vb++) {
        var _bank_start = _vb * 0x4000;
        var _bank_end   = _bank_start + 0x3FFF;
        var _vbx1 = _x1 + (_bank_start / _addr_total) * _map_w;
        var _vbx2 = _x1 + (_bank_end   / _addr_total) * _map_w;
        draw_set_color(_bcol);
        draw_set_alpha(0.8);
        draw_line(_vbx1, _by, _vbx2, _by);
        draw_line(_vbx1, _by, _vbx1, _by + _leg);
        draw_line(_vbx2, _by, _vbx2, _by + _leg);
        draw_set_alpha(1.0);
        draw_set_halign(fa_center);
        draw_set_color(_bcol);
        draw_text((_vbx1 + _vbx2) / 2, _by + _leg - 3, "VIC BANK " + string(_vb));
        draw_set_halign(fa_left);
    }

    // -------------------------------------------------------
    // DRAW CONFLICT LABELS
    // -------------------------------------------------------
    draw_set_font(fnt_c64_tiny);
    var _drawn_conflicts_x = [];
    var _cfl_total = array_length(_conflicts);

    for (var _ci = 0; _ci < _cfl_total; _ci++) {
        var _cf     = _conflicts[_ci];

        // Skip rendering if this conflict range is in the user's ignore list.
        // The conflict can still exist internally (flagging children etc.) —
        // we just don't draw the warning bracket/label/yellow flash for it.
        var _cf_ignored = false;
        if (variable_global_exists("ignored_conflicts")) {
            var _ilen = array_length(global.ignored_conflicts);
            for (var _ii = 0; _ii < _ilen; _ii++) {
                var _ie = global.ignored_conflicts[_ii];
                // Match if the current conflict range falls inside (or equals)
                // any ignored range — covers slight start/end drift between
                // pair-by-pair ranges and the original suppressed range.
                if (_cf.start >= _ie.range_start && _cf.finish <= _ie.range_end) {
                    _cf_ignored = true;
                    break;
                }
                // Also match if they share the same exact range
                if (_cf.start == _ie.range_start && _cf.finish == _ie.range_end) {
                    _cf_ignored = true;
                    break;
                }
            }
        }
        if (_cf_ignored) continue;

        var _cx1    = _x1 + (_cf.start  / _addr_total) * _map_w;
        var _cx2    = _x1 + (_cf.finish / _addr_total) * _map_w;
        var _cx_mid = (_cx1 + _cx2) / 2;

        draw_set_alpha(0.5 + (0.4 * _pulse));
        draw_set_color(c_yellow);
        draw_rectangle(_cx1, _y, _cx2, _y + _map_h, false);
        draw_set_alpha(1.0);

        var _bracket_y = _y - 8;
        var _clash_col = (variable_struct_exists(_cf, "is_var_clash") && _cf.is_var_clash) ? make_color_rgb(255, 100, 255) : c_yellow;
        draw_set_color(_clash_col);
        draw_line(_cx1, _bracket_y, _cx2, _bracket_y);
        draw_line(_cx1, _bracket_y, _cx1, _y);
        draw_line(_cx2, _bracket_y, _cx2, _y);

        // Gather names/types/lines from cached segments
        // Two-pass: containers (INIT BLOCK / ORG aggregates) first, then child segments.
        // This prevents the label from showing two near-identical child names when
        // the actual interesting conflict is a container-vs-container clash.
        var _names     = [];
        var _types     = [];
        var _lines_arr = [];

        for (var _pass = 0; _pass < 2; _pass++) {
            for (var _si = 0; _si < _seg_total; _si++) {
                var _seg = _segments[_si];
                if (!_seg.conflict) continue;
                if (_seg.addr > _cf.finish || (_seg.addr + _seg.size) < _cf.start) continue;

                // Container check: INIT BLOCK label, or anything with "AT $" suffix (ORG aggregate)
                var _is_container = (string_pos("INIT BLOCK", _seg.name) > 0 ||
                                     string_pos(" AT $",      _seg.name) > 0);

                if (_pass == 0 && !_is_container) continue;
                if (_pass == 1 &&  _is_container) continue;

                var _nm = _seg.name;
                var _ty = _seg.type;
                var _ln = _seg.lines;

                var _found_idx = -1;
                var _nl = array_length(_names);
                for (var _n = 0; _n < _nl; _n++) {
                    if (_names[_n] == _nm) { _found_idx = _n; break; }
                }

                if (_found_idx == -1) {
                    array_push(_names,     _nm);
                    array_push(_types,     _ty);
                    array_push(_lines_arr, _ln);
                } else {
                    var _lnl = array_length(_ln);
                    for (var _l = 0; _l < _lnl; _l++) {
                        var _ex  = false;
                        var _xll = array_length(_lines_arr[_found_idx]);
                        for (var _xl = 0; _xl < _xll; _xl++) {
                            if (_lines_arr[_found_idx][_xl] == _ln[_l]) { _ex = true; break; }
                        }
                        if (!_ex) array_push(_lines_arr[_found_idx], _ln[_l]);
                    }
                }
            }
        }

        var _name1  = array_length(_names)     > 0 ? _names[0]     : "UNKNOWN";
        var _type1  = array_length(_types)     > 0 ? _types[0]     : "CODE";
        var _lines1 = array_length(_lines_arr) > 0 ? _lines_arr[0] : [];
        var _name2  = array_length(_names)     > 1 ? _names[1]     : "";
        var _type2  = array_length(_types)     > 1 ? _types[1]     : "";
        var _lines2 = array_length(_lines_arr) > 1 ? _lines_arr[1] : [];

        var _ln_str1 = "";
        if (array_length(_lines1) > 0) {
            _ln_str1 = " - LINES: ";
            var _max1 = min(6, array_length(_lines1));
            for (var _l = 0; _l < _max1; _l++)
                _ln_str1 += string(_lines1[_l]) + ((_l < _max1 - 1) ? "," : "");
            if (array_length(_lines1) > 6) _ln_str1 += "...";
        }

        var _ln_str2 = "";
        if (array_length(_lines2) > 0) {
            _ln_str2 = " - LINES: ";
            var _max2 = min(6, array_length(_lines2));
            for (var _l = 0; _l < _max2; _l++)
                _ln_str2 += string(_lines2[_l]) + ((_l < _max2 - 1) ? "," : "");
            if (array_length(_lines2) > 6) _ln_str2 += "...";
        }

        var _type1_clean = (_type1 == "VARIABLE_BLOCK") ? "VARS" : ((_type1 == "NODE") ? "CODE" : _type1);
        var _type2_clean = (_type2 == "VARIABLE_BLOCK") ? "VARS" : ((_type2 == "NODE") ? "CODE" : _type2);

        var _str_part1 = "CONFLICT: " + _type1_clean + ": \"" + _name1 + "\"" + _ln_str1;
        var _str_part2 = (_name2 != "") ? " (with) " : "";
        var _str_part3 = (_name2 != "") ? _type2_clean + ": \"" + _name2 + "\"" + _ln_str2 : "";
        var _full_label = _str_part1 + _str_part2 + _str_part3;

        var _text_y = _y - 160;
        var _dcl = array_length(_drawn_conflicts_x);
        for (var _d = 0; _d < _dcl; _d++) {
            if (abs(_cx_mid - _drawn_conflicts_x[_d].x) < 400) {
                _text_y = _drawn_conflicts_x[_d].y - 35;
            }
        }
        array_push(_drawn_conflicts_x, { x: _cx_mid, y: _text_y });

        draw_set_color(c_yellow);
        draw_set_alpha(0.4);
        draw_line_width(_cx_mid, _text_y + 10, _cx_mid, _y, 2);
        draw_line(_cx_mid, _text_y + 10, _cx1, _y);
        draw_line(_cx_mid, _text_y + 10, _cx2, _y);
        draw_set_alpha(1.0);

        draw_set_halign(fa_left);
        var _total_w = string_width(_full_label);
        var _start_x = clamp(_cx_mid - (_total_w / 2), _x1 + 8, (_x2 - 222) - _total_w - 8);

        var _pad = 5;
        var _lh  = string_height(_full_label);
        var _lbx1 = _start_x - _pad;
        var _lby1 = _text_y  - _pad - 6;
        var _lbx2 = _start_x + _total_w + _pad;
        var _lby2 = _text_y  + _lh - 2;

        var _ring_pulse = 0.3 + (0.3 * _pulse);
        for (var _ri = 4; _ri >= 1; _ri--) {
            draw_set_alpha(_ring_pulse * (_ri / 4));
            draw_set_color(make_color_rgb(200, 40, 40));
            draw_rectangle(_lbx1 - _ri * 2, _lby1 - _ri * 2, _lbx2 + _ri * 2, _lby2 + _ri * 2, true);
        }
        draw_set_alpha(1.0);
        draw_set_color(c_black);
        draw_rectangle(_lbx1, _lby1, _lbx2, _lby2, false);
        draw_set_color(make_color_rgb(200, 40, 40));
        draw_rectangle(_lbx1, _lby1, _lbx2, _lby2, true);

        draw_set_color(c_yellow);
        draw_text(_start_x, _text_y - 6, _str_part1);
        if (_name2 != "") {
            var _px2 = _start_x + string_width(_str_part1);
            draw_set_color(make_color_rgb(255, 60, 60));
            draw_text(_px2, _text_y - 6, _str_part2);
            draw_set_color(c_yellow);
            draw_text(_px2 + string_width(_str_part2), _text_y - 6, _str_part3);
        }

        // CLICK DETECTION: open conflict-options popup on label click
        if (!global.conflict_popup_open &&
            mouse_check_button_pressed(mb_left) &&
            point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y, _lbx1, _lby1, _lbx2, _lby2)) {

            // Find the two distinct *container* owners (INIT BLOCK / ORG aggregate)
            // inside this conflict range. Skip per-instruction children — they all
            // sit at the same world position as the parent ORG and would make
            // "Go Right" useless. Two-pass: containers first, fall back to any
            // owner if no container is present.
            var _owner_a = noone;
            var _owner_b = noone;
            var _asset_a_name = "";
            var _asset_b_name = "";

            for (var _pass = 0; _pass < 2; _pass++) {
                for (var _osi = 0; _osi < _seg_total; _osi++) {
                    var _oseg = _segments[_osi];
                    if (!_oseg.conflict) continue;
                    if (_oseg.addr > _cf.finish || (_oseg.addr + _oseg.size) < _cf.start) continue;

                    // Asset segments have node_id = noone — track them separately
                    // so the popup can show an "asset clash" notice rather than
                    // a broken Go-Left / Go-Right pair.
                    if (_oseg.node_id == noone) {
                        if (_asset_a_name == "") _asset_a_name = _oseg.name;
                        else if (_oseg.name != _asset_a_name && _asset_b_name == "") _asset_b_name = _oseg.name;
                        continue;
                    }
                    if (!instance_exists(_oseg.node_id)) continue;

                    var _is_container = (string_pos("INIT BLOCK", _oseg.name) > 0 ||
                                         string_pos(" AT $",      _oseg.name) > 0);
                    if (_pass == 0 && !_is_container) continue;
                    if (_pass == 1 &&  _is_container) continue;

                    if (_owner_a == noone) { _owner_a = _oseg.node_id; continue; }
                    if (_oseg.node_id != _owner_a) { _owner_b = _oseg.node_id; break; }
                }
                if (_owner_a != noone && _owner_b != noone) break;
            }

            global.conflict_popup_open        = true;
            global.conflict_popup_x           = global.gui_mouse_x;
            global.conflict_popup_y           = global.gui_mouse_y;
            global.conflict_popup_owner_a     = _owner_a;
            global.conflict_popup_owner_b     = _owner_b;
            global.conflict_popup_asset_a     = _asset_a_name;
            global.conflict_popup_asset_b     = _asset_b_name;
            global.conflict_popup_range_start = _cf.start;
            global.conflict_popup_range_end   = _cf.finish;
        }
    }
    draw_set_alpha(1.0);

	// -------------------------------------------------------
    // DRAW SEGMENT BARS
    // Load_later (LO-tagged) asset segments render at reduced alpha
    // with a "DISK" tag above so users can see they live on disk and
    // are pulled into RAM on demand by MACRO_LOADER — they share the
    // address with whatever is currently resident there.
    // -------------------------------------------------------
    var _bar_mx       = global.gui_mouse_x;
    var _bar_my       = global.gui_mouse_y;
    var _bar_hovered  = point_in_rectangle(_bar_mx, _bar_my, _x1, _y, _x2, _y + _map_h);
    var _hover_addr   = -1;
    var _hover_seg_i  = -1;
    var _hover_seg    = noone;

    if (_bar_hovered) {
        _hover_addr = clamp(floor(((_bar_mx - _x1) / _map_w) * _addr_total), 0, 65535);

        // Later segments are painted over earlier ones, so search backwards and
        // report exactly the allocation the pointer appears to be resting on.
        for (var _hsi = _seg_total - 1; _hsi >= 0; _hsi--) {
            var _hs = _segments[_hsi];
            if (_hover_addr >= _hs.addr && _hover_addr < _hs.addr + max(1, _hs.size)) {
                _hover_seg_i = _hsi;
                _hover_seg   = _hs;
                break;
            }
        }

        if (is_struct(_hover_seg)) {
            if (variable_struct_exists(_hover_seg, "node_id") &&
                instance_exists(_hover_seg.node_id)) {
                global.memory_bar_hover_node = _hover_seg.node_id;
            } else if (variable_struct_exists(_hover_seg, "asset_index")) {
                global.memory_bar_hover_asset = _hover_seg.asset_index;
            }
        }
    }

    for (var _si = 0; _si < _seg_total; _si++) {
        var _seg = _segments[_si];
        var _sx1 = _x1 + (_seg.addr / _addr_total) * _map_w;
        var _sx2 = _x1 + ((_seg.addr + _seg.size) / _addr_total) * _map_w;
        if (_sx2 - _sx1 < 2) _sx2 = _sx1 + 2;

        var _seg_is_disk = variable_struct_exists(_seg, "load_later") && _seg.load_later;

        if (_seg_is_disk) {
            draw_set_alpha(0.35);
            draw_set_color(_seg.col);
            draw_rectangle(_sx1, _y, _sx2, _y + _map_h, false);
            draw_set_alpha(0.8);
            draw_set_color(_seg.col);
            draw_rectangle(_sx1, _y, _sx2, _y + _map_h, true);
            draw_set_alpha(1.0);
        } else {
            draw_set_color(_seg.col);
            draw_rectangle(_sx1, _y, _sx2, _y + _map_h, false);
        }

        if (_si == _hover_seg_i) {
            draw_set_alpha(1.0);
            draw_set_color(c_white);
            draw_rectangle(_sx1 - 1, _y - 2, _sx2 + 1, _y + _map_h + 2, true);
        }
    }

    // Second pass: draw DISK tag labels above ghosted segments so they
    // sit on top of every other segment fill (avoids overdraw obscuring them).
    draw_set_font(fnt_c64_tiny);
    for (var _si = 0; _si < _seg_total; _si++) {
        var _seg = _segments[_si];
        if (!variable_struct_exists(_seg, "load_later") || !_seg.load_later) continue;
        var _sx1 = _x1 + (_seg.addr / _addr_total) * _map_w;
        var _sx2 = _x1 + ((_seg.addr + _seg.size) / _addr_total) * _map_w;
        if (_sx2 - _sx1 < 18) continue;  // Too narrow to label
        var _seg_mid = (_sx1 + _sx2) / 2;
        draw_set_halign(fa_center);
        draw_set_color(make_color_rgb(255, 220, 80));
        draw_text(_seg_mid, _y + _map_h - 9, "DISK");
        draw_set_halign(fa_left);
    }
    // -------------------------------------------------------
    // NAMED BLOCK LABELS
    // -------------------------------------------------------
    draw_set_font(fnt_c64_pico);
    draw_set_halign(fa_center);

    if (!ds_list_empty(global.node_chain)) {
        var _first = ds_list_find_value(global.node_chain, 0);
        if (instance_exists(_first)) {
            var _ix = _x1 + (_first.pc_address / _addr_total) * _map_w;
            draw_set_color(make_color_rgb(30, 200, 40));
            draw_text(_ix + 4, _y + _map_h + 5, "INIT");
        }
    }

    with (obj_c64_node) {
        if (!is_connected) continue;
        if (node_type == "ORG" && end_address > pc_address) {
            if (node_title == "HW REGISTERS") {
                var _hx = _x1 + (pc_address / _addr_total) * _map_w;
                draw_set_color(make_color_rgb(70, 100, 105));
                draw_text(_hx + 4, _y + _map_h + 5, "HW VARS");
            } else if (node_title == "VARIABLES") {
                var _vx = _x1 + (pc_address / _addr_total) * _map_w;
                draw_set_color(make_color_rgb(60, 140, 200));
                draw_text(_vx + 4, _y + _map_h + 5, "UV VARS");
            }
        }
    }
    draw_set_halign(fa_left);

    // Outline
    draw_set_color(make_color_rgb(80, 90, 160));
    draw_rectangle(_x1, _y, _x2, _y + _map_h, true);

    // -------------------------------------------------------
    // DISK (LOAD_ORG) ASSET STRIPE — 3px yellow below the bar
    // -------------------------------------------------------
    if (variable_global_exists("memory_bar_disk_assets")) {
        var _stripe_y = _y + _map_h + 2;
        var _stripe_h = 3;
        var _disk_total = array_length(global.memory_bar_disk_assets);
        for (var _dsi = 0; _dsi < _disk_total; _dsi++) {
            var _ds2 = global.memory_bar_disk_assets[_dsi];
            var _dsx1 = _x1 + (_ds2.addr / _addr_total) * _map_w;
            var _dsx2 = _x1 + ((_ds2.addr + _ds2.size) / _addr_total) * _map_w;
            if (_dsx2 - _dsx1 < 2) { _dsx2 = _dsx1 + 2; }
            draw_set_color(make_color_rgb(255, 220, 50));
            draw_set_alpha(0.85);
            draw_rectangle(_dsx1, _stripe_y, _dsx2, _stripe_y + _stripe_h, false);
            draw_set_alpha(1.0);

            if (point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y, _dsx1, _stripe_y - 20, _dsx2, _stripe_y + _stripe_h)) {
                draw_set_font(fnt_c64_tiny);
                draw_set_halign(fa_left);
                var _addr_lo_hex = string_upper(decimal_to_hex(_ds2.addr));
                while (string_length(_addr_lo_hex) < 4) _addr_lo_hex = "0" + _addr_lo_hex;
                var _addr_hi_hex = string_upper(decimal_to_hex(_ds2.addr + _ds2.size - 1));
                while (string_length(_addr_hi_hex) < 4) _addr_hi_hex = "0" + _addr_hi_hex;
                var _stripe_label = _ds2.load_org_name + " : " + _ds2.name + " AT $" + _addr_lo_hex + "-$" + _addr_hi_hex;
                draw_set_color(make_color_rgb(255, 220, 50));
                draw_text(_dsx1, _stripe_y - string_height(_stripe_label) - 1, _stripe_label);
            }
        }
    }

    // -------------------------------------------------------
    // REGION LABELS
    // -------------------------------------------------------
    var _c_red  = make_color_rgb(200, 50, 40);
    var _c_grey = make_color_rgb(160, 160, 160);
    draw_set_font(fnt_c64_tiny);

    var _full_bank = [
        [0x0000, "ZERO PAGE",   0],
        [0x0100, "STACK",       0],
        [0x0200, "OS VECTORS",  0],
        [0x0400, "SCREEN",      0],
        [0x0800, "BASIC RAM",   0],
        [0x1000, "MUSIC/DATA",  0],
        [0x3000, "GFX DATA",    0],
        [0x4000, "BITMAP",      0],
        [0x6000, "+SCRCOL",     0],
        [0x2800, "GFX DATA",    0],
        [0x8000, "MAP/DATA",    0],
        [0xA000, "BASIC ROM",   0],
        [0xC000, "HIGH RAM",    0],
        [0xD000, "I/O-CHAR",  -20],
        [0xE000, "KERNAL",    -40]
    ];

   var _last_px = -100;
    var _base_y  = 27;
    var _stagger = 18;
    var _clash_n = 0;
    var _fbl = array_length(_full_bank);
    for (var _i = 0; (_i < _fbl) && _labels_visible; _i++) {
        var _addr  = _full_bank[_i][0];
        var _label = _full_bank[_i][1];
        var _nudge = _full_bank[_i][2];
        var _px    = _x1 + ((_addr / 65535.0) * _map_w);
        _clash_n   = (_px - _last_px < 160) ? _clash_n + 1 : 0;
        var _off_y = _base_y + (_clash_n * _stagger) + ((_addr == 0xD000) ? 15 : 0) + _nudge;
        var _fy    = _y - _off_y;
        draw_set_color(c_aqua);
        draw_set_alpha(0.4);
        draw_line(_px, _y, _px, _fy + 10);
        draw_set_alpha(1.0);
        var _hex_str = "$" + string_upper(decimal_to_hex(_addr));
        draw_set_color(_c_grey); draw_text(_px + 4, _fy, _hex_str);
        draw_set_color(_c_red);  draw_text(_px + 4 + string_width(_hex_str), _fy, ":" + _label);
        _last_px = _px;
    }

    // -------------------------------------------------------
    // SPRITE POINTER TABLE MARKERS
    // -------------------------------------------------------
    if (instance_exists(obj_asset_manager) && _labels_visible) {
        var _am_spr = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am_spr.asset_list); _ai++) {
            var _a = ds_list_find_value(_am_spr.asset_list, _ai);
            if (_a.type != "SPRITE_SET") continue;
            if (!buffer_exists(_a.buffer)) continue;
            // Sprite pointer table lives at active screen RAM + $03F8.
            // Resolve screen RAM from MACRO_VIC so the marker tracks the real bank.
            var _scr_ram = scr_resolve_screen_ram();
            var _ptr_base = _scr_ram + 0x03F8;
            var _px1 = _x1 + (_ptr_base       / _addr_total) * _map_w;
            var _px2 = _x1 + ((_ptr_base + 8) / _addr_total) * _map_w;
            if (_px2 - _px1 < 2) _px2 = _px1 + 2;
            draw_set_color(make_color_rgb(255, 250, 0));
            draw_set_alpha(0.85);
            draw_rectangle(_px1, _y, _px2, _y + _map_h, false);
            draw_set_alpha(1.0);
            draw_set_color(make_color_rgb(255, 250, 0));
            draw_line(_px1, _y - 4, _px1, _y);
            draw_set_font(fnt_c64_tiny);
            draw_set_halign(fa_left);
            var _ptr_hex = "$" + string_upper(decimal_to_hex(_ptr_base));
            draw_set_color(make_color_rgb(255, 250, 80));
            draw_text(_px1 + 2, _y - 18, _ptr_hex + " SPR PTRS");
        }
    }



    // -------------------------------------------------------
    // HOVER CURSOR
    // -------------------------------------------------------
    var _gui_mx = global.gui_mouse_x;
    var _gui_my = global.gui_mouse_y;
    if (_gui_my >= _y - 15 && _gui_my <= _y + _map_h + 5 &&
        _gui_mx >= _x1 && _gui_mx <= _x2) {
        var _cursor_addr = floor(((_gui_mx - _x1) / _map_w) * _addr_total);
        var _hover_hex  = string_upper(decimal_to_hex(_cursor_addr));
        while (string_length(_hover_hex) < 4) _hover_hex = "0" + _hover_hex;
        draw_set_color(c_white);
        draw_set_alpha(0.8);
        draw_line(_gui_mx, _y - 15, _gui_mx, _y + _map_h);
        draw_set_alpha(1.0);
        draw_set_halign(fa_center);
        draw_text(_gui_mx, _y - 36, "$" + _hover_hex);

        if (_bar_hovered && is_struct(_hover_seg)) {
            var _owner_kind = _hover_seg.type;
            if (_owner_kind == "NODE" || _owner_kind == "CODE") _owner_kind = "CODE";
            else if (_owner_kind == "VARIABLE_BLOCK") _owner_kind = "VARS";
            var _owner_text = _owner_kind + ": " + _hover_seg.name;
            draw_set_color(c_white);
            draw_text(_gui_mx, _y - 52, _owner_text);
        }
        draw_set_halign(fa_left);
    }

    // Navigate from the allocation itself. A node is centred in the workspace;
    // an asset opens in the normal asset viewer. The click is consumed so it
    // cannot also trigger controls behind the Draw-GUI memory bar.
    if (_bar_hovered && is_struct(_hover_seg) &&
        mouse_check_button_pressed(mb_left) &&
        !global.ui_click_consumed && !global.conflict_popup_open) {
        if (variable_struct_exists(_hover_seg, "node_id") &&
            instance_exists(_hover_seg.node_id)) {
            scr_focus_camera_on_node(_hover_seg.node_id);
            global.ui_click_consumed = true;
        } else if (variable_struct_exists(_hover_seg, "asset_index") &&
                   instance_exists(obj_asset_manager)) {
            var _open_ai = _hover_seg.asset_index;
            if (_open_ai >= 0 && _open_ai < ds_list_size(obj_asset_manager.asset_list)) {
                obj_asset_manager.viewer_asset  = _open_ai;
                obj_asset_manager.viewer_open   = true;
                obj_asset_manager.bb_return_asset = -1;
                keyboard_string = "";
                global.ui_click_consumed = true;
            }
        }
    }

    // -------------------------------------------------------
    // DANGER ZONE CLICK - UNLOCK INJECTION (REMOVED)
    // Banking is now driven by the BANK_SWITCH macro node. The memory bar
    // reflects state read-only; clicking the BASIC/KERNAL zones does nothing.
    // -------------------------------------------------------
	
	// -------------------------------------------------------
    // CONFLICT-OPTIONS POPUP
    // -------------------------------------------------------
    if (global.conflict_popup_open) {
        // Detect "asset involved" — one or both sides of this conflict are assets,
        // which the asset manager owns rather than a placeable node.
        var _has_asset = (global.conflict_popup_asset_a != "" ||
                          global.conflict_popup_asset_b != "");
        // Left button is only useful if we found a node container for owner_a.
        // Right button likewise for owner_b.
        var _can_go_left  = instance_exists(global.conflict_popup_owner_a);
        var _can_go_right = instance_exists(global.conflict_popup_owner_b);

        var _pw  = 200;
        var _bh  = 22;
        var _gap = 4;
        var _note_h = _has_asset ? 34 : 0;
        var _ph  = (_bh * 3) + (_gap * 4) + _note_h;
        var _ppx1 = global.conflict_popup_x;
        var _ppy1 = global.conflict_popup_y;
        var _ppx2 = _ppx1 + _pw;
        var _ppy2 = _ppy1 + _ph;

        // Background
        draw_set_color(make_color_rgb(20, 20, 30));
        draw_rectangle(_ppx1, _ppy1, _ppx2, _ppy2, false);
        draw_set_color(c_yellow);
        draw_rectangle(_ppx1, _ppy1, _ppx2, _ppy2, true);

        var _btn_x1 = _ppx1 + _gap;
        var _btn_x2 = _ppx2 - _gap;
        var _b_ignore_y = _ppy1 + _gap;
        var _b_left_y   = _b_ignore_y + _bh + _gap;
        var _b_right_y  = _b_left_y   + _bh + _gap;
        var _note_y     = _b_right_y  + _bh + _gap;

        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);

        // Button: Ignore (always available)
        var _hov_ig = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
                                         _btn_x1, _b_ignore_y, _btn_x2, _b_ignore_y + _bh);
        draw_set_color(_hov_ig ? make_color_rgb(120, 80, 30) : make_color_rgb(60, 40, 20));
        draw_rectangle(_btn_x1, _b_ignore_y, _btn_x2, _b_ignore_y + _bh, false);
        draw_set_color(c_yellow);
        draw_rectangle(_btn_x1, _b_ignore_y, _btn_x2, _b_ignore_y + _bh, true);
        draw_text((_btn_x1 + _btn_x2) / 2, _b_ignore_y + (_bh / 2), "IGNORE THIS CONFLICT");

        // Button: Go Left — disabled if owner is an asset (no node to pan to)
        var _hov_l = false;
        if (_can_go_left) {
            _hov_l = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
                                        _btn_x1, _b_left_y, _btn_x2, _b_left_y + _bh);
            draw_set_color(_hov_l ? make_color_rgb(40, 100, 140) : make_color_rgb(20, 60, 90));
            draw_rectangle(_btn_x1, _b_left_y, _btn_x2, _b_left_y + _bh, false);
            draw_set_color(c_aqua);
            draw_rectangle(_btn_x1, _b_left_y, _btn_x2, _b_left_y + _bh, true);
            draw_text((_btn_x1 + _btn_x2) / 2, _b_left_y + (_bh / 2), "GO TO LEFT SIDE");
        } else {
            draw_set_color(make_color_rgb(40, 40, 50));
            draw_rectangle(_btn_x1, _b_left_y, _btn_x2, _b_left_y + _bh, false);
            draw_set_color(make_color_rgb(100, 100, 100));
            draw_rectangle(_btn_x1, _b_left_y, _btn_x2, _b_left_y + _bh, true);
            draw_text((_btn_x1 + _btn_x2) / 2, _b_left_y + (_bh / 2), "(LEFT IS AN ASSET)");
        }

        // Button: Go Right — disabled if owner is an asset
        var _hov_r = false;
        if (_can_go_right) {
            _hov_r = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
                                        _btn_x1, _b_right_y, _btn_x2, _b_right_y + _bh);
            draw_set_color(_hov_r ? make_color_rgb(40, 100, 140) : make_color_rgb(20, 60, 90));
            draw_rectangle(_btn_x1, _b_right_y, _btn_x2, _b_right_y + _bh, false);
            draw_set_color(c_aqua);
            draw_rectangle(_btn_x1, _b_right_y, _btn_x2, _b_right_y + _bh, true);
            draw_text((_btn_x1 + _btn_x2) / 2, _b_right_y + (_bh / 2), "GO TO RIGHT SIDE");
        } else {
            draw_set_color(make_color_rgb(40, 40, 50));
            draw_rectangle(_btn_x1, _b_right_y, _btn_x2, _b_right_y + _bh, false);
            draw_set_color(make_color_rgb(100, 100, 100));
            draw_rectangle(_btn_x1, _b_right_y, _btn_x2, _b_right_y + _bh, true);
            draw_text((_btn_x1 + _btn_x2) / 2, _b_right_y + (_bh / 2), "(RIGHT IS AN ASSET)");
        }

        // Asset notice — explains the disabled buttons
        if (_has_asset) {
            draw_set_color(make_color_rgb(200, 180, 80));
            draw_text((_btn_x1 + _btn_x2) / 2, _note_y + 6, "ASSET CLASH");
            draw_set_color(make_color_rgb(160, 160, 160));
            var _asset_name = (global.conflict_popup_asset_a != "")
                            ? global.conflict_popup_asset_a
                            : global.conflict_popup_asset_b;
            // Truncate very long asset names so the notice fits
            if (string_length(_asset_name) > 28) {
                _asset_name = string_copy(_asset_name, 1, 25) + "...";
            }
            draw_text((_btn_x1 + _btn_x2) / 2, _note_y + 18, "CHECK ASSET: " + _asset_name);
        }

        draw_set_halign(fa_left);
        draw_set_valign(fa_top);

        // Click handling
        if (mouse_check_button_pressed(mb_left)) {
            if (_hov_ig) {
                // Resolve each side to its family root before storing — if the
                // popup's owner is an ORG child, we store the ORG's UID instead,
                // so suppression applies to every child of that ORG without
                // needing to click Ignore once per child.
                var _root_a = global.conflict_popup_owner_a;
                var _root_b = global.conflict_popup_owner_b;
                if (instance_exists(_root_a) && _root_a.org_parent != noone && instance_exists(_root_a.org_parent)) {
                    _root_a = _root_a.org_parent;
                }
                if (instance_exists(_root_b) && _root_b.org_parent != noone && instance_exists(_root_b.org_parent)) {
                    _root_b = _root_b.org_parent;
                }
                var _uid_a = scr_get_node_uid(_root_a);
                var _uid_b = scr_get_node_uid(_root_b);
                array_push(global.ignored_conflicts, {
                    range_start: global.conflict_popup_range_start,
                    range_end:   global.conflict_popup_range_end,
                    owner_a_uid: _uid_a,
                    owner_b_uid: _uid_b
                });
                global.memory_bar_dirty = true;
                global.autosave_dirty   = true;
                global.conflict_popup_open = false;
                scr_c64_do_update_addresses();
            } else if (_hov_l && _can_go_left) {
                scr_focus_camera_on_node(global.conflict_popup_owner_a);
                global.conflict_popup_open = false;
            } else if (_hov_r && _can_go_right) {
                scr_focus_camera_on_node(global.conflict_popup_owner_b);
                global.conflict_popup_open = false;
            } else if (!point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
                                           _ppx1, _ppy1, _ppx2, _ppy2)) {
                global.conflict_popup_open = false;
            }
        }
    }
}
