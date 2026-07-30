/// @desc Draw MACRO_MAP_SWITCH node
/// @param {real} draw_x
/// @param {real} draw_y
/// @param {real} cam_x
/// @param {real} cam_y
/// @param {real} cam_zoom
function scr_node_draw_macro_map_switch(draw_x, draw_y, cam_x, cam_y, cam_zoom) {

    var _asset_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _has_asset  = (_asset_name != "");

    var _header_h = 28;
    var _line_h   = 18;
    var _pad      = 8;
    var _ly       = draw_y + _header_h + _pad;

    // MAP PICKER BUTTON
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "MAP:");
    var _pb_x1    = draw_x + 44;
    var _pb_x2    = draw_x + width - 8;
    var _pb_y1    = _ly - 2;
    var _pb_y2    = _ly + 14;
    var _pb_hover = point_in_rectangle(mouse_x, mouse_y, _pb_x1, _pb_y1, _pb_x2, _pb_y2);
    draw_set_color(_pb_hover ? make_color_rgb(80, 200, 120) : make_color_rgb(30, 60, 40));
    draw_rectangle(_pb_x1, _pb_y1, _pb_x2, _pb_y2, false);
    draw_set_color(_has_asset ? c_lime : make_color_rgb(150, 150, 150));
    draw_set_halign(fa_center);
    draw_text(_pb_x1 + (_pb_x2 - _pb_x1) * 0.5, _ly,
              _has_asset ? _asset_name : "[ PICK MAP ]");
    draw_set_halign(fa_left);
    _ly += _line_h + 2;

    // STATUS — show what will happen at runtime
    draw_set_font(fnt_c64_tiny);
    if (_has_asset) {
        // Look up asset meta for size info
        var _map_w = 40;
        var _map_h = 25;
        var _map_addr = 0;
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = ds_list_find_value(_am.asset_list, _ai);
                if (_a.type == "MAP_DATA" && _a.name == _asset_name) {
                    if (variable_struct_exists(_a.meta, "map_w")) { _map_w = _a.meta.map_w; }
                    if (variable_struct_exists(_a.meta, "map_h")) { _map_h = _a.meta.map_h; }
                    _map_addr = _a.address;
                    break;
                }
            }
        }
        draw_set_color(c_ltgray);
        draw_text(draw_x + 8, _ly, "SIZE: " + string(_map_w) + " x " + string(_map_h));
        _ly += _line_h;
		draw_set_color(c_ltgray);
        var _addr_hex = decimal_to_hex(_map_addr);
        if (string_length(_addr_hex) < 4) { _addr_hex = string_repeat("0", 4 - string_length(_addr_hex)) + _addr_hex; }
        draw_text(draw_x + 8, _ly, "ADDR: $" + string_upper(_addr_hex)); 
        _ly += _line_h;

    } else {
        draw_set_color(make_color_rgb(150, 80, 80));
        draw_text(draw_x + 8, _ly, "NO MAP SELECTED");
        _ly += _line_h;
        draw_set_color(make_color_rgb(100, 100, 100));
        draw_text(draw_x + 8, _ly, "PICK A MAP ASSET");
    }
}