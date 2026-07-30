/// @desc Draw MACRO_METAMAP node body
function scr_node_draw_macro_metamap(draw_x, draw_y, cam_x, cam_y, cam_zoom) {
    var _tileset_name = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
    var _map_index    = (array_length(instructions[0]) > 2) ? real(instructions[0][2]) : 0;
    var _has_tileset  = (_tileset_name != "");

    // Display-only truncation so a long name can't flood past the picker box.
    var _ts_disp = _tileset_name;
    if (string_length(_ts_disp) > 18) {
        _ts_disp = string_copy(_ts_disp, 1, 18) + "...";
    }

    // Resolve tileset to read map_count / stamp dims for display + clamping
    var _map_count   = 0;
    var _stamp_w     = 0;
    var _stamp_h     = 0;
    var _ts_resolved = false;
    if (_has_tileset && instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "META_TILESET" && _a.name == _tileset_name) {
                if (variable_struct_exists(_a.meta, "map_count")) _map_count = _a.meta.map_count;
                if (variable_struct_exists(_a.meta, "stamp_w"))   _stamp_w   = _a.meta.stamp_w;
                if (variable_struct_exists(_a.meta, "stamp_h"))   _stamp_h   = _a.meta.stamp_h;
                _ts_resolved = true;
                break;
            }
        }
    }
    // A name is set but no matching tileset exists (renamed/deleted/re-imported).
    var _ts_missing = (_has_tileset && !_ts_resolved);
    var _ts_flash   = ((current_time div 400) mod 2 == 0);

    // Clamp stored map_index if maps were deleted since it was set
    if (_map_count > 0 && _map_index > _map_count - 1) {
        _map_index = _map_count - 1;
        instructions[0][2] = _map_index;
    }
    if (_map_index < 0) {
        _map_index = 0;
        instructions[0][2] = 0;
    }

    var header_h = 28;
    var line_h   = 18;
    var pad      = 8;
    var _ly = draw_y + header_h + pad;

    // TILESET PICKER
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "TILESET:");
    var _pb_x1 = draw_x + 64;
    var _pb_x2 = draw_x + width - 8;
    var _pb_y1 = _ly - 2;
    var _pb_y2 = _ly + 14;
    var _pb_hover = point_in_rectangle(mouse_x, mouse_y, _pb_x1, _pb_y1, _pb_x2, _pb_y2);
    if (_ts_missing) {
        // Flashing red — the picked tileset no longer resolves to an asset.
        draw_set_color(_ts_flash ? make_color_rgb(90, 25, 25) : make_color_rgb(50, 15, 15));
        draw_rectangle(_pb_x1, _pb_y1, _pb_x2, _pb_y2, false);
        draw_set_color(_ts_flash ? make_color_rgb(220, 60, 60) : make_color_rgb(120, 40, 40));
        draw_rectangle(_pb_x1, _pb_y1, _pb_x2, _pb_y2, true);
        draw_set_color(_ts_flash ? c_white : make_color_rgb(220, 120, 120));
        draw_set_halign(fa_center);
        draw_text(_pb_x1 + (_pb_x2 - _pb_x1) * 0.5, _ly, _ts_disp + " ?");
        draw_set_halign(fa_left);
    } else {
        draw_set_color(_pb_hover ? make_color_rgb(80, 200, 120) : make_color_rgb(30, 60, 40));
        draw_rectangle(_pb_x1, _pb_y1, _pb_x2, _pb_y2, false);
        draw_set_color(_has_tileset ? c_lime : make_color_rgb(150, 150, 150));
        draw_set_halign(fa_center);
        draw_text(_pb_x1 + (_pb_x2 - _pb_x1) * 0.5, _ly, _has_tileset ? _ts_disp : "[ PICK TILESET ]");
        draw_set_halign(fa_left);
    }
    _ly += line_h + 2;

    // MAP INDEX SELECTOR — LIT spinner or VAR name picker
    // Defensive: if the var picker wrote the name into slot 6 (the src_mode
    // slot), repair the swap so real() never sees a string.
    if (array_length(instructions[0]) > 6 && is_string(instructions[0][6])) {
        var _stray = instructions[0][6];
        while (array_length(instructions[0]) < 8) array_push(instructions[0], "");
        instructions[0][7] = _stray;   // move name to its correct slot
        instructions[0][6] = 1;        // string present implies VAR mode
    }
    var _src_mode = (array_length(instructions[0]) > 6 && is_real(instructions[0][6])) ? real(instructions[0][6]) : 0;
    var _map_var  = (array_length(instructions[0]) > 7) ? string(instructions[0][7]) : "";

    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "MAP:");

    // LIT/VAR source toggle (small button just right of the MAP: label)
    var _ms_x1  = draw_x + 42;
    var _ms_x2  = draw_x + 78;
    var _ms_hov = point_in_rectangle(mouse_x, mouse_y, _ms_x1, _ly - 2, _ms_x2, _ly + 12);
    if (_src_mode == 1) {
        draw_set_color(_ms_hov ? make_color_rgb(160, 100, 80) : make_color_rgb(100, 60, 40));
    } else {
        draw_set_color(_ms_hov ? make_color_rgb(80, 100, 160) : make_color_rgb(40, 60, 100));
    }
    draw_rectangle(_ms_x1, _ly , _ms_x2, _ly + 15, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_ms_x1 + _ms_x2) * 0.5, _ly , (_src_mode == 1) ? "VAR" : "LIT");
    draw_set_halign(fa_left);

    if (_src_mode == 1) {
        // VAR MODE — click the name to open a var picker
        var _mv_x1  = draw_x + 84;
        var _mv_x2  = draw_x + width - 8;
        var _mv_hov = point_in_rectangle(mouse_x, mouse_y, _mv_x1, _ly - 2, _mv_x2, _ly + 12);
        draw_set_color(_mv_hov ? c_lime : c_yellow);
        draw_set_halign(fa_right);
        draw_text(_mv_x2, _ly, (_map_var != "") ? ("$" + _map_var) : "< MAP VAR >");
        draw_set_halign(fa_left);
    } else {
        // LIT MODE — existing - n/max + spinner
        var _mi_x1  = draw_x + width - 80;
        var _mi_mid = draw_x + width - 44;
        var _mi_x2  = draw_x + width - 8;
        var _mi_y1  = _ly ;
        var _mi_y2  = _ly + 16;
        draw_set_color(make_color_rgb(30, 60, 80));
        draw_rectangle(_mi_x1, _mi_y1, _mi_x2, _mi_y2, false);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_rectangle(_mi_x1, _mi_y1, _mi_x2, _mi_y2, true);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mi_x1 + 10, _ly, "-");
        if (_map_count > 0) {
            draw_text(_mi_mid, _ly, string(_map_index) + "/" + string(_map_count - 1));
        } else {
            draw_set_color(make_color_rgb(150, 150, 150));
            draw_text(_mi_mid, _ly, "--");
            draw_set_color(c_white);
        }
        draw_text(_mi_x2 - 10, _ly, "+");
        draw_set_halign(fa_left);
    }
    _ly += line_h + 2;

    // SCREEN TARGETS (fixed, like MACRO_MAP)
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "CHAR  -> $0400");
    _ly += line_h;
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "COLOR -> $D800");
    _ly += line_h;

    // FLATTEN INFO
    draw_set_color(make_color_rgb(100, 100, 100));
    if (_stamp_w > 0 && _stamp_h > 0) {
        var _cols = floor(40 / _stamp_w);
        var _rows = floor(25 / _stamp_h);
        draw_text(draw_x + 8, _ly, string(_cols) + "x" + string(_rows) + " METATILES -> 40x25");
    } else {
        draw_text(draw_x + 8, _ly, "PICK A TILESET");
    }
    _ly += line_h + 4;

    // ZP SOURCE POINTER
    var _zp_base = (array_length(instructions[0]) > 5) ? real(instructions[0][5]) : 0x50;
    var _zp_hex  = string_upper(decimal_to_hex(_zp_base));
    if (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;
    draw_set_color(c_ltgray);
    draw_text(draw_x + 8, _ly, "MAP SRC ZP:");
    var _zp_x1 = draw_x + 140;
    var _zp_x2 = draw_x + width - 8;
    var _zp_y1 = _ly ;
    var _zp_y2 = _ly + 16;
    var _zp_hover = point_in_rectangle(mouse_x, mouse_y, _zp_x1, _zp_y1, _zp_x2, _zp_y2);
    draw_set_color(_zp_hover ? make_color_rgb(80, 160, 200) : make_color_rgb(20, 40, 60));
    draw_rectangle(_zp_x1, _zp_y1, _zp_x2, _zp_y2, false);
    draw_set_color(make_color_rgb(80, 80, 80));
    draw_rectangle(_zp_x1, _zp_y1, _zp_x2, _zp_y2, true);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_zp_x1 + (_zp_x2 - _zp_x1) * 0.5, _ly, "$" + _zp_hex);
    draw_set_halign(fa_left);
    _ly += line_h;
}