function scr_node_step_macro_bmp(_draw_x) {
    var _header_h   = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;
	
	// Auto-sync bmp_addr from linked asset
	if (instance_exists(obj_asset_manager) && string(instructions[0][1]) != "") {
	    var _am = obj_asset_manager;
	    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	        var _a = ds_list_find_value(_am.asset_list, _ai);
	        if (_a.type == "BITMAP" && _a.name == string(instructions[0][1])) {
	            instructions[0][2] = _a.address;
	            break;
	        }
	    }
	}

    // BMP picker open — handle selection first
    if (instance_exists(obj_asset_manager) && obj_asset_manager.bmp_picker_open &&
        obj_asset_manager.bmp_picker_node == id) {
        var _pdx = _draw_x + width + 8;
        var _pdy = y + 24;
        var _pw  = 180;
        var _ih  = 20;
        var _matches = [];
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "BITMAP") array_push(_matches, _a);
        }
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _pdy + 2 + (_i * _ih);
            if (point_in_rectangle(mouse_x, mouse_y, _pdx, _iy, _pdx + _pw, _iy + _ih)) {
                instructions[0][1]                = _matches[_i].name;
                obj_asset_manager.bmp_picker_open = false;
                obj_asset_manager.bmp_picker_node = noone;
                exit;
            }
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        if (!point_in_rectangle(mouse_x, mouse_y, _pdx, _pdy, _pdx + _pw, _pdy + _total_h)) {
            obj_asset_manager.bmp_picker_open = false;
            obj_asset_manager.bmp_picker_node = noone;
        }
        exit;
    }

    // Asset name field — open picker
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _fy, _draw_x + width - 8, _fy + 16)) {
        if (instance_exists(obj_asset_manager)) {
            var _node_id = id;
            with (obj_asset_manager) {
                bmp_picker_open = true;
                bmp_picker_node = _node_id;
            }
        }
        exit;
    }
    _fy += _line_h; // row 1: asset name
    _fy += _line_h; // row 2: bitmap addr (read only)
    // row 3: screen addr REMOVED
    //_fy += _line_h; // row 3: colour (read only)
    _fy += _line_h; // row 4: vic bank (read only)

    // Row 5b: Force VIC bank checkbox
    var _cb_x = _draw_x + 10;
    var _cb_y = _fy + 1;
    if (point_in_rectangle(mouse_x, mouse_y, _cb_x, _cb_y, _cb_x + 12, _cb_y + 13)) {
        var _cur = (array_length(instructions[0]) > 3) ? real(instructions[0][3]) : 0;
        instructions[0][3] = (_cur == 0) ? 1 : 0;
        exit;
    }
    _fy += _line_h; // row 5: data status
    // Row 6: Pre-clear toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 10, _fy, _draw_x + width - 8, _fy + 13)) {
        var _pc_cur = 0;
        if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) {
            _pc_cur = real(instructions[0][4]);
        }
        if (_pc_cur == 0) {
            instructions[0][4] = 1;
        } else {
            instructions[0][4] = 0;
        }
        exit;
    }
}