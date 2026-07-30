/// @function scr_node_step_macro_vector_page(_draw_x)
function scr_node_step_macro_vector_page(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;

    // Picker open — handle selection (shares the setup node's picker state)
    if (instance_exists(obj_asset_manager) && obj_asset_manager.vbmp_picker_open &&
        obj_asset_manager.vbmp_picker_node == id) {
        var _pdx = _draw_x + width + 8;
        var _pdy = y + 24;
        var _pw  = 180;
        var _ih  = 20;
        var _matches = [];
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "VECTOR_BITMAP") array_push(_matches, _a);
        }
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _pdy + 2 + (_i * _ih);
            if (point_in_rectangle(mouse_x, mouse_y, _pdx, _iy, _pdx + _pw, _iy + _ih)) {
                instructions[0][1]                 = _matches[_i].name;
                // Reset the literal page to 0 on asset change; leave the
                // use_var flag (slot 2) untouched so VAR mode survives re-pick.
                if (!is_real(instructions[0][2])) instructions[0][2] = 0;
                if (real(instructions[0][2]) == 0) instructions[0][3] = 0;
                obj_asset_manager.vbmp_picker_open = false;
                obj_asset_manager.vbmp_picker_node = noone;
                exit;
            }
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        if (!point_in_rectangle(mouse_x, mouse_y, _pdx, _pdy, _pdx + _pw, _pdy + _total_h)) {
            obj_asset_manager.vbmp_picker_open = false;
            obj_asset_manager.vbmp_picker_node = noone;
        }
        exit;
    }

    // Row 1: asset name — open picker
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 16)) {
        if (instance_exists(obj_asset_manager)) {
            var _node_id = id;
            with (obj_asset_manager) {
                vbmp_picker_open = true;
                vbmp_picker_node = _node_id;
            }
        }
        exit;
    }
    _fy += _line_h; // row 1 asset
    // ---- normalise instruction layout to house convention ----
    // ["macro_vector_page", asset, use_var_flag, page_or_varname]
    // (draw normalises too; repeated here so step is safe if it fires first)
    while (array_length(instructions[0]) < 4) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][2])) instructions[0][2] = 0;
    var _use_var = real(instructions[0][2]);
    // Row 2 geometry — must match scr_node_draw_macro_vector_page
    var _tog_w = 30;
    var _tog_x = _draw_x + width - _tog_w - 8;
    // ---- VAR toggle click ----
    if (point_in_rectangle(mouse_x, mouse_y, _tog_x, _fy, _tog_x + _tog_w, _fy + 15)) {
        scr_undo_snapshot();
        if (_use_var == 0) {
            instructions[0][2] = 1;
            instructions[0][3] = ""; // clear literal page, await var pick
        } else {
            instructions[0][2] = 0;
            instructions[0][3] = 0; // back to literal page 0
        }
        global.addresses_dirty = true;
        exit;
    }
    // Row 2: value area
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 60, _fy, _tog_x - 4, _fy + 12)) {
        if (_use_var == 1) {
            // Open the SHARED UV var picker for slot 3
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = ["[clear]"];
            label_picker_target     = id;
            label_picker_index      = 3;
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                if (global.named_loc_meta[_ki].type == "UV") {
                    array_push(label_picker_list, global.named_loc_meta[_ki].name);
                }
            }
            exit;
        } else {
            // Literal: left-click cycles page forward, wrapping on page count
            var _cur = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
            var _count = 1;
            var _asset_name = string(instructions[0][1]);
            if (instance_exists(obj_asset_manager) && _asset_name != "") {
                var _am2 = obj_asset_manager;
                for (var _i = 0; _i < ds_list_size(_am2.asset_list); _i++) {
                    var _a = ds_list_find_value(_am2.asset_list, _i);
                    if (_a.type == "VECTOR_BITMAP" && _a.name == _asset_name) {
                        if (variable_struct_exists(_a.meta, "pages") && is_array(_a.meta.pages)) {
                            _count = max(1, array_length(_a.meta.pages));
                        }
                        break;
                    }
                }
            }
            instructions[0][3] = (_cur + 1) mod _count;
            exit;
        }
    }
}