function scr_node_draw_macro_save_game(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
    var _header_h = 24;
    var _line_h   = 12;

    var _org_name  = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _file_name = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "";

    var _org_asset  = undefined;
    var _file_addr  = 0;
    var _file_size  = 0;
    var _file_asset = undefined;
    if (instance_exists(obj_asset_manager) && _org_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "LOAD_ORG" && _a.name == _org_name) {
                _org_asset = _a;
                break;
            }
        }
        if (_file_name != "") {
            for (var _fi = 0; _fi < ds_list_size(_am.asset_list); _fi++) {
                var _fa = ds_list_find_value(_am.asset_list, _fi);
                if (_fa.name == _file_name) {
                    _file_asset = _fa;
                    _file_addr  = _fa.address;
                    if (buffer_exists(_fa.buffer)) {
                        _file_size = buffer_get_size(_fa.buffer);
                    }
                    break;
                }
            }
        }
    }

    var _c_edit = make_color_rgb(220, 140, 60);
    var _c_dim  = make_color_rgb(120, 120, 120);

    draw_set_font(fnt_c64_tiny);
    var _ly = _y + _header_h + 4;

    var _org_hov = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _ly, "DISK:");
    draw_set_color((_org_asset != undefined) ? make_color_rgb(20, 40, 60) : make_color_rgb(60, 20, 60));
    draw_rectangle(_draw_x + 68, _ly + 2, _draw_x + width - 8, _ly + 15, false);
    draw_set_color((_org_asset != undefined) ? c_aqua : (_org_hov ? c_white : make_color_rgb(180, 80, 180)));
    draw_text(_draw_x + 72, _ly, (_org_name == "") ? "CLICK TO SET" : _org_name);
    _ly += _line_h;

    var _file_hov = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _ly, "FILE:");
    draw_set_color((_file_name != "") ? make_color_rgb(20, 40, 60) : make_color_rgb(40, 40, 40));
    draw_rectangle(_draw_x + 68, _ly + 2, _draw_x + width - 8, _ly + 15, false);
    draw_set_color((_file_name != "") ? c_yellow : (_file_hov ? c_white : make_color_rgb(100, 100, 100)));
    draw_text(_draw_x + 72, _ly, (_file_name == "") ? "-- NONE --" : _file_name);
    _ly += _line_h;

    var _ah = string_upper(decimal_to_hex(_file_addr));
    while (string_length(_ah) < 4) _ah = "0" + _ah;
    draw_set_color(_c_dim);   draw_text(_draw_x + 10, _ly, "ADDR:");
    draw_set_color(c_aqua);   draw_text(_draw_x + 70, _ly, "$" + _ah);
    _ly += _line_h;

    draw_set_color(_c_dim);   draw_text(_draw_x + 10, _ly, "SIZE:");
    draw_set_color(c_aqua);
    if (_file_size > 0) {
        draw_text(_draw_x + 70, _ly, string(_file_size) + " BYTES");
    } else {
        draw_text(_draw_x + 70, _ly, "--");
    }
    _ly += _line_h + 4;

    if (_org_asset != undefined && _file_name != "") {
        var _is_linked = false;
        if (variable_struct_exists(_org_asset, "linked_assets")) {
            var _links = _org_asset.linked_assets;
            for (var _li = 0; _li < array_length(_links); _li++) {
                if (_links[_li].asset_name == _file_name) {
                    _is_linked = true;
                    break;
                }
            }
        }
        var _is_save_slot = (_file_asset != undefined
            && _file_asset.type == "BYTE_DATA"
            && variable_struct_exists(_file_asset.meta, "is_save_file")
            && _file_asset.meta.is_save_file);

        draw_set_halign(fa_center);
        if (!_is_linked) {
            var _flash = (current_time mod 600 < 300) ? c_white : c_red;
            draw_set_color(_flash);
            draw_text(_draw_x + (width / 2), _ly, "FILE NOT IN DISK!");
        } else if (!_is_save_slot) {
            draw_set_color(c_yellow);
            draw_text(_draw_x + (width / 2), _ly, "NOT A SAVE-FILE BYTE_DATA");
        } else {
            draw_set_color(make_color_rgb(220, 140, 60));
            draw_text(_draw_x + (width / 2), _ly, "WRITES TO DISK");
        }
        draw_set_halign(fa_left);
    }
}