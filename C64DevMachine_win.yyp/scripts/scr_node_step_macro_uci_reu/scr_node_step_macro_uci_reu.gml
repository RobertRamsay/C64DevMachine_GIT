/// @desc Handle LMB clicks for MACRO_UCI_REU.
function scr_node_step_macro_uci_reu(_draw_x) {
    var _hh = 24, _lh = 16, _inst = instructions[0];
    while (array_length(_inst) < 4) {
        array_push(_inst, "");
    }

    var _lx = _draw_x + 8, _rx = _draw_x + width - 6, _cy = y + _hh + 4;

    var _hit = function(_x1, _x2, _yy) {
        return point_in_rectangle(mouse_x, mouse_y, _x1, _yy + 4, _x2, _yy + 10);
    };

    // ---- REU manifest: cycle through the LOAD_REU assets ----
    if (_hit(_lx + 48, _rx, _cy)) {
        var _matches = [];
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
                var _a = ds_list_find_value(_am.asset_list, _i);
                if (_a.type == "LOAD_REU") array_push(_matches, _a.name);
            }
        }
        if (array_length(_matches) > 0) {
            var _at = -1;
            for (var _i = 0; _i < array_length(_matches); _i++) {
                if (_matches[_i] == string(_inst[1])) { _at = _i; break; }
            }
            _at = (_at + 1) mod array_length(_matches);
            instructions[0][1] = _matches[_at];
            // Switching manifest drops a stale override, so the filename goes
            // back to following whichever asset is now selected.
            instructions[0][2] = "";
        }
        exit;
    }
    _cy += _lh;

    // ---- filename override: type one, or clear it to follow the manifest ----
    if (_hit(_lx + 48, _rx, _cy)) {
        var _seed = string(_inst[2]);
        if (_seed == "") {
            var _manifest = scr_reu_find_asset(string(_inst[1]));
            if (!is_undefined(_manifest) && variable_struct_exists(_manifest, "reu_filename")) {
                _seed = string(_manifest.reu_filename);
            }
        }
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            current_input_string = _seed;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _cy += _lh;

    // ---- status var picker ----
    if (_hit(_lx + 48, _rx, _cy)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_word_only  = false;
        label_picker_byte_only  = true;
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 3;
        exit;
    }
}
