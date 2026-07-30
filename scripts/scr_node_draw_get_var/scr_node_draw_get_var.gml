function scr_node_draw_get_var() {
    // Backfill defensively for old 2-slot saves
    while (array_length(instructions[0]) < 8) array_push(instructions[0], "");
    if (!is_real(instructions[0][2])) instructions[0][2] = 0;
    if (!is_real(instructions[0][4])) instructions[0][4] = 0;
    if (!is_real(instructions[0][5])) instructions[0][5] = 0;

    var _src_mode = real(instructions[0][2]); // 0=var, 1=asset
    var _off_mode = real(instructions[0][4]); // 0=none/lit, 1=var, 2=X, 3=Y
    var _name     = string(instructions[0][1]);
    var _asset    = string(instructions[0][3]);
    var _off_lit  = real(instructions[0][5]);
    var _off_var  = string(instructions[0][6]);

    var _lh = 18;
    var _ly = y + 28;
    draw_set_font(fnt_c64_tiny);

    // ---- SRC MODE TOGGLE (top-left) ----
    var _sm_x1 = x + 10;
    var _sm_x2 = x + 80;
    var _sm_hov = point_in_rectangle(mouse_x, mouse_y, _sm_x1, _ly - 2, _sm_x2, _ly + 12);
    draw_set_color(_sm_hov ? make_color_rgb(60, 120, 80) : make_color_rgb(30, 60, 40));
    draw_rectangle(_sm_x1, _ly, _sm_x2+2, _ly + 14, false);
    draw_set_color(c_lime);
    draw_text(_sm_x1 + 4, _ly - 2, (_src_mode == 0) ? "SRC:VAR " : "SRC:ASSET ");

    if (_src_mode == 0) {
        // ============ VAR MODE (original layout) ============
        // Var name (row 1) — click the text to open the VAR picker
        var _vname_disp = _name != "" ? _name : "< SELECT >";
        var _vname_x    = x + 90;
        var _vname_hov  = point_in_rectangle(mouse_x, mouse_y, _vname_x, _ly - 4, x + width - 8, _ly + 12);
        draw_set_color(_vname_hov ? c_white : c_yellow);
        draw_text(_vname_x, _ly - 2, _vname_disp);
        _ly += _lh;

        var _addr = ds_map_exists(global.named_loc_map, _name)
                    ? ds_map_find_value(global.named_loc_map, _name) : -1;
        var _meta = scr_nloc_find_meta(_name);
        var _size = (_meta != undefined) ? _meta.size : 1;
        var _enc  = (_meta != undefined && variable_struct_exists(_meta, "encoding")) ? _meta.encoding : "byte";

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
        draw_set_color(make_color_rgb(120, 180, 120));
        switch (_size) {
            case 1: draw_text(x + 10, _ly, "LOADS: A");         break;
            case 2: draw_text(x + 10, _ly, "LOADS: A=lo X=hi"); break;
            case 3: draw_text(x + 10, _ly, "LOADS: A X Y");     break;
        }
        _ly += _lh;
        draw_set_color(make_color_rgb(80, 80, 120));
        draw_text(x + 10, _ly, "[" + string_upper(_enc) + "]");

    } else {
        // ============ ASSET MODE ============
        // Resolve asset base address from asset_manager
        var _abase = -1;
        if (_asset != "" && instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = _am.asset_list[| _ai];
                if (_a.type == "BYTE_DATA" && _a.name == _asset) { _abase = _a.address; break; }
            }
        }

        // Asset name (row 1) — click the text to open the asset picker
        var _aname_disp = _asset != "" ? _asset : "< ASSET >";
        var _aname_x    = x + 90;
        var _aname_hov  = point_in_rectangle(mouse_x, mouse_y, _aname_x, _ly - 4, x + width - 8, _ly + 12);
        draw_set_color(_aname_hov ? c_white : c_yellow);
        draw_text(_aname_x, _ly - 2, _aname_disp);
        _ly += _lh;

        // Base address line (row 2)
        if (_abase >= 0) {
            var _hex = decimal_to_hex(_abase);
            while (string_length(_hex) < 4) _hex = "0" + _hex;
            draw_set_color(c_aqua);
            draw_text(x + 10, _ly, global.use_hex_display ? ("@ $" + string_upper(_hex)) : ("@ " + string(_abase)));
        } else {
            draw_set_color(c_red);
            draw_text(x + 10, _ly, "UNKNOWN ASSET");
        }
        _ly += _lh;

        // Offset mode toggle (row 3, left) — cycles NONE/LIT -> VAR -> X -> Y
        var _ofb_x1 = x + 10;
        var _ofb_x2 = x + 64;
        var _ofb_hov = point_in_rectangle(mouse_x, mouse_y, _ofb_x1, _ly, _ofb_x2, _ly + 12);
        draw_set_color(_ofb_hov ? make_color_rgb(60, 120, 80) : make_color_rgb(30, 60, 40));
        draw_rectangle(_ofb_x1, _ly+2, _ofb_x2, _ly + 13, false);
        draw_set_color(c_lime);
        var _ofl = "OFF";
        switch (_off_mode) {
            case 0: _ofl = "OFF:LIT"; break;
            case 1: _ofl = "OFF:VAR"; break;
            case 2: _ofl = "OFF:X";   break;
            case 3: _ofl = "OFF:Y";   break;
        }
        draw_text(_ofb_x1 , _ly - 1, _ofl);

        // Offset value display (row 3, middle) — literal shows value, VAR is clickable text
        if (_off_mode == 0) {
            draw_set_color(c_yellow);
            var _off_disp = global.use_hex_display
                ? ("$" + string_upper(decimal_to_hex(_off_lit)))
                : string(_off_lit);
            draw_text(_ofb_x2 , _ly - 1, "+" + _off_disp);
        } else if (_off_mode == 1) {
            var _ovname = _off_var != "" ? _off_var : "< VAR >";
            var _ov_hov = point_in_rectangle(mouse_x, mouse_y, _ofb_x2 + 8, _ly - 3, x + width - 8, _ly + 12);
            draw_set_color(_ov_hov ? c_white : c_yellow);
            draw_text(_ofb_x2 + 8, _ly - 1, _ovname);
        } else {
            draw_set_color(make_color_rgb(120, 180, 120));
            draw_text(_ofb_x2 + 8, _ly - 1, (_off_mode == 2) ? "via X" : "via Y");
        }
        _ly += _lh;

        // Dest var line (row 4) — click text to pick a UV var (empty = leave in A)
        var _dest_var  = string(instructions[0][7]);
        var _dst_disp  = _dest_var != "" ? ("-> " + _dest_var) : "LOADS: A";
        var _dst_x     = x + 10;
        var _dst_hov   = point_in_rectangle(mouse_x, mouse_y, _dst_x, _ly - 3, x + width - 8, _ly + 12);
        if (_dest_var != "") {
            draw_set_color(_dst_hov ? c_white : make_color_rgb(120, 180, 120));
        } else {
            draw_set_color(_dst_hov ? c_white : make_color_rgb(80, 80, 120));
        }
        draw_text(_dst_x, _ly, _dst_disp);
    }
}