/// =============================================================
/// scr_node_draw_inc_var(draw_x, y)
/// Called from the Draw event switch for node_type == "INC_VAR"
/// =============================================================
function scr_node_draw_inc_var() {
    var _name  = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
    var _addr  = ds_map_exists(global.named_loc_map, _name)
                 ? ds_map_find_value(global.named_loc_map, _name) : -1;
    var _meta  = scr_nloc_find_meta(_name);
    var _size  = (_meta != undefined) ? _meta.size : 1;
    var _enc   = (_meta != undefined && variable_struct_exists(_meta, "encoding")) ? _meta.encoding : "byte";
    var _lh = 12;
    var _ly = y + 28;
    draw_set_font(fnt_c64_tiny);
    var _name_hov = point_in_rectangle(mouse_x, mouse_y, x + 10, _ly - 2, x + width - 8, _ly + 10);
    draw_set_color(_name_hov ? c_lime : c_yellow);
    draw_text(x + 10, _ly - 2, _name != "" ? scr_nloc_display_name(_name) : "< SELECT >");
    _ly += _lh;
    if (_addr >= 0) {
        var _hex = decimal_to_hex(_addr);
        while (string_length(_hex) < 4) _hex = "0" + _hex;
        draw_set_color(c_aqua);
             var _addr_disp = global.use_hex_display
            ? ("@ $" + string_upper(_hex))
            : ("@ " + string(_addr));
        draw_text(x + 10, _ly, _addr_disp);
    } else {
        draw_set_color(c_red);
        draw_text(x + 10, _ly, "UNKNOWN NAME");
    }
    _ly += _lh;
    draw_set_color(make_color_rgb(120, 200, 120));
    switch (_size) {
        case 1: draw_text(x + 10, _ly, "INC $" + ((_addr >= 0) ? string_upper(decimal_to_hex(_addr)) : "??"));        break;
        case 2: draw_text(x + 10, _ly, "INC LO + BCC HI");  break;
        default: draw_text(x + 10, _ly, "INC (1 BYTE)");     break;
    }
    _ly += _lh;
    draw_set_color(make_color_rgb(80, 80, 120));
    draw_text(x + 10, _ly, "[" + string_upper(_enc) + "]");
}

