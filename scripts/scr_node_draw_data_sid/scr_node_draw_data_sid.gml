/// @desc scr_node_draw_data_sid(draw_x, y)
/// Draws the DATA_SID node body content.

function scr_node_draw_data_sid(_draw_x, _y) {

    var _px  = _draw_x + 10;
    var _py  = _y + 24 + 6;
    var _has = (array_length(instructions[0]) > 1 &&
                string(instructions[0][1]) != "" &&
                string(instructions[0][1]) != "0");

    var _bx1  = _px;
    var _by1  = _py;
    var _bx2  = _draw_x + width - 8;
    var _by2  = _by1 + 20;
    var _bhov = point_in_rectangle(mouse_x, mouse_y, _bx1, _by1, _bx2, _by2);

    draw_set_color(_bhov ? make_color_rgb(80,160,220) : make_color_rgb(20,60,100));
    draw_rectangle(_bx1, _by1, _bx2, _by2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_font(fnt_c64_tiny);
    draw_text((_bx1 + _bx2) * 0.5, _by1 + 4, "IMPORT .SID");
    draw_set_halign(fa_left);

    if (_has) {
        draw_set_color(c_yellow);  draw_text(_px, _py + 26, variable_instance_exists(id, "sid_title")  ? sid_title  : "");
        draw_set_color(c_ltgray);  draw_text(_px, _py + 38, variable_instance_exists(id, "sid_author") ? sid_author : "");
        draw_set_color(c_aqua);    draw_text(_px, _py + 50, "TRACKS: " + string(variable_instance_exists(id, "sid_songs") ? sid_songs : 0));
        var _lh = decimal_to_hex(variable_instance_exists(id, "sid_load_addr") ? sid_load_addr : 0);
        draw_set_color(c_ltgray);  draw_text(_px, _py + 62, "LOAD: $" + string_upper(_lh));
        var _cia = variable_instance_exists(id, "sid_uses_cia") ? sid_uses_cia : false;
        draw_set_color(_cia ? c_yellow : c_aqua);
        draw_text(_px, _py + 74, _cia ? "CIA TIMER" : "RASTER IRQ");
    } else {
        draw_set_color(c_gray);
        draw_text(_px, _py + 26, "NO SID LOADED");
    }
}
