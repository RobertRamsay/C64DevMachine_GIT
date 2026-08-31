/// @function scr_node_draw_macro_mouse(_draw_x, _y)
/// @desc MACRO_MOUSE node body. Laid out to match scr_node_draw_macro_joy —
///       same header offsets, same line pitch, same "interactive is green,
///       value is aqua, enabled is yellow" colour language — so the two input
///       macros read as a pair.
function scr_node_draw_macro_mouse(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    var _i0   = instructions[0];
    var _port = 1;
    if (array_length(_i0) > 1 && is_real(_i0[1])) {
        _port = real(_i0[1]);
    }
    var _zp = 0xF7;
    if (array_length(_i0) > 2 && is_real(_i0[2])) {
        _zp = real(_i0[2]);
    }
    var _yinv = 1;
    if (array_length(_i0) > 3 && is_real(_i0[3])) {
        _yinv = real(_i0[3]);
    }

    var _c_edit = make_color_rgb(120, 220, 120);
    draw_set_font(fnt_c64_tiny);
    var _my = _y + _header_h + 4;

    // ---- PORT ----
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _my, "PORT:                           (JSR CALLS)");
    draw_set_color(_port == 1 ? c_yellow : c_gray);
    draw_text(_draw_x + 60, _my, "1");
    draw_set_color(_port == 2 ? c_yellow : c_gray);
    draw_text(_draw_x + 80, _my, "2");
    _my += _line_h + 2;

    // ---- ZP BASE ----
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _my, "ZP:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 60, _my, "$" + scr_mouse_hex2(_zp) + " (7 BYTES)");
    _my += _line_h + 2;

    // ---- Y AXIS SENSE ----
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _my, "Y AXIS:");
    draw_set_color(c_yellow);
    if (_yinv == 1) {
        draw_text(_draw_x + 60, _my, "SCREEN (DOWN +)");
    } else {
        draw_text(_draw_x + 60, _my, "RAW (UP +)");
    }
    _my += _line_h + 2;

    // ---- WHERE THE RESULT LANDS ----
    // The whole point of the node: these are the addresses your own code reads.
    draw_set_color(make_color_rgb(150, 170, 200));
    draw_text(_draw_x + 8, _my,
              "X $" + scr_mouse_hex2(_zp + 2) + "/$" + scr_mouse_hex2(_zp + 3)
            + "  Y $" + scr_mouse_hex2(_zp + 4) + "/$" + scr_mouse_hex2(_zp + 5));
    _my += _line_h + 6;

    // ---- CALL GRID ----
    // Two rows, five columns, same pitch as the MACRO_JOY grid.
    //   row 0: buttons     LMB RMB
    //   row 1: movement    LF RT UP DN
    draw_set_font(fnt_C64_Angled);

    var _grid_labels = [
        ["LMB", "RMB"],
        ["LF ", "RT ", "UP ", "DN "]
    ];
    var _grid_idx = [
        [1, 2],
        [3, 4, 5, 6]
    ];

    var _col_w = (width - 4) / 5;

    for (var _r = 0; _r < array_length(_grid_idx); _r++) {
        var _row_data = _grid_idx[_r];
        for (var _c = 0; _c < array_length(_row_data); _c++) {
            var _ins_idx = _row_data[_c];
            if (_ins_idx >= array_length(instructions)) {
                continue;
            }

            var _enabled = false;
            if (array_length(instructions[_ins_idx]) > 2 && real(instructions[_ins_idx][2]) == 1) {
                _enabled = true;
            }

            draw_set_color(_enabled ? c_yellow : make_color_rgb(110, 90, 90));
            draw_text(_draw_x + 6 + (_c * _col_w), _my, _grid_labels[_r][_c]);
        }
        _my += _line_h + 2;
    }
}

/// @function scr_mouse_hex2(_v)
/// @desc Two-digit uppercase hex, the spelling used everywhere on these nodes.
function scr_mouse_hex2(_v) {
    var _h = string_upper(decimal_to_hex(_v & 0xFF));
    while (string_length(_h) < 2) {
        _h = "0" + _h;
    }
    return _h;
}
