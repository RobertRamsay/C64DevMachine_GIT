function scr_node_draw_new_str() {
    // Pad instructions to expected length
    while (array_length(instructions[0]) <= 5) array_push(instructions[0], "");
    if (!is_real(instructions[0][4])) instructions[0][4] = 0;
    if (!is_real(instructions[0][2])) instructions[0][2] = pc_address;

    var _inst   = instructions[0];
    var _name   = (array_length(_inst) > 1) ? string(_inst[1]) : "";
    var _inline = (array_length(_inst) > 3) ? string(_inst[3]) : "";
    var _use_as = (array_length(_inst) > 4 && is_real(_inst[4])) ? real(_inst[4]) : 0;
    var _asname = (array_length(_inst) > 5) ? string(_inst[5]) : "";

node_title = "UV STR";
    var _ly = y + 25;

    draw_set_font(fnt_c64_code);
    draw_set_color(make_color_rgb(230, 200, 120));
    draw_text(x + 8, _ly, _name != "" ? _name : "< NO NAME >");

    // Address
    var _hex = decimal_to_hex(pc_address);
    while (string_length(_hex) < 4) _hex = "0" + _hex;
    draw_set_font(fnt_c64_tiny);
    if (org_parent == noone) {
        draw_set_color(make_color_rgb(160, 120, 20));
        draw_text(x + 8, _ly + 14, "$----");
    } else {
        draw_set_color(c_aqua);
        draw_text(x + 8, _ly + 14, "$" + string_upper(_hex));
    }

    // Source toggle label
    draw_set_color(_use_as == 0 ? make_color_rgb(180, 180, 80) : make_color_rgb(80, 180, 180));
    draw_text(x + 60, _ly + 14, _use_as == 0 ? "[INLINE]" : "[ASSET]");

    // Content preview
    draw_set_font(fnt_c64_tiny);
    var _preview = "";
    if (_use_as == 0) {
        _preview = string_length(_inline) > 0 ? "\"" + string_copy(_inline, 1, min(string_length(_inline), 22)) + "\"" : "<EMPTY>";
    } else {
        _preview = _asname != "" ? _asname : "<NO ASSET>";
    }
    draw_set_color(c_ltgray);
    draw_text(x + 8, _ly + 28, _preview);

    // Byte count
    //var _byte_count = _use_as == 0 ? (string_length(_inline) + 1) : 0;
	var _byte_count = _use_as == 0 ? string_length(_inline) : 0;
    if (_use_as == 1 && _asname != "" && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "TEXT_DATA" && _a.name == _asname) {
               // _byte_count = buffer_exists(_a.buffer) ? buffer_get_size(_a.buffer) : 0;
				_byte_count = buffer_exists(_a.buffer) ? max(0, buffer_get_size(_a.buffer) - 1) : 0;
                break;
            }
        }
    }
    draw_set_color(make_color_rgb(100, 100, 140));
    draw_text(x + 8, _ly + 40, string(_byte_count) + " BYTES [STR]");
}