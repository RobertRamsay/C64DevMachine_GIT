/// @desc scr_node_draw_macro_track(draw_x, y)
/// Draws the MACRO_TRACK node body content.

function scr_node_draw_macro_track(_draw_x, _y) {

    var _header_h   = 24;
    var _line_h   = 12;
	var _linked_init = 0x1000;
    var _best_dist   = 999999;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID") {
            var _d = point_distance(x, y, other.x, other.y);
            if (_d < _best_dist) {
                _best_dist = _d;
                var _asset_name = string(instructions[0][1]);
                if (instance_exists(obj_asset_manager) && _asset_name != "") {
                    var _am = obj_asset_manager;
                    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                        var _a = ds_list_find_value(_am.asset_list, _ai);
                        if (_a.type == "SID_MUSIC" && _a.name == _asset_name) {
                            _linked_init = variable_struct_exists(_a.meta, "sid_init_addr")
                                         ? _a.meta.sid_init_addr : _a.address;
                            break;
                        }
                    }
                }
            }
        }
    }
	
    var _ih = decimal_to_hex(_linked_init);
    while (string_length(_ih) < 4) _ih = "0" + _ih;
	var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)

	
    draw_set_font(fnt_c64_tiny);
    var _tly = _y + _header_h + 4;
    draw_set_color(_c_dim); draw_text(_draw_x + 8,  _tly,           "INIT:");
    draw_set_color(c_aqua);   draw_text(_draw_x + 60, _tly,           "$" + string_upper(_ih));
	draw_set_color(_c_edit); draw_text(_draw_x + 8,  _tly + _line_h, "TRACK:");
    var _track_val = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0;
    draw_set_color(c_yellow); draw_text(_draw_x + 70, _tly + _line_h, string(_track_val));


}
