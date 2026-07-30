/// @function scr_node_draw_macro_vector_bmp(_draw_x, _y)
function scr_node_draw_macro_vector_bmp(_draw_x, _y) {
    var _header_h   = 24;
    var _line_h     = 12;
    var _asset_name = string(instructions[0][1]);
    var _fill_stack = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 0;
    var _render_now = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 1;

    var _asset     = undefined;
    var _bmp_addr  = 0x4000;
    var _cmd_count = 0;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "VECTOR_BITMAP" && _a.name == _asset_name) {
                _asset    = _a;
                _bmp_addr = _a.address;
                if (variable_struct_exists(_a.meta, "commands")) _cmd_count = array_length(_a.meta.commands);
                break;
            }
        }
    }
    var _has_asset = (_asset != undefined);
    var _vic_bank  = floor(_bmp_addr / 0x4000);
    var _cia_val   = 3 - _vic_bank;
    var _c_edit    = make_color_rgb(120, 220, 120);

    draw_set_font(fnt_c64_tiny);
    var _ly = _y + _header_h + 4;

    // Row 1: Asset name (click to pick)
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _ly, "ASSET:");
    draw_set_color(_has_asset ? c_lime : (_name_hover ? c_white : make_color_rgb(200, 80, 80)));
    draw_text(_draw_x + 72, _ly, _asset_name == "" ? "CLICK TO SET" : _asset_name);
    _ly += _line_h;

    // Row 2: Bitmap addr (synced from asset)
    var _bh = string_upper(decimal_to_hex(_bmp_addr));
    while (string_length(_bh) < 4) _bh = "0" + _bh;
    draw_set_color(c_gray);  draw_text(_draw_x + 10, _ly, "BITMAP:");
    draw_set_color(c_aqua);  draw_text(_draw_x + 80, _ly, "$" + _bh);
    _ly += _line_h;

    // Row 3: VIC bank
    draw_set_color(c_gray);   draw_text(_draw_x + 10, _ly, "VIC BANK:");
    draw_set_color(c_yellow); draw_text(_draw_x + 90, _ly, string(_vic_bank) + "  CIA=$0" + string(_cia_val));
    _ly += _line_h;

    // Row 4: Command count / data status
    draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "CMDS:");
    if (_has_asset) {
        draw_set_color(_cmd_count > 0 ? make_color_rgb(80, 200, 80) : c_orange);
        draw_text(_draw_x + 52, _ly, string(_cmd_count) + (_cmd_count > 0 ? " primitives" : " (EMPTY)"));
    } else {
        draw_set_color(make_color_rgb(200, 60, 60));
        draw_text(_draw_x + 52, _ly, "NO ASSET");
    }
    _ly += _line_h;

    // Row 5: Fill stack base (editable hex field — click to set, +/- to adjust).
    // Base drives BOTH regions: fill stack = base..base+$07FF, stream = base+$0800.
    var _fs = (_fill_stack == 0) ? 0x8000 : _fill_stack;
    var _fsh = string_upper(decimal_to_hex(_fs));
    while (string_length(_fsh) < 4) _fsh = "0" + _fsh;
    var _sth = string_upper(decimal_to_hex(_fs + 0x0800));
    while (string_length(_sth) < 4) _sth = "0" + _sth;
    var _fs_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 78, _ly, _draw_x + width - 8, _ly + 11);
    draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "BASE:");
    draw_set_color(_fs_hover ? c_white : c_aqua);
    draw_text(_draw_x + 78, _ly, "$" + _fsh + (_fill_stack == 0 ? " (def)" : ""));
    _ly += _line_h;
    // Row 6: derived stream addr (read-only, follows base)
    draw_set_color(c_gray);   draw_text(_draw_x + 10, _ly, "STREAM:");
    draw_set_color(c_yellow); draw_text(_draw_x + 80, _ly, "$" + _sth);
    _ly += _line_h;
}