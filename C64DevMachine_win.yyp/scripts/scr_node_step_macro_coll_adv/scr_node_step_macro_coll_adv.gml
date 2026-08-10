function scr_node_step_macro_coll_adv(_draw_x) {

    // Backfill — 26 slots total
    // [5..12]=T1..T8  [18..25]=T9..T16
    while (array_length(instructions[0]) < 26) {
        var _len = array_length(instructions[0]);
        if (_len == 1)                    { array_push(instructions[0], 0);  }
        else if (_len == 2)               { array_push(instructions[0], 0);  }
        else if (_len == 3)               { array_push(instructions[0], 0);  }
        else                              { array_push(instructions[0], ""); }
    }

    var _h        = 16;
    var _step_amt = 1;
    if (keyboard_check(vk_shift)) { _step_amt = 8; }

    var _dx_vnm     = is_string(instructions[0][16]) ? string(instructions[0][16]) : "";
    var _dy_vnm     = is_string(instructions[0][17]) ? string(instructions[0][17]) : "";
    var _dx_has_var = (_dx_vnm != "" && _dx_vnm != "[clear]");
    var _dy_has_var = (_dy_vnm != "" && _dy_vnm != "[clear]");
    var _any_var    = (_dx_has_var || _dy_has_var);

    // Matching draw coords exactly
    var _dxm1    = _draw_x + 20;
    var _dxp1    = _draw_x + 62;
    var _dym1    = _draw_x + 20;
    var _dyp1    = _draw_x + 62;
    var _pick_x  = _draw_x + 70;
    var _pick_x2 = _draw_x + 140;
    var _vis_x   = _draw_x + width - 56;
    var _vis_y   = y + 70;
    var _vis_w   = 48;
    var _vis_h   = 42;

    // ---- PROBE SPRITE selector ----
    var _sbtn_w     = 22;
    var _sbtn_h     = 18;
    var _sbtn_gap   = 2;
    var _sbtn_sx    = _draw_x + 6;
    var _sbtn_yoffs = 44;
    for (var _si = 0; _si < 8; _si++) {
        var _bx = _sbtn_sx + _si * (_sbtn_w + _sbtn_gap);
        if (point_in_rectangle(mouse_x, mouse_y, _bx, y + _sbtn_yoffs, _bx + _sbtn_w, y + _sbtn_yoffs + _sbtn_h)) {
            instructions[0][1] = _si;
            global.addresses_dirty = true;
            exit;
        }
    }

    // ---- DX row (y+78) ----
    if (!_dx_has_var) {
        if (point_in_rectangle(mouse_x, mouse_y, _dxm1, y + 78, _dxm1 + 18, y + 78 + _h)) {
            var _v = real(instructions[0][2]) - _step_amt;
            if (_v < -64) { _v = -64; }
            instructions[0][2] = _v;
            global.addresses_dirty = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _dxp1, y + 78, _dxp1 + 18, y + 78 + _h)) {
            var _v = real(instructions[0][2]) + _step_amt;
            if (_v > 64) { _v = 64; }
            instructions[0][2] = _v;
            global.addresses_dirty = true;
            exit;
        }
    }

    // DX pick box
    if (point_in_rectangle(mouse_x, mouse_y, _pick_x, y + 78, _pick_x2, y + 78 + _h)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = ["[clear]"];
        label_picker_target     = id;
        label_picker_index      = 16;
        for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
            if (global.named_loc_meta[_ki].type == "UV") {
                array_push(label_picker_list, global.named_loc_meta[_ki].name);
            }
        }
        exit;
    }

    // ---- DY row (y+96) ----
    if (!_dy_has_var) {
        if (point_in_rectangle(mouse_x, mouse_y, _dym1, y + 96, _dym1 + 18, y + 96 + _h)) {
            var _v = real(instructions[0][3]) - _step_amt;
            if (_v < -64) { _v = -64; }
            instructions[0][3] = _v;
            global.addresses_dirty = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _dyp1, y + 96, _dyp1 + 18, y + 96 + _h)) {
            var _v = real(instructions[0][3]) + _step_amt;
            if (_v > 64) { _v = 64; }
            instructions[0][3] = _v;
            global.addresses_dirty = true;
            exit;
        }
    }

    // DY pick box
    if (point_in_rectangle(mouse_x, mouse_y, _pick_x, y + 96, _pick_x2, y + 96 + _h)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = ["[clear]"];
        label_picker_target     = id;
        label_picker_index      = 17;
        for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
            if (global.named_loc_meta[_ki].type == "UV") {
                array_push(label_picker_list, global.named_loc_meta[_ki].name);
            }
        }
        exit;
    }

    // ---- Visualiser click-drag — blocked when any var is active ----
    if (!_any_var) {
        var _vis_pad = 2;
        var _vis_in_padded = point_in_rectangle(
            mouse_x, mouse_y,
            _vis_x - _vis_pad,          _vis_y - _vis_pad,
            _vis_x + _vis_w + _vis_pad, _vis_y + _vis_h + _vis_pad
        );
        if (_vis_in_padded && mouse_check_button(mb_left)) {
            var _cx     = _vis_x + _vis_w * 0.5;
            var _cy     = _vis_y + _vis_h * 0.5;
            var _new_dx = round((mouse_x - _cx) / 2);
            var _new_dy = round((mouse_y - _cy) / 2);
            if (_new_dx < -64) { _new_dx = -64; }
            if (_new_dx >  64) { _new_dx =  64; }
            if (_new_dy < -64) { _new_dy = -64; }
            if (_new_dy >  64) { _new_dy =  64; }
            var _changed = (real(instructions[0][2]) != _new_dx) || (real(instructions[0][3]) != _new_dy);
            if (_changed) {
                instructions[0][2] = _new_dx;
                instructions[0][3] = _new_dy;
                global.addresses_dirty = true;
            }
        }
    }

    // ---- When a var is picked, reset literal values to 0 ----
    if (_dx_has_var && real(instructions[0][2]) != 0) {
        instructions[0][2] = 0;
        global.addresses_dirty = true;
    }
    if (_dy_has_var && real(instructions[0][3]) != 0) {
        instructions[0][3] = 0;
        global.addresses_dirty = true;
    }

    // ---- DIRECT toggle (JSR DISPATCH row, right-aligned) ----
    while (array_length(instructions[0]) < 27) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][26])) { instructions[0][26] = 0; }
    var _dir_bx1 = _draw_x + width - 62;
    var _dir_bx2 = _draw_x + width - 6;
    if (point_in_rectangle(mouse_x, mouse_y, _dir_bx1, y + 134, _dir_bx2, y + 150)) {
        instructions[0][26] = (real(instructions[0][26]) == 1) ? 0 : 1;
        global.addresses_dirty = true;
        exit;
    }

    // ---- MAP picker ----
    var _mx1   = _draw_x + 40;
    var _mpbx2 = _draw_x + width - 4;
    if (point_in_rectangle(mouse_x, mouse_y, _mx1, y + 116, _mpbx2, y + 132)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_index      = 4;
        label_picker_scroll     = 0;
        label_picker_list       = ["[clear]"];
        label_picker_mode       = "JUMP";
        label_picker_target     = id;
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = ds_list_find_value(_am.asset_list, _ai);
                if (_a.type == "MAP_DATA" || _a.type == "META_TILESET" || _a.type == "META_MAP") {
                    array_push(label_picker_list, _a.name);
                }
            }
        }
        exit;
    }

    // ---- 16 TYPE SLOT pickers ----
    var _slot_h       = 20;
    var _slot_row_y0  = y + 155;
    var _half_w       = (width - 12) * 0.5;
    var _swatch_w     = 14;
    var _label_w      = 20;
    var _picker_btn_w = 0;

    var _slot_arr_idx = function(_slot_idx) {
        if (_slot_idx < 8) { return 5 + _slot_idx; }
        return 18 + (_slot_idx - 8);
    };

    for (var _ri = 0; _ri < 8; _ri++) {
        for (var _ci = 0; _ci < 2; _ci++) {
            var _slot_idx = _ri * 2 + _ci;
            var _arr_idx  = _slot_arr_idx(_slot_idx);
            var _slot_x   = _draw_x + 6 + _ci * _half_w;
            var _slot_y   = _slot_row_y0 + _ri * _slot_h;
            var _f_x1     = _slot_x + _swatch_w + _label_w;
            var _f_x2     = _slot_x + _half_w - 6 - _picker_btn_w - 2;

            if (point_in_rectangle(mouse_x, mouse_y, _f_x1, _slot_y, _f_x2, _slot_y + 16)) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_index      = _arr_idx;
                label_picker_scroll     = 0;
                label_picker_list       = ["[clear]"];
                label_picker_mode       = "JUMP";
                label_picker_target     = id;
                with (obj_c64_node) {
                    if (node_type == "LABEL") {
                        array_push(other.label_picker_list, string_replace_all(string(instructions[0][1]), " ", "_"));
                    }
                    if (node_type == "MACRO_ANIM") {
                        if (anim_alias == "") {
                            anim_alias = "anim" + string(real(id));
                        }
                        array_push(other.label_picker_list, anim_alias + "_sub");
                        array_push(other.label_picker_list, anim_alias + "_reset");
                    }
                    if (node_type == "MACRO_SCROLL") {
                    array_push(other.label_picker_list, "Scroller_L");
                    array_push(other.label_picker_list, "Scroller_R");
                    var _sc_src = (array_length(instructions[0]) > 6  && is_real(instructions[0][6]))  ? real(instructions[0][6])  : 0;
                    var _sc_vm  = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                    if (_sc_src == 1 && _sc_vm == 1) {
                        array_push(other.label_picker_list, "Scroller_MapSet");
                    }
	                }
	                if (node_type == "MACRO_SID_SONG") {
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_play");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_init");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_seek");
                }
                    if (node_type == "MACRO_VSCROLL") {
                        array_push(other.label_picker_list, "Scroller_U");
                        array_push(other.label_picker_list, "Scroller_D");
                    }
                }
                exit;
            }
        }
    }

    // ---- OUTPUT VAR pickers ----
    var _out_y0    = _slot_row_y0 + 8 * _slot_h + 6;
    var _out_lbl_w = 44;
    var _out_x1    = _draw_x + 6 + _out_lbl_w;
    var _out_x2    = _draw_x + width - 8;
    var _out_h     = 16;
    var _out_y1    = _out_y0 + _out_h + 3;
    var _out_y2    = _out_y1 + _out_h + 3;

    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y0, _out_x2, _out_y0 + _out_h)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_index      = 13;
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_target     = id;
        exit;
    }

    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y1, _out_x2, _out_y1 + _out_h)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_index      = 14;
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_target     = id;
        exit;
    }

    if (point_in_rectangle(mouse_x, mouse_y, _out_x1, _out_y2, _out_x2, _out_y2 + _out_h)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_index      = 15;
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_target     = id;
        exit;
    }

    exit;
}