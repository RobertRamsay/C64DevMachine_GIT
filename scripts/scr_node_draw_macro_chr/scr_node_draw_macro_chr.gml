/// @desc Draw MACRO_CHR node body
function scr_node_draw_macro_chr(_x, _y, _cam_x, _cam_y, _cam_zoom) {

    var _header_h   = 24;
    var _line_h     = 18;
    var _asset_name = (array_length(instructions) > 0 && array_length(instructions[0]) > 1)
                    ? string(instructions[0][1]) : "";
    var _mc_flag    = (array_length(instructions) > 0 && array_length(instructions[0]) > 2)
                    ? real(instructions[0][2]) : 0;

    // --- DETECT MAP CONNECTION ---
    var _map_connected = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_MAP" && is_connected) {
            _map_connected = true;
            break;
        }
    }

    // --- CHARSET PICKER BUTTON (always available) ---
    var _btn_x   = _x + 8;
    var _btn_y   = _y + _header_h + 4;
    var _btn_w   = width - 16;
    var _btn_h   = _line_h;
    var _btn_hov = point_in_rectangle(mouse_x, mouse_y, _btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h);

    draw_set_color(_btn_hov ? make_color_rgb(30, 100, 160) : make_color_rgb(15, 50, 80));
    draw_rectangle(_btn_x, _btn_y, _btn_x + _btn_w, _btn_y + _btn_h, false);
    draw_set_color(_asset_name != "" ? make_color_rgb(100, 200, 255) : make_color_rgb(80, 80, 100));
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_text(_btn_x + _btn_w * 0.5, _btn_y + 3,
              _asset_name != "" ? _asset_name : "-- SELECT CHARSET --");
    draw_set_halign(fa_left);

    if (_btn_hov && mouse_check_button_pressed(mb_left)) {
        if (instance_exists(obj_asset_manager)) {
            obj_asset_manager.chr_picker_open = true;
            obj_asset_manager.chr_picker_node = id;
        }
    }

    // --- MULTICOLOUR TOGGLE (locked if map connected) ---
    var _mc_x   = _x + 8;
    var _mc_y   = _btn_y + _line_h + 4;
    var _mc_w   = width - 16;
    var _mc_h   = _line_h;
    var _mc_hov = !_map_connected && point_in_rectangle(mouse_x, mouse_y, _mc_x, _mc_y, _mc_x + _mc_w, _mc_y + _mc_h);

    if (_map_connected) {
        // greyed out — map is master
        draw_set_color(make_color_rgb(25, 25, 35));
        draw_rectangle(_mc_x, _mc_y, _mc_x + _mc_w, _mc_y + _mc_h, false);
        draw_set_color(make_color_rgb(55, 55, 65));
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_mc_x + _mc_w * 0.5, _mc_y + 3, "MAP IS MASTER");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_mc_flag ? make_color_rgb(160, 80, 20) : make_color_rgb(30, 30, 45));
        draw_rectangle(_mc_x, _mc_y, _mc_x + _mc_w, _mc_y + _mc_h, false);
        draw_set_color(_mc_flag ? make_color_rgb(255, 160, 60) : make_color_rgb(80, 80, 100));
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_mc_x + _mc_w * 0.5, _mc_y + 3, _mc_flag ? "MULTICOLOUR  ON" : "MULTICOLOUR OFF");
        draw_set_halign(fa_left);
    }

    // --- $D018 CALCULATED VALUE DISPLAY ---
    var _d018_y = _mc_y + _mc_h + 6;
    draw_set_font(fnt_c64_tiny);
    if (array_length(instructions) > 10) {
        var _d018_val = instructions[5][1];
        var _d016_val = instructions[3][1];
        var _d021_val = instructions[7][1];
        var _d022_val = instructions[9][1];
        var _d023_val = instructions[11][1];

        draw_set_color(make_color_rgb(60, 160, 180));
        draw_text(_x + 8, _d018_y, "$D018:");
        draw_set_color(make_color_rgb(100, 200, 255));
        draw_text(_x + 52, _d018_y, "$" + string_upper(decimal_to_hex(_d018_val)));
        draw_set_color(make_color_rgb(60, 160, 180));
        draw_text(_x + 90, _d018_y, "$D016:");
        draw_set_color(_mc_flag ? make_color_rgb(255, 160, 60) : make_color_rgb(100, 200, 255));
        draw_text(_x + 134, _d018_y, "$" + string_upper(decimal_to_hex(_d016_val)));


// Colour swatches only shown if no map connected
        if (_mc_flag && !_map_connected) {
			var _d021_y = _d018_y + 20; // Moved down 4 pixels
            var _col_w = (width - 16) / 4; 
            var _swatch_w = 22; // Reduced width by 2 pixels
            var _swatch_h = 16; 
            var _swatch_y = _d021_y - 2; 
            var _swatch_offset = 22; // Moved left 4 pixels (was 26)

            var _char_col = (array_length(instructions[0]) > 3) ? instructions[0][3] : 1;

            var _x0 = _x + 8;
            var _x1 = _x + 8 + _col_w;
            var _x2 = _x + 8 + (_col_w * 2);
            var _x3 = _x + 8 + (_col_w * 3);

            // BG Column
            draw_set_color(make_color_rgb(180, 180, 200));
            draw_text(_x0, _d021_y, "BG:");
            draw_set_color(scr_c64_pepto_colour(_d021_val));
            draw_rectangle(_x0 + _swatch_offset, _swatch_y, _x0 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h, false);

            // C1 Column
            draw_set_color(make_color_rgb(180, 180, 200));
            draw_text(_x1, _d021_y, "C1:");
            draw_set_color(scr_c64_pepto_colour(_d022_val));
            draw_rectangle(_x1 + _swatch_offset, _swatch_y, _x1 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h, false);

            // C2 Column
            draw_set_color(make_color_rgb(180, 180, 200));
            draw_text(_x2, _d021_y, "C2:");
            draw_set_color(scr_c64_pepto_colour(_d023_val));
            draw_rectangle(_x2 + _swatch_offset, _swatch_y, _x2 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h, false);

            // CH Column (Char Colour)
            draw_set_color(make_color_rgb(180, 180, 200));
            draw_text(_x3, _d021_y, "CH:");
            draw_set_color(scr_c64_pepto_colour(_char_col));
            draw_rectangle(_x3 + _swatch_offset, _swatch_y, _x3 + _swatch_offset + _swatch_w, _swatch_y + _swatch_h, false);
        }
		
    } else {
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_x + 8, _d018_y, "SELECT ASSET TO CALCULATE");
    }
}