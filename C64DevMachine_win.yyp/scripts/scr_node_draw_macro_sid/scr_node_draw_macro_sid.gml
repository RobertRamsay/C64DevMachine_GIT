function scr_node_draw_macro_sid(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
    var _header_h   = 24;
    var _line_h     = 12;
    var _asset_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _track      = (array_length(instructions[0]) > 2) ? real(instructions[0][2]) : 0;
    var _volume     = (array_length(instructions[0]) > 3) ? real(instructions[0][3]) : 12;

    // Resolve asset
    var _asset    = undefined;
    var _has_data = false;
    var _sid_addr = 0x1000;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SID_MUSIC" && _a.name == _asset_name) {
                _asset    = _a;
                _sid_addr = _a.address;
                _has_data = buffer_exists(_a.buffer) && _a.file != "";
                break;
            }
        }
    }
    var _has_asset = (_asset != undefined);

    draw_set_font(fnt_c64_tiny);
    var _ly = _y + _header_h + 4;
	
	var _c_edit = make_color_rgb(120, 220, 120); // Light Green for editable labels
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)   // Dimmed for non-editable labels


    // Row 1: Asset picker
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _ly, "ASSET:");
    draw_set_color(_has_asset ? make_color_rgb(20, 40, 60) : make_color_rgb(60, 20, 60));
    draw_rectangle(_draw_x + 68, _ly +2, _draw_x + width - 8, _ly + 15, false);
    draw_set_color(_has_asset ? c_aqua : (_name_hover ? c_white : make_color_rgb(180, 80, 180)));
    draw_text(_draw_x + 72, _ly, _asset_name == "" ? "CLICK TO SET" : _asset_name );
    _ly += _line_h;

    // Row 2: SID address
    var _sh = string_upper(decimal_to_hex(_sid_addr));
    while (string_length(_sh) < 4) _sh = "0" + _sh;
    draw_set_color(_c_dim);   draw_text(_draw_x + 10, _ly, "SID ADDR:");
    draw_set_color(c_aqua);   draw_text(_draw_x + 90, _ly, "$" + _sh);
    _ly += _line_h;

    // Row 3: Track
    draw_set_color(_c_edit);   draw_text(_draw_x + 10, _ly, "TRACK:");
    draw_set_color(c_yellow); draw_text(_draw_x + 70, _ly, string(_track));
    _ly += _line_h;

    // Row 4: Volume
	var _irq_line_val = (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) ? real(instructions[0][4]) : 0x60;
    var _irq_hex = string_upper(decimal_to_hex(_irq_line_val));
    while (string_length(_irq_hex) < 2) _irq_hex = "0" + _irq_hex;
    draw_set_color(_c_edit);   draw_text(_draw_x + 10, _ly, "IRQ LINE:");
    draw_set_color(c_yellow); draw_text(_draw_x + 90, _ly, "$" + _irq_hex);
    _ly += _line_h;

    // Row 5: Status
global.sid_active = true; // Always true now due to NULLSID fallback
    draw_set_color(_c_dim); draw_text(_draw_x + 10, _ly, "DATA:");
    if (_has_data) {
        draw_set_color(make_color_rgb(80, 200, 80));
        draw_text(_draw_x + 60, _ly, filename_name(_asset.file));
    } else {
        draw_set_color(c_orange);
        draw_text(_draw_x + 60, _ly, "USING FALLBACK");
    }
	_ly += _line_h + 4;

    // Row 6: Warning if connected but not at the top of the spine
    var _is_invalid_pos = false;
    if (is_connected) {
        if (org_parent != noone) {
            _is_invalid_pos = true; // Inside an ORG block (not main spine)
        } else {
			with (obj_c64_node) {
                // If ANY connected node on the spine above us isn't INIT, LABEL, or COMMENT, we are out of place
				if (is_connected && org_parent == noone && id != other.id && y < other.y && node_type != "INIT" && node_type != "LABEL" && node_type != "COMMENT" && node_title != "KERNAL RAM UNLOCK" && node_title != "BASIC ROM UNLOCK") {
                    _is_invalid_pos = true;
                }
            }
        }
    }

	if (is_connected) {
        draw_set_halign(fa_center);
        if (_is_invalid_pos) {
            
			draw_set_alpha(0.8);
			draw_rectangle_colour(_draw_x,_y+20,_draw_x+width,_y+height,c_red,c_black,c_red,c_black,0)
			draw_set_alpha(1.0);
			var _flash_col = (current_time mod 600 < 300) ? c_white : c_black;
            draw_set_color(_flash_col);
            draw_text(_draw_x + (width / 2), _ly-30, "NEEDS TO BE AFTER INIT!");
            _ly += _line_h;
            draw_text(_draw_x + (width / 2), _ly-30, "WITH SID EXIT BELOW IT");
            _ly += _line_h;
			
        } else {
			draw_set_font(fnt_c64_nano);
            draw_set_color(make_color_rgb(80, 200, 80));
            draw_text(_draw_x + (width / 2), _ly-3, "NODE IN PLACE");
            _ly += _line_h;
        }
        draw_set_halign(fa_left);
    }

   // var _raw_h = _ly - _y + 6;
   // height = ceil(_raw_h / 20) * 20;


}

