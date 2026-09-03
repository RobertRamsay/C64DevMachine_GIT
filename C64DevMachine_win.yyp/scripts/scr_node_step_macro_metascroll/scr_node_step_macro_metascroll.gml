/// @desc Step MACRO_METASCROLL node - tileset picker, map spinner, addresses
function scr_node_step_macro_metascroll(_draw_x) {

    if (!mouse_check_button_pressed(mb_left)) return;
    if (global.ui_click_consumed) return;
    if (global.any_picker_open) return;

    var header_h = 28;
    var pad      = 8;
    var line_h   = 18;

    var _ly0 = y + header_h + pad;

    // ROW 0 - TILESET PICKER
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 64, _ly0 - 2, _draw_x + width - 8, _ly0 + 14)) {
        with (obj_asset_manager) {
            metamap_picker_open       = true;
            metamap_picker_node       = other.id;
            metamap_picker_hover      = -1;
            metamap_picker_name_idx   = 1;
            metamap_picker_mapidx_idx = 2;
        }
        exit;
    }

    // ROW 1 - MAP INDEX spinner ( - on the left half, + on the right )
    var _mi_ly = _ly0 + line_h;
    var _mi_x1 = _draw_x + width - 80;
    var _mi_md = _draw_x + width - 44;
    var _mi_x2 = _draw_x + width - 8;

    // Resolve map_count so the spinner can clamp
    var _map_count = 0;
    var _tn = "";
    if (array_length(instructions[0]) > 1) _tn = string(instructions[0][1]);
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
    var _cur     = 0;
    if (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) _cur = real(instructions[0][2]);

    if (point_in_rectangle(mouse_x, mouse_y, _mi_x1, _mi_ly - 2, _mi_md - 1, _mi_ly + 14)) {
        instructions[0][2]     = max(0, _cur - 1);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _mi_md, _mi_ly - 2, _mi_x2, _mi_ly + 14)) {
        instructions[0][2]     = min(_max_idx, _cur + 1);
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }

    // ROW 2 - PLANE BASE ADDRESS (hex input)
    var _ba_ly = _ly0 + line_h * 2;
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 64, _ba_ly - 2, _draw_x + 200, _ba_ly + 14)) {
        var _ba_cur = 0x4000;
        if (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) _ba_cur = real(instructions[0][3]);
        var _ba_hex = string_upper(decimal_to_hex(_ba_cur));
        while (string_length(_ba_hex) < 4) _ba_hex = "0" + _ba_hex;
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 3;
        obj_workspace_manager.current_input_string = _ba_hex;
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ROW 4 - ZP BASE (hex input)
    var _zp_ly = _ly0 + line_h * 4;
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 140, _zp_ly - 2, _draw_x + 200, _zp_ly + 14)) {
        var _zp_cur = 0x60;
        if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) _zp_cur = real(instructions[0][4]);
        var _zp_hex = string_upper(decimal_to_hex(_zp_cur));
        while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 4;
        obj_workspace_manager.current_input_string = _zp_hex;
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        exit;
    }

    // ROW 5 - COLOUR MODE toggle (left half) / fixed nibble cycle (right half)
    var _cm_ly = _ly0 + line_h * 5;
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 140, _cm_ly - 2, _draw_x + 196, _cm_ly + 14)) {
        var _cm_cur = 0;
        if (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) _cm_cur = real(instructions[0][6]);
        if (_cm_cur == 1) {
            instructions[0][6] = 0;
        } else {
            instructions[0][6] = 1;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 200, _cm_ly - 2, _draw_x + width - 8, _cm_ly + 14)) {
        var _cm_now = 0;
        if (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) _cm_now = real(instructions[0][6]);
        if (_cm_now == 0) {
            // cycle -1 (auto) then 0..15
            var _fc_cur = -1;
            if (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) _fc_cur = real(instructions[0][7]);
            _fc_cur = _fc_cur + 1;
            if (_fc_cur > 15) {
                _fc_cur = -1;
            }
            instructions[0][7] = _fc_cur;
            global.undo_dirty  = true;
        }
        exit;
    }

    // ROW 6 - CLAMP toggle
    var _cl_ly = _ly0 + line_h * 6;
    if (point_in_rectangle(mouse_x, mouse_y,
            _draw_x + 140, _cl_ly - 2, _draw_x + 200, _cl_ly + 14)) {
        var _cl_cur = 1;
        if (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) _cl_cur = real(instructions[0][5]);
        if (_cl_cur == 1) {
            instructions[0][5] = 0;
        } else {
            instructions[0][5] = 1;
        }
        global.undo_dirty = true;
        exit;
    }
}
