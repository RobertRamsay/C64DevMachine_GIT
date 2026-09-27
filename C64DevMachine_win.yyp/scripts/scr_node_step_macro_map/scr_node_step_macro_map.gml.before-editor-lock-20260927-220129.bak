/// @desc Step MACRO_MAP node — handles picker button click
/// @param {Id.Instance} _node
function scr_node_step_macro_map(_node) {

    var _asset_name = (array_length(_node.instructions[0]) > 1)
                    ? string(_node.instructions[0][1]) : "";

    var draw_x = (_node.x - obj_workspace_manager.cam_x) / obj_workspace_manager.cam_zoom;
    var draw_y = (_node.y - obj_workspace_manager.cam_y) / obj_workspace_manager.cam_zoom;

    var _pb_x1 = draw_x + 44;
    var _pb_x2 = draw_x + _node.width - 8;
    var _pb_y1 = draw_y + 28 + 8 - 2;
    var _pb_y2 = _pb_y1 + 14;

if (mouse_check_button_pressed(mb_left) &&
	    point_in_rectangle(
	        mouse_x, mouse_y,
	        _node.x + 44, _node.y + 28 + 8 - 2,
	        _node.x + _node.width - 8, _node.y + 28 + 8 + 14 - 2)) {
	    with (obj_asset_manager) {
	        map_picker_open  = true;
	        map_picker_node  = _node;
	        map_picker_hover = -1;
	    }
	}
// HR / MIXED mode is read-only on the node — change it via the map editor

// ZP SOURCE POINTER FIELD — click to open hex input
if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
    var _zp_ly = _node.y + 28 + 8 + 20 + 18 + 18 + 18 + 22;
    var _zp_x1 = _node.x + _node.width - 52;
    var _zp_x2 = _node.x + _node.width - 8;
    var _zp_y1 = _zp_ly - 2;
    var _zp_y2 = _zp_ly + 14;
    if (point_in_rectangle(mouse_x, mouse_y, _zp_x1, _zp_y1, _zp_x2, _zp_y2)) {
        var _zp_cur = (array_length(_node.instructions[0]) > 6) ? real(_node.instructions[0][6]) : 0x50;
        var _zp_hex = decimal_to_hex(_zp_cur);
        if (string_length(_zp_hex) < 2) { _zp_hex = "0" + _zp_hex; }
        obj_workspace_manager.input_target_node    = _node;
        obj_workspace_manager.input_target_index   = 6;
        obj_workspace_manager.current_input_string = string_upper(_zp_hex);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
    }
}

   // Colour row start spinner
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        var _col_row_st = (array_length(_node.instructions[0]) > 5) ? real(_node.instructions[0][5]) : 0;
        
        // Calculate Y offset based on the drawing logic (110 pixels down)
        var _ly = _node.y + 110; 
        
        // Match drawing offsets exactly
        var _sp_x1  = _node.x + _node.width - 52;
        var _sp_mid = _node.x + _node.width - 32;
        var _sp_x2  = _node.x + _node.width - 8;
        var _sp_y1  = _ly - 2;
        var _sp_y2  = _ly + 14;

        // Click detection (Left side: - )
        if (point_in_rectangle(mouse_x, mouse_y, _sp_x1, _sp_y1, _sp_mid - 1, _sp_y2)) {
            _node.instructions[0][5] = max(0, _col_row_st - 1);
        }
        // Click detection (Right side: + )
        if (point_in_rectangle(mouse_x, mouse_y, _sp_mid, _sp_y1, _sp_x2, _sp_y2)) {
            _node.instructions[0][5] = min(24, _col_row_st + 1);
        }
    }
}
