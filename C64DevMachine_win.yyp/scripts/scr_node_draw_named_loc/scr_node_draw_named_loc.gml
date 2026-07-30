function scr_node_draw_named_loc() {
    // NEW_STR nodes use their own layout
    if (node_type == "NEW_STR") {
        scr_node_draw_new_str();
        return;
    }
    var _name = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
    var _meta = scr_nloc_find_meta(_name);
	
    var _lh   = 16;
    var _ly   = y + 25;
    var _is_hw = (_meta != undefined && _meta.type == "HW");
    node_title = _is_hw ? "HW REG" : "UV VAR";
    draw_set_font(fnt_c64_code);
    if (_meta != undefined) {
        var _name_col = _is_hw
            ? make_color_rgb(140, 200, 190)
            : make_color_rgb(180, 230, 140);
        draw_set_color(_name_col);
        draw_text(x + 8, _ly, _name);
        var _hex = decimal_to_hex(_meta.addr);
        while (string_length(_hex) < 4) _hex = "0" + _hex;
        draw_set_font(fnt_c64_tiny);
		
        if (org_parent == noone) 
			{draw_set_color(make_color_rgb(160, 120, 20)) ;draw_text(x + 8, _ly + 14, "$----")}
			else
			{draw_set_color(c_aqua);draw_text(x + 8, _ly + 14,"$" + string_upper(_hex) )}
				
		
		
		
        if (!_is_hw) {
            draw_set_color(make_color_rgb(120, 150, 100));
            draw_text(x + 60, _ly + 14, string(_meta.size) + "B [" + string_upper(_meta.encoding) + "]");
        } else {
            draw_set_color(make_color_rgb(90, 110, 110));
            draw_text(x + 60, _ly + 14, "[" + _meta.chip + "]");
        }
    } else {
        draw_set_color(c_red);
        draw_set_font(fnt_c64_code);
        draw_text(x + 8, _ly, _name != "" ? "? " + _name : "< NO NAME >");
    }
}