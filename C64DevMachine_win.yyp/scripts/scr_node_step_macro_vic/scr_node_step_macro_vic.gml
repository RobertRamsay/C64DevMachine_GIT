function scr_node_step_macro_vic(_draw_x) {
    var _header_h   = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;
    var _mode     = string(instructions[0][1]);
    var _vic_bank = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _scr_addr = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
    var _chr_addr = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0x2000;
    var _bw       = 35;
    var _bank_base = _vic_bank * 0x4000;

    // Row 0: Mode Selection (Matches Draw Rectangles)
    var _mfull = ["TEXT", "MCT", "ECM", "BITMAP", "MCB"];
    var _bx = _draw_x + 8 + 48; 
    var _btn_w = 30;
    for (var _mi = 0; _mi < 5; _mi++) {
        // Matches _fy + 2 and _btn_w - 8 from Draw
        if (point_in_rectangle(mouse_x, mouse_y, _bx, _fy + 2, _bx + _btn_w - 8, _fy + _line_h + 1)) {
            var _new_mode = _mfull[_mi];
            if (_new_mode != _mode) {
                var _was_bitmap = (_mode == "BITMAP" || _mode == "BMP" || _mode == "MCB");
                var _now_bitmap = (_new_mode == "BITMAP" || _new_mode == "MCB");
                instructions[0][1] = _new_mode;
                if (_was_bitmap != _now_bitmap) {
                    instructions[0][4] = _now_bitmap ? _bank_base : _bank_base + 0x0800;
                }
            }
            exit;
        }
        _bx += _btn_w;
    }
    _fy += _line_h + 8;

// Row 2: VIC Bank — click to cycle 0-3
	if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 90, _fy, _draw_x + width - 8, _fy + 16)) {
	    var _new_bank      = (_vic_bank + 1) mod 4;
	    var _new_base      = _new_bank * 0x4000;
	    var _cur_mode      = string(instructions[0][1]);
	    instructions[0][2] = _new_bank;
	    instructions[0][3] = _new_base + 0x0400;
	    if (_cur_mode == "BITMAP" || _cur_mode == "BMP" || _cur_mode == "MCB") {
	        instructions[0][4] = _new_base;
	    } else {
	        instructions[0][4] = _new_base + 0x0800;
	    }
	    exit;
	}
	_fy += _line_h;

    // Row 3: Screen RAM — cycle through valid positions within current VIC bank (text/MCT/ECM only)
    // In MCT mode the GET MAP COLS button occupies the right side, so cap the hitbox before it
    var _row_click_x2 = (_mode == "MCT") ? (_draw_x + 90 + 48) : (_draw_x + width - 8);
    if (_mode != "BITMAP" && _mode != "BMP" && _mode != "MCB") {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 90, _fy, _row_click_x2, _fy + _line_h - 1)) {
            var _scr_options = [];
            for (var _i = 0; _i < 16; _i++) {
                array_push(_scr_options, _bank_base + _i * 0x0400);
            }
            var _cur_scr = 0;
            for (var _i = 0; _i < 16; _i++) {
                if (_scr_options[_i] == _scr_addr) {
                    _cur_scr = _i;
                    break;
                }
            }
            instructions[0][3] = _scr_options[(_cur_scr + 1) mod 16];
            scr_c64_update_addresses();
            exit;
        }
    }
    _fy += _line_h;
	//_fy += _line_h;

    // Row 4: Char/Bitmap address — bitmap modes: 2 positions; text modes: 8 positions
    // Cap right edge in MCT so the GET MAP COLS button isn't swallowed
    var _row4_click_x2 = (_mode == "MCT") ? (_draw_x + 90 + 48) : (_draw_x + width - 8);
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 90, _fy, _row4_click_x2, _fy + _line_h - 1)) {
        if (_mode == "BITMAP" || _mode == "BMP" || _mode == "MCB") {
            var _bmp_options = [_bank_base, _bank_base + 0x2000];
            var _cur = 0;
            for (var _i = 0; _i < 2; _i++) {
                if (_bmp_options[_i] == _chr_addr) { _cur = _i; break; }
            }
            instructions[0][4] = _bmp_options[(_cur + 1) mod 2];
        } else {
            var _chr_options = [];
            for (var _i = 0; _i < 8; _i++) array_push(_chr_options, _bank_base + _i * 0x0800);
            var _cur = 0;
            for (var _i = 0; _i < 8; _i++) {
                if (_chr_options[_i] == _chr_addr) { _cur = _i; break; }
            }
            instructions[0][4] = _chr_options[(_cur + 1) mod 8];
        }
        exit;
    }
    _fy += _line_h;

    // Row 5: D018 — read only, but GET MAP COLS button visible in MCT mode
    // Hitbox matches the enlarged draw rect (_vx + 50, _fy - 20 .. _fy + _line_h - 1)
    if (_mode == "MCT") {
        var _btn_x1 = _draw_x + 90 + 50;
        var _btn_x2 = _draw_x + width - 8;
        var _btn_y1 = _fy - 20;
        var _btn_y2 = _fy + _line_h - 1;
        if (point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2)) {
			
            // Find closest MACRO_MAP node above this VIC node on the spine
            var _best_map = noone;
            var _best_y   = -999999;
            with (obj_c64_node) {
                if (node_type == "MACRO_MAP" && is_connected  ) {
					
                    _best_y   = y;
                    _best_map = id;
                }
            }
            if (instance_exists(_best_map)) {
				
                var _map_asset_name = (array_length(_best_map.instructions[0]) > 1) ? string(_best_map.instructions[0][1]) : "";
                if (_map_asset_name != "" && instance_exists(obj_asset_manager)) {
                    var _am = obj_asset_manager;
                    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                        var _a = ds_list_find_value(_am.asset_list, _ai);
                        if (_a.type == "MAP_DATA" && _a.name == _map_asset_name) {
                            if (variable_struct_exists(_a.meta, "map_mc_bg"))   instructions[0][6] = _a.meta.map_mc_bg;
                            if (variable_struct_exists(_a.meta, "map_mc_col1")) instructions[0][7] = _a.meta.map_mc_col1;
                            if (variable_struct_exists(_a.meta, "map_mc_col2")) instructions[0][8] = _a.meta.map_mc_col2;
                            scr_c64_update_addresses();
                            break;
                        }
                    }
                }
            }
            exit;
        }
    }
    _fy += _line_h + 4;

    // Row 6: Combined Color Swatches (Synchronized with Draw logic)
    var _cx = _draw_x + 8;
    var _sw = 16;
    var _swx = _cx + 32;
    var _swy = _fy + 1;
    var _gap = 40;
    
    // All four swatches open the 16-colour picker instead of advancing one
    // step per click. _sw is the swatch width, so the 256px bar is centred
    // over whichever swatch was hit and drops just under the swatch row.
    // Same picker MACRO_PRINT and MACRO_CHR already use.
    var _spawn_picker = function(_node, _sw_left, _sw_size, _sw_top, _col) {
        instance_destroy(obj_ui_color_picker);
        var _picker_w = 256;
        var _spawn_x  = (_sw_left + (_sw_size / 2)) - (_picker_w / 2);
        var _picker   = instance_create_depth(_spawn_x, _sw_top + _sw_size + 2, -9999, obj_ui_color_picker);
        _picker.target_node = _node;
        _picker.target_row  = 0;
        _picker.target_col  = _col;
        mouse_clear(mb_left);
    };

    // BDR
    if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
        _spawn_picker(id, _swx, _sw, _swy, 5);
        exit;
    }
    _swx += _gap + 4;

    // BKG (was labeled BG in step, now BKG to match draw)
    if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
        _spawn_picker(id, _swx, _sw, _swy, 6);
        exit;
    }
    _swx += _gap + 4;

    if (_mode == "MCT" || _mode == "MCB") {
        // MC1
        if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
            _spawn_picker(id, _swx, _sw, _swy, 7);
            exit;
        }
        _swx += _gap + 4;
        // MC2
        if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
            _spawn_picker(id, _swx, _sw, _swy, 8);
            exit;
        }
    } else if (_mode == "ECM") {
        // BG1
        if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
            _spawn_picker(id, _swx, _sw, _swy, 7);
            exit;
        }
        _swx += _gap + 4;
        // BG2
        if (point_in_rectangle(mouse_x, mouse_y, _swx, _swy, _swx + _sw, _swy + _sw)) {
            _spawn_picker(id, _swx, _sw, _swy, 8);
            exit;
        }
    }
}