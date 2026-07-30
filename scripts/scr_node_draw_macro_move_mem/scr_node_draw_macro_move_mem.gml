/// @desc Draw MOVE_MEM node body
function scr_node_draw_macro_move_mem(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 14;
    var _src_s    = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0xC000;
    var _src_e    = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0xC100;
    var _dst      = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0500;

    if (_src_e < _src_s) _src_e = _src_s;
    var _bytes = (_src_e - _src_s) + 1;  // inclusive: end byte counts
    var _capped = (_bytes > 1024);
    if (_capped) _bytes = 1024;

    var _src_s_h = string_upper(decimal_to_hex(_src_s)); while (string_length(_src_s_h) < 4) _src_s_h = "0" + _src_s_h;
    var _src_e_h = string_upper(decimal_to_hex(_src_e)); while (string_length(_src_e_h) < 4) _src_e_h = "0" + _src_e_h;
    var _dst_h   = string_upper(decimal_to_hex(_dst));   while (string_length(_dst_h)   < 4) _dst_h   = "0" + _dst_h;
    var _dst_e   = _dst + _bytes-1;
    var _dst_e_h = string_upper(decimal_to_hex(_dst_e)); while (string_length(_dst_e_h) < 4) _dst_e_h = "0" + _dst_e_h;

    var _c_edit = make_color_rgb(120, 220, 120);
    var _c_dim  = make_color_rgb(120, 120, 120);

    draw_set_font(fnt_c64_tiny);
    var _ply = _y + _header_h + 4;

    // Row 1: FROM
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "FROM:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 48, _ply, "$" + _src_s_h);
    draw_set_color(_c_dim);
    draw_text(_draw_x + 100, _ply, "->");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 118, _ply, "$" + _src_e_h);
    _ply += _line_h;

    // Row 2: TO
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "TO:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 48, _ply, "$" + _dst_h);
    draw_set_color(_c_dim);
    draw_text(_draw_x + 100, _ply, "->");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 118, _ply, "$" + _dst_e_h);
    _ply += _line_h;

    // Row 3: byte count
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    draw_text(_draw_x + 8, _ply, string(_bytes) + " BYTES");
    if (_capped) {
        draw_set_color(c_red);
        draw_text(_draw_x + 80, _ply, "(CAPPED @1024)");
    }
    _ply += _line_h;

    // Row 4: cost preview
    draw_set_color(make_color_rgb(80, 120, 180));
    if (_bytes <= 8) {
        draw_text(_draw_x + 8, _ply-2, "UNROLLED (" + string(_bytes * 6) + " B)");
    } else {
        var _pages = ceil(_bytes / 256);
        draw_text(_draw_x + 8, _ply-3, "LOOP x" + string(_pages) + " PAGE" + ((_pages > 1) ? "S" : ""));
    }
}