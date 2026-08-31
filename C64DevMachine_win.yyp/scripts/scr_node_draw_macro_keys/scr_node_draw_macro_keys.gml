/// @function scr_node_draw_macro_keys(_draw_x, _y)
/// @desc Shared body for MACRO_LETTERS / MACRO_FNNUMBERS / MACRO_MISCKEYS.
///       One grid of toggles, laid out from scr_key_category_list, so all
///       three nodes behave identically and only the key list differs.
function scr_node_draw_macro_keys(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    var _cat  = scr_key_category_list(node_type);
    var _cols = _cat.cols;

    var _zp = 0xF0;
    if (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) {
        _zp = real(instructions[0][1]);
    }

    // One bit per key in the list, so the ZP block is as wide as the category
    // needs and no wider — 4 bytes for the letters, 2 for the numbers.
    var _zp_bytes = ceil(array_length(_cat.keys) / 8);

    draw_set_font(fnt_c64_tiny);
    var _ky = _y + _header_h + 4;

    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 8, _ky, "ZP:");
    draw_set_color(c_aqua);
    var _zp_hex = string_upper(decimal_to_hex(_zp & 0xFF));
    while (string_length(_zp_hex) < 2) {
        _zp_hex = "0" + _zp_hex;
    }
    draw_text(_draw_x + 44, _ky, "$" + _zp_hex + "  " + string(_zp_bytes) + "B HELD");
    _ky += _line_h + 6;

    // ---- KEY GRID ----
    draw_set_font(fnt_C64_Angled);
    var _col_w = (width - 8) / _cols;

    for (var _si = 1; _si < array_length(instructions); _si++) {
        var _idx = _si - 1;
        var _c   = _idx mod _cols;
        var _r   = _idx div _cols;

        var _row = instructions[_si];
        if (array_length(_row) < 3) {
            continue;
        }

        var _enabled = (real(_row[2]) == 1);
        draw_set_color(_enabled ? c_yellow : make_color_rgb(105, 90, 90));
        draw_text(_draw_x + 6 + (_c * _col_w), _ky + (_r * (_line_h + 2)),
                  scr_key_slot_label(string(_row[0])));
    }
}
