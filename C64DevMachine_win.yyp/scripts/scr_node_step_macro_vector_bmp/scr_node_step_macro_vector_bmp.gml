/// @function scr_node_step_macro_vector_bmp(_draw_x)
function scr_node_step_macro_vector_bmp(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;

    // Auto-sync bmp addr display isn't stored on the node; nothing to sync here
    // (the asset's address is the source of truth, read at draw time).

    // Picker open — handle selection
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
    _fy += _line_h; // row 2 bitmap addr (read only)
    _fy += _line_h; // row 3 vic bank (read only)
    _fy += _line_h; // row 4 cmd count (read only)
    // Row 5: BASE hex field — left-click cycles through common bases.
    // Base drives fill stack (base..base+$07FF) and stream (base+$0800).
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 78, _fy, _draw_x + width - 8, _fy + 11)) {
        var _cur_base = (array_length(instructions[0]) > 2 && is_real(instructions[0][2]) && real(instructions[0][2]) != 0)
            ? real(instructions[0][2]) : 0x8000;
        var _next_base = 0x8000;
        if (_cur_base == 0x8000) {
            _next_base = 0xA000;
        } else if (_cur_base == 0xA000) {
            _next_base = 0xC000;
        } else {
            _next_base = 0x8000;
        }
        instructions[0][2] = _next_base;
        exit;
    }
}