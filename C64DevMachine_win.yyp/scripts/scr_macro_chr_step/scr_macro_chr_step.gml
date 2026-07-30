/// @desc Step logic for MACRO_CHR node
function scr_macro_chr_step(_node) {
    with (_node) {

        // --- DETECT MAP CONNECTION ---
        var _map_connected = false;
        with (obj_c64_node) {
            if (node_type == "MACRO_MAP" && is_connected) {
                _map_connected = true;
                break;
            }
        }

        var _header_h   = 24;
        var _line_h   = 12;

        // --- CHARSET PICKER BUTTON CLICK (always available) ---
        var _btn_x = x + 8;
        var _btn_y = y + _header_h + 4;
        var _btn_w = width - 16;
        var _btn_h = _line_h;
        if (mouse_check_button_pressed(mb_left) &&
            point_in_rectangle(mouse_x, mouse_y, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h)) {
            if (instance_exists(obj_asset_manager)) {
                obj_asset_manager.chr_picker_open = true;
                obj_asset_manager.chr_picker_node = id;
            }
        }

        // --- MULTICOLOUR TOGGLE CLICK (blocked if map connected) ---
        if (!_map_connected) {
            var _mc_x = x + 8;
            var _mc_y = _btn_y + _line_h + 10;
            var _mc_w = width - 16;
            var _mc_h = _line_h + 12;
            if (mouse_check_button_pressed(mb_left) &&
                point_in_rectangle(mouse_x, mouse_y, _mc_x, _mc_y, _mc_x + _mc_w, _mc_y + _mc_h)) {
                var _mc_flag = (array_length(instructions) > 0 && array_length(instructions[0]) > 2)
                             ? real(instructions[0][2]) : 0;
                var _new_mc = _mc_flag ? 0 : 1;
                instructions[0][2] = _new_mc;
                // Push the override back to the linked asset so sync (which now reads
                // asset meta) keeps the user's node-side choice instead of reverting it.
                var _chr_name = string(instructions[0][1]);
                if (instance_exists(obj_asset_manager)) {
                    with (obj_asset_manager) {
                        for (var _mi = 0; _mi < ds_list_size(asset_list); _mi++) {
                            var _ma = ds_list_find_value(asset_list, _mi);
                            if (_ma.type == "CHAR_SET" && _ma.name == _chr_name) {
                                _ma.meta.mc_mode = _new_mc;
                                break;
                            }
                        }
                    }
                }
                scr_macro_chr_sync(id);
                global.addresses_dirty = true;
            }
        }
// --- COLOUR SWATCH CLICK TO CYCLE ---
        var _mc_flag = (array_length(instructions) > 0 && array_length(instructions[0]) > 2) ? real(instructions[0][2]) : 0;
        
        if (!_map_connected && array_length(instructions) > 10) {
			var _header_h = 24;

            var _d018_y   = (y + _header_h + 4) + _line_h + 4 + _line_h + 6; 
            var _d021_y   = _d018_y + 20; // Match the +20 from draw
            
            var _col_w = (width - 16) / 4; 
            var _swatch_w = 22; // Match the 22
            var _swatch_h = 16;
            var _swatch_y = _d021_y - 2;
            var _swatch_offset = 22; // Match the 22 offset

            var _x0 = x + 8;
            var _x1 = x + 8 + _col_w;
            var _x2 = x + 8 + (_col_w * 2);
            var _x3 = x + 8 + (_col_w * 3);

if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
                var _spawn_picker = false;
                var _px = 0, _t_row = 0, _t_col = 0;

                // Check BG
                if (point_in_rectangle(mouse_x, mouse_y, _x0 + _swatch_offset, _swatch_y, _x0 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h)) {
                    _spawn_picker = true; _px = _x0 + _swatch_offset; _t_row = 7; _t_col = 1;
                }
                // Check C1 (multicolour only)
                else if (_mc_flag && point_in_rectangle(mouse_x, mouse_y, _x1 + _swatch_offset, _swatch_y, _x1 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h)) {
                    _spawn_picker = true; _px = _x1 + _swatch_offset; _t_row = 9; _t_col = 1;
                }
                // Check C2 (multicolour only)
                else if (_mc_flag && point_in_rectangle(mouse_x, mouse_y, _x2 + _swatch_offset, _swatch_y, _x2 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h)) {
                    _spawn_picker = true; _px = _x2 + _swatch_offset; _t_row = 11; _t_col = 1;
                }
                // Check CH (Char)
                else if (point_in_rectangle(mouse_x, mouse_y, _x3 + _swatch_offset, _swatch_y, _x3 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h)) {
                    if (array_length(instructions[0]) < 4) array_push(instructions[0], 1); 
                    _spawn_picker = true; _px = _x3 + _swatch_offset; _t_row = 0; _t_col = 3;
                }

                // If a swatch was clicked, spawn the universal modal!
                if (_spawn_picker) {
                    instance_destroy(obj_ui_color_picker); // Destroy any already open
                    
                    // Calculate center: Current X + (Half Swatch Width) - (Half Modal Width)
                    var _picker_w = 256; 
                    var _spawn_x = _px + (_swatch_w / 2) - (_picker_w / 2);
                    var _py = _swatch_y + _swatch_h + 4; // Spawn just below the swatch
                    
                    var _picker = instance_create_depth(_spawn_x, _py, -9999, obj_ui_color_picker);
                    _picker.target_node = id;
                    _picker.target_row = _t_row;
                    _picker.target_col = _t_col;
                    
                    // CRITICAL: Clear the mouse state so the picker doesn't immediately 
                    // catch this exact same left-click and instantly destroy itself!
                    mouse_clear(mb_left);
                }
            }
        }
    }
}