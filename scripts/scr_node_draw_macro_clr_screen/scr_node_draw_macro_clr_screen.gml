/// @desc scr_node_draw_macro_clr_screen(_draw_x, _y)
/// instructions[0]: ["macro_clr_screen", 1 scr_base (hex), 2 fill (0-255)]

function scr_node_draw_macro_clr_screen(_draw_x, _y) {

    var _ins = instructions[0];

    var _scr_base = (array_length(_ins) > 1 && is_real(_ins[1])) ? real(_ins[1]) : 0x0400;
    var _fill     = (array_length(_ins) > 2 && is_real(_ins[2])) ? clamp(real(_ins[2]), 0, 255) : 0;

    var _lh    = 14;
    var _ly    = _y + 28;
    var _c_lbl = make_color_rgb(140, 160, 200);

    draw_set_font(fnt_c64_tiny);

    // ── Row 1: BASE ──
    var _base_edit = (obj_workspace_manager.is_entering_text &&
                      obj_workspace_manager.input_target_node  == id &&
                      obj_workspace_manager.input_target_index == 1);

    var _sb_hex = decimal_to_hex(_scr_base);
    while (string_length(_sb_hex) < 4) _sb_hex = "0" + _sb_hex;

    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "BASE:");
    if (_base_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, "$" + obj_workspace_manager.current_input_string);
    } else {
        draw_set_color(c_aqua);
        draw_text(_draw_x + 52, _ly, "$" + string_upper(_sb_hex));
    }
    _ly += _lh;

    // ── Row 2: FILL ──
    var _fill_edit = (obj_workspace_manager.is_entering_text &&
                      obj_workspace_manager.input_target_node  == id &&
                      obj_workspace_manager.input_target_index == 2);

    var _f_hex = decimal_to_hex(_fill & 0xFF);
    while (string_length(_f_hex) < 2) _f_hex = "0" + _f_hex;

    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "FILL:");
    if (_fill_edit) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, obj_workspace_manager.current_input_string);
    } else {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, "$" + string_upper(_f_hex) + "  (" + string(_fill) + ")");
    }
    _ly += _lh;

    // ── Footer: coverage ──
    var _end = _scr_base + 0x3E7;
    var _eh  = decimal_to_hex(_end);
    while (string_length(_eh) < 4) _eh = "0" + _eh;
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    draw_text(_draw_x + 8, _ly, "WIPES $" + string_upper(_sb_hex) + "-$" + string_upper(_eh));
}