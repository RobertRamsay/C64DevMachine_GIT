function scr_node_draw_macro_text_scroll(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
    // 1. Data Extraction
    var _row      = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 23;
    var _colour   = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 1;
    var _speed    = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 2;
    var _addr     = (array_length(instructions[0]) > 5 && is_real(instructions[0][5])) ? real(instructions[0][5]) : 0xC000;
    var _txt      = (array_length(instructions[0]) > 6) ? string(instructions[0][6]) : "HELLO WORLD ";
    var _text_src = (array_length(instructions[0]) > 9 && is_real(instructions[0][9]))  ? real(instructions[0][9])  : 0;
    var _pre_nop  = (array_length(instructions[0]) > 7 && is_real(instructions[0][7])) ? real(instructions[0][7]) : 6;
    var _post_nop = (array_length(instructions[0]) > 8 && is_real(instructions[0][8])) ? real(instructions[0][8]) : 27;
    var _jsr_mode = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
    var _asset_name = (array_length(instructions[0]) > 10) ? string(instructions[0][10]) : "";
    var _charset_nm = (array_length(instructions[0]) > 13) ? string(instructions[0][13]) : "";
    var _raw_alias = (array_length(instructions[0]) > 12 && is_string(instructions[0][12])) ? string(instructions[0][12]) : "";

    var _use_sid = 0;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID" && is_connected) { _use_sid = 1; break; }
    }

    // Local standard colors
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green for editable labels
    var _c_dim  = make_color_rgb(120, 120, 120);    // Dimmed for non-editable labels
    
    var _px = _draw_x + 8;
    var _ly = _y + 28;
    var _lh = 12;
    draw_set_font(fnt_c64_tiny);

  
    // ROW 0 — SCROLL ROW
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "SCROLL ROW (DEC):");
    draw_set_color(c_aqua); // Value remains Aqua
    draw_text(_px + string_width("SCROLL ROW (DEC): "), _ly, string(_row));
    _ly += _lh;

    // ROW 1 — INIT COLOUR
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "COLOUR:");
    
    // Inlined color name lookup to prevent crashes
    var _c_names = ["BLACK","WHITE","RED","CYAN","PURPLE","GREEN","BLUE","YELLOW","ORANGE","BROWN","LT.RED","DK.GRY","GREY","LT.GRN","LT.BLU","LT.GRY"];
    var _c_name = (_colour >= 0 && _colour <= 15) ? _c_names[_colour] : "???";
    
    draw_set_color(scr_c64_pepto_colour(_colour)); // Value remains Pepto
    draw_text(_px + 76, _ly, string(_colour) + " (" + _c_name + ")");
    _ly += _lh;

    // ROW 2 — INIT SPEED
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "SPEED:");
    draw_set_color(c_aqua); // Value remains Aqua
    draw_text(_px + 66, _ly, string(_speed) + " PX/FRAME");
    _ly += _lh;

    // ROW 4 — TEXT ADDRESS
    var _addr_str = (global.use_hex_display) ? ("$" + string_upper(decimal_to_hex(_addr))) : string(_addr);
    if (_text_src == 1) {
        draw_set_color(_c_dim); // Non-editable label
        draw_text(_px, _ly, "DATA ADDR:");
        draw_set_color(make_color_rgb(100, 120, 100)); // Dimmed value
        draw_text(_px + 100, _ly, _addr_str);
    } else {
        draw_set_color(_c_edit); // Editable label
        draw_text(_px, _ly, "DATA ADDR:");
        draw_set_color(make_color_rgb(255, 200, 80)); // Original value color
        draw_text(_px + 100, _ly, _addr_str);
    }
    _ly += _lh;

    // ROW 5 — CHARSET ASSET
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "CHARSET:");
    draw_set_color(_charset_nm != "" ? c_lime : c_orange);
    draw_text(_px + 80, _ly, _charset_nm != "" ? _charset_nm : "ROM DEFAULT");
    _ly += _lh;

    // ROW 6 — TEXT SRC toggle
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "TEXT SRC:");
    draw_set_color(_text_src == 0 ? c_aqua : c_lime);
    draw_text(_px + 86, _ly, _text_src == 0 ? "INLINE" : "ASSET");
    _ly += _lh;

    // ROW 6 — TEXT/ASSET CONTENT
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, (_text_src == 0 ? "TEXT:" : "ASSET:"));
    if (_text_src == 0) {
        draw_set_color(make_color_rgb(160, 230, 160));
        var _preview = string_copy(_txt, 1, 12);
        if (string_length(_txt) > 12) _preview += "...";
        draw_text(_px + 40, _ly, "'' " + _preview + " ''");
    } else {
        draw_set_color(_asset_name == "" ? c_orange : c_lime);
        draw_text(_px + 60, _ly, _asset_name == "" ? "< NONE >" : _asset_name);
    }
    _ly += _lh;

    // ROW 7 — PRE-NOP
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "PRE-NOP:");
    draw_set_color(make_color_rgb(255, 180, 80));
    draw_text(_px + 80, _ly, string(_pre_nop) + " CYCLES");
    _ly += _lh;

    // ROW 8 — POST-NOP
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "POST-NOP:");
    draw_set_color(make_color_rgb(255, 180, 80));
    draw_text(_px + 85, _ly, string(_post_nop) + " CYCLES");
    _ly += _lh;

    // ROW 9 — JSR MODE
    var _jchk_col = (_jsr_mode == 1) ? c_lime : make_color_rgb(80, 60, 20);
    draw_set_color(_jchk_col);
    draw_rectangle(_px + 4, _ly + 4, _px + 12, _ly + 12, false);

    draw_set_color(_c_edit); 
    draw_text(_px + 18, _ly, "JSR MODE");

    if (_jsr_mode == 1) {
        _ly += _lh;
        draw_set_color(c_fuchsia);
        draw_text(_px, _ly, "CALL:");
        var _alias = (_raw_alias != "") ? _raw_alias : ("ts" + string(real(id)));
        draw_set_color(make_color_rgb(255, 200, 80));
        draw_text(_px + 40, _ly, _alias + "_scrl");

        if (jsr_called == 0) {
            var _call_w  = string_width(_alias + "_scrl");
            var _flash_w = (current_time mod 800 < 400) ? c_red : c_yellow;
            draw_set_color(_flash_w);
			draw_set_font(fnt_c64_pico);
            draw_text(_px + 40 + _call_w + 8, _ly, "(NOT CALLED)");
			draw_set_font(fnt_c64_tiny);
        }
    }
    _ly += _lh;

    // ALIAS row
    draw_set_color(_c_edit); 
    draw_text(_px, _ly, "ALIAS:");
    var _alias_val = (_raw_alias != "") ? _raw_alias : "< SET ALIAS >";
    draw_set_color((_raw_alias != "") ? make_color_rgb(255, 200, 80) : c_orange);
    draw_text(_px + 60, _ly, _alias_val);
    _ly += _lh;

    node_height = _ly - _y + 10;
	
	  // Warning banner
    if (_use_sid == 0) {
		draw_set_alpha(0.8);
		draw_rectangle_colour(_draw_x,_y+20,_draw_x+width,_y+height,c_red,c_black,c_red,c_black,0)
		draw_set_alpha(1.0);
		var _flash_col = (current_time mod 600 < 300) ? c_white : c_black;
	    draw_set_color(_flash_col);
		draw_set_halign(fa_center)
	    draw_text(_draw_x + (width / 2), (_y+_ly)/2, "! REQUIRES MACRO_SID !");
		draw_set_halign(fa_left)
	}

			
}