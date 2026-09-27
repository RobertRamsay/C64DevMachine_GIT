/// @desc scr_node_step_macro_spr()
/// Handles LMB input for MACRO_SPR nodes.
/// Call from inside the LMB click block in obj_c64_node Step.

function scr_node_step_macro_spr(_draw_x) {

    // Handle picker selection
    if (instance_exists(obj_asset_manager) && obj_asset_manager.spr_picker_open && obj_asset_manager.spr_picker_node == id) {
        var _pdx = _draw_x + width + 8;
        var _pdy = y + 24;
        var _pw  = 180;
        var _ih  = 20;

        var _matches = [];
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "SPRITE_SET") {
                array_push(_matches, _a);
            }
        }

        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _pdy + 2 + (_i * _ih);
            if (point_in_rectangle(mouse_x, mouse_y, _pdx, _iy, _pdx + _pw, _iy + _ih)) {
                instructions[0][1]                = _matches[_i].name;
                obj_asset_manager.spr_picker_open = false;
                obj_asset_manager.spr_picker_node = noone;
                exit;
            }
        }

        // Click outside closes it
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        if (!point_in_rectangle(mouse_x, mouse_y, _pdx, _pdy, _pdx + _pw, _pdy + _total_h)) {
            obj_asset_manager.spr_picker_open = false;
            obj_asset_manager.spr_picker_node = noone;
        }
        exit;
    }

    var _mframe   = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0;

    var _header_h = 24;
    var _line_h   = 14;
    var _cell_h   = 21 * 2 + 4; // 46

    var _fy = y + _header_h + 4;

    // Row 1: Asset name field — open picker
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 14)) {
        if (instance_exists(obj_asset_manager)) {
            with (obj_asset_manager) {
                spr_picker_open = true;
                spr_picker_node = other.id;
                spr_picker_x    = other.x + other.width + 8;
                spr_picker_y    = other.y + 24;
            }
        }
        exit;
    }
    _fy += _line_h; // end of row 1

    // Row 2: Addr / PTR — read only
    _fy += _line_h; // end of row 2

    // Row 3: Slot field — click cycles 0-7
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 55, _fy, _draw_x + 80, _fy + 16)) {
        var _cur_slot = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
        _cur_slot += 1;
        if (_cur_slot > 7) {
            _cur_slot = 0;
        }
        instructions[0][2] = _cur_slot;
        exit;
    }

    // Row 3: X field
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 90, _fy, _draw_x + 120, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 3;
            current_input_string = string(other.instructions[0][3]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // Row 3: Y field
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 150, _fy, _draw_x + 170, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 4;
            current_input_string = string(other.instructions[0][4]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _fy += _line_h; // end of row 3

    // Row 4: Frame nav — draw adds +4 bump before triangles
    _fy += 4;

    var _nav_lx = _draw_x + 70;
    var _nav_rx = _draw_x + 110;
    var _nav_hw = 16;
    var _nav_hh = 10;

    if (point_in_rectangle(mouse_x, mouse_y, _nav_lx, _fy, _nav_lx + _nav_hw, _fy + _nav_hh)) {
        instructions[0][5] = max(0, _mframe - 1);
        exit;
    }

    if (point_in_rectangle(mouse_x, mouse_y, _nav_rx, _fy, _nav_rx + _nav_hw, _fy + _nav_hh)) {
        var _max_frame = 63;
        if (instance_exists(obj_asset_manager)) {
            var _aname = string(instructions[0][1]);
            var _am    = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = ds_list_find_value(_am.asset_list, _ai);
                if (_a.type == "SPRITE_SET" && _a.name == _aname) {
                    if (variable_struct_exists(_a.meta, "used_count")) {
                        _max_frame = _a.meta.used_count - 1;
                    }
                    break;
                }
            }
        }
        instructions[0][5] = min(_max_frame, _mframe + 1);
        exit;
    }
    _fy += _line_h; // end of row 4 (frame nav) — matches draw's advance into the preview row

    // Row 5: sprite preview — double-click opens SPRED64 V2 directly on this
    // node's sprite asset, with the frame currently shown (_mframe) selected.
    var _prev_x = _draw_x + 10;
    var _prev_y = _fy;
    var _prev_w = 24 * 2 + 4;
    var _prev_h = 21 * 2 + 4;

    if (spr_preview_dbl_click_timer > 0) {
        spr_preview_dbl_click_timer -= 1;
    }

    if (point_in_rectangle(mouse_x, mouse_y, _prev_x, _prev_y, _prev_x + _prev_w, _prev_y + _prev_h)
    && mouse_check_button_pressed(mb_left)) {
        if (spr_preview_dbl_click_timer > 0) {
            spr_preview_dbl_click_timer = 0;

            if (instance_exists(obj_asset_manager)) {
                var _open_aname = string(instructions[0][1]);
                var _open_am    = obj_asset_manager;
                var _open_idx   = -1;
                for (var _oai = 0; _oai < ds_list_size(_open_am.asset_list); _oai++) {
                    var _oa = ds_list_find_value(_open_am.asset_list, _oai);
                    if (_oa.type == "SPRITE_SET" && _oa.name == _open_aname) {
                        _open_idx = _oai;
                        break;
                    }
                }
                if (_open_idx >= 0) {
                    with (_open_am) {
                        viewer_open  = true;
                        viewer_asset = _open_idx;
                        scr_spred64_v2_open(_open_idx);

                        var _open_used = spred64_v2.used_count;
                        var _open_slot = _mframe;
                        if (_open_slot > _open_used - 1) {
                            _open_slot = _open_used - 1;
                        }
                        if (_open_slot < 0) {
                            _open_slot = 0;
                        }
                        spred64_v2.selected_slot = _open_slot;
                        if (surface_exists(spred64_v2.edit_surface)) {
                            surface_free(spred64_v2.edit_surface);
                        }
                        spred64_v2.edit_surface = -1;
                    }
                }
            }
        } else {
            spr_preview_dbl_click_timer = dbl_click_threshold;
        }
        exit;
    }
}