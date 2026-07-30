/// @desc scr_node_step_bitmap_kla(_draw_x)
/// Handles LMB input for BITMAP_KLA nodes.

function scr_node_step_bitmap_kla(_draw_x) {

    var _thumb_h = 80;
    var _ly = y + 24 + 4 + 18 + 18 + 18 + 18 + 4 + _thumb_h + 6;

    var _btn_x1 = _draw_x + 10;
    var _btn_x2 = _draw_x + 170;
    var _btn_y1 = _ly;
    var _btn_y2 = _ly + 18;
	
	// Address field click — hex input
	var _addr_y = y + 24 + 4 + 18; // row 1 = address row
	if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _addr_y, _draw_x + width - 8, _addr_y + 16)) {
	    var _input = get_string("Bitmap load address (hex):", string_upper(decimal_to_hex(pc_address)));
	    if (_input != "") {
	        var _val = scr_hex_to_int(_input);
	        if (_val >= 0 && _val <= 0xFFFF) {
	            pc_address = _val;
	            instructions[0][2] = _val;
	            // Write back to asset manager
	            if (instance_exists(obj_asset_manager)) {
	                var _am = obj_asset_manager;
	                var _aname = string(instructions[0][1]);
	                for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
	                    var _a = ds_list_find_value(_am.asset_list, _ai);
	                    if (_a.type == "BITMAP" && _a.name == _aname) {
	                        _a.address = _val;
	                        break;
	                    }
	                }
	            }
	        }
	    }
	    exit;
	}

    if (point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2)) {
        var _path = get_open_filename("Koala Painter (*.kla)|*.kla", "");
        if (_path != "") {
            if (variable_instance_exists(id, "kla_buffer") && kla_buffer != -1 && buffer_exists(kla_buffer)) buffer_delete(kla_buffer);
            if (variable_instance_exists(id, "preview_surf") && surface_exists(preview_surf)) surface_free(preview_surf);
            preview_surf = -1;

            kla_buffer   = buffer_load(_path);
            kla_filename = filename_name(_path);
			
			if (!buffer_exists(kla_buffer) || buffer_get_size(kla_buffer) != 10003) {
			    scr_show_message("Invalid KLA file — expected 10003 bytes.");
			    buffer_delete(kla_buffer);
			    kla_buffer = -1;
			}
			
        }
        exit;
    }
}
