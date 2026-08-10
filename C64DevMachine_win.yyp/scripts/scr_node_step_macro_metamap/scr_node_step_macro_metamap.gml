/// @desc Step MACRO_METAMAP node — tileset picker + map index spinner
function scr_node_step_macro_metamap(_node) {
    var header_h = 28;
    var pad      = 8;
    var line_h   = 18;

    // TILESET PICKER click (row 0)
    var _pb_y = _node.y + header_h + pad;
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open &&
        point_in_rectangle(mouse_x, mouse_y,
            _node.x + 64, _pb_y - 2,
            _node.x + _node.width - 8, _pb_y + 14)) {
        with (obj_asset_manager) {
            metamap_picker_open       = true;
            metamap_picker_node       = _node;
            metamap_picker_hover      = -1;
            metamap_picker_name_idx   = 1;
            metamap_picker_mapidx_idx = 2;
        }
        exit;
    }

    // MAP row (row 1) — LIT/VAR toggle, var-name picker, or LIT spinner
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        var _mi_ly = _node.y + header_h + pad + line_h + 2;
        if (array_length(_node.instructions[0]) > 6 && is_string(_node.instructions[0][6])) {
            var _stray_s = _node.instructions[0][6];
            while (array_length(_node.instructions[0]) < 8) array_push(_node.instructions[0], "");
            _node.instructions[0][7] = _stray_s;
            _node.instructions[0][6] = 1;
        }
        var _src_mode = (array_length(_node.instructions[0]) > 6 && is_real(_node.instructions[0][6])) ? real(_node.instructions[0][6]) : 0;

        // LIT/VAR source toggle — match draw: draw_x + 42 .. draw_x + 78
        var _ms_x1 = _node.x + 42;
        var _ms_x2 = _node.x + 78;
        if (point_in_rectangle(mouse_x, mouse_y, _ms_x1, _mi_ly - 2, _ms_x2, _mi_ly + 12)) {
            while (array_length(_node.instructions[0]) < 8) array_push(_node.instructions[0], "");
            if (!is_real(_node.instructions[0][6])) _node.instructions[0][6] = 0;
            _node.instructions[0][6] = (real(_node.instructions[0][6]) == 0) ? 1 : 0;
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }

        if (_src_mode == 1) {
            // VAR MODE — click the name to open the var picker
            // match draw: draw_x + 84 .. draw_x + width - 8
            var _mv_x1 = _node.x + 130;
            var _mv_x2 = _node.x + _node.width - 8;
            if (point_in_rectangle(mouse_x, mouse_y, _mv_x1, _mi_ly - 2, _mv_x2, _mi_ly + 12)) {
                with (_node) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth                   = -9999;
                    label_picker_index      = 0;
                    label_picker_scroll     = 0;
                    label_picker_list       = [];
                    label_picker_mode       = "VAR_SRC";
                    label_picker_target     = id;
                }
                exit;
            }
        } else {
            // LIT MODE — - n/max + spinner
            var _mi_x1  = _node.x + _node.width - 80;
            var _mi_mid = _node.x + _node.width - 44;
            var _mi_x2  = _node.x + _node.width - 8;
            var _mi_y1  = _mi_ly - 2;
            var _mi_y2  = _mi_ly + 14;
            var _cur    = (array_length(_node.instructions[0]) > 2) ? real(_node.instructions[0][2]) : 0;
            // Resolve map_count for clamp
            var _map_count = 0;
            var _tn = (array_length(_node.instructions[0]) > 1) ? string(_node.instructions[0][1]) : "";
            if (_tn != "" && instance_exists(obj_asset_manager)) {
                var _am = obj_asset_manager;
                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                    var _a = ds_list_find_value(_am.asset_list, _ai);
                    if (_a.type == "META_TILESET" && _a.name == _tn) {
                        if (variable_struct_exists(_a.meta, "map_count")) _map_count = _a.meta.map_count;
                        break;
                    }
                }
            }
            var _max_idx = max(0, _map_count - 1);
            if (point_in_rectangle(mouse_x, mouse_y, _mi_x1, _mi_y1, _mi_mid - 1, _mi_y2)) {
                _node.instructions[0][2] = max(0, _cur - 1);
                global.addresses_dirty = true;
            } else if (point_in_rectangle(mouse_x, mouse_y, _mi_mid, _mi_y1, _mi_x2, _mi_y2)) {
                _node.instructions[0][2] = min(_max_idx, _cur + 1);
                global.addresses_dirty = true;
            }
        }
    }

    // ZP SOURCE POINTER click — open hex input
    // draw row order after MAP row: CHAR (line_h), COLOR (line_h),
    // FLATTEN (line_h + 4), then ZP. So from MAP row top:
    //   MAP top = header_h + pad + (line_h + 2)         [tileset row used line_h + 2]
    //   after MAP: + (line_h + 2)
    //   CHAR/COLOR: + line_h * 2
    //   FLATTEN:   + (line_h + 4)
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        var _zp_ly = _node.y + header_h + pad + (line_h + 2) * 2 + line_h * 2 + (line_h + 4);
        var _zp_x1 = _node.x + 140;
        var _zp_x2 = _zp_x1 + 52;
        if (point_in_rectangle(mouse_x, mouse_y, _zp_x1, _zp_ly - 2, _zp_x2, _zp_ly + 14)) {
            var _zp_cur = (array_length(_node.instructions[0]) > 5) ? real(_node.instructions[0][5]) : 0x50;
            var _zp_hex = string_upper(decimal_to_hex(_zp_cur));
            if (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;
            obj_workspace_manager.input_target_node    = _node;
            obj_workspace_manager.input_target_index   = 5;
            obj_workspace_manager.current_input_string = _zp_hex;
            obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
            obj_workspace_manager.is_entering_text     = true;
        }
    }
}