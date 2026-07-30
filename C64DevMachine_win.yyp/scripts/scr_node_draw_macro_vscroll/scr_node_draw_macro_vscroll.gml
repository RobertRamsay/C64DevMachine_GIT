/// @desc Draw MACRO_VSCROLL node
function scr_node_draw_macro_vscroll(_draw_x, _draw_y, _cam_x, _cam_y, _cam_zoom) {

    // instructions[0] layout:
    //   [0]="MACRO_VSCROLL" [1]=start_col [2]=col_count [3]=colour_mode

    var _start_col = (array_length(instructions[0]) > 1 && is_real(instructions[0][1])) ? real(instructions[0][1]) : 0;
    var _col_count = (array_length(instructions[0]) > 2 && is_real(instructions[0][2])) ? real(instructions[0][2]) : 40;
    var _col_mode  = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 1;

    var _col_labels = ["NONE", "DEFERRED", "INLINE"];
    var _col_str    = _col_labels[clamp(_col_mode, 0, 2)];

    var _px = _draw_x + 8;
    var _ly = _draw_y + 24 + 4;
    var _lh = 18;
    draw_set_font(fnt_c64_code);

    // ROW 0 — START COL
    draw_set_color(c_gray);
    draw_text(_px,       _ly, "START COL:");
    draw_set_color(c_aqua);
    draw_text(_px + 100, _ly, string(_start_col));
    _ly += _lh;

    // ROW 1 — COL COUNT
    draw_set_color(c_gray);
    draw_text(_px,       _ly, "COL COUNT:");
    draw_set_color(c_aqua);
    draw_text(_px + 100, _ly, string(_col_count));
    draw_set_color(make_color_rgb(70, 130, 140));
    draw_text(_px + 130, _ly, string(_start_col) + " to " + string(_start_col + _col_count - 1));
    _ly += _lh;

    // ROW 3 — scroll note
    draw_set_color(c_gray);
    draw_text(_px, _ly, "SPEED = 1px per JSR");
    _ly += _lh;

    // ROW 4 — JSR Up
    draw_set_color(c_gray);
    draw_text(_px,      _ly, "JSR UP  :");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Scroller_U");
    _ly += _lh;

    // ROW 5 — JSR Down
    draw_set_color(c_gray);
    draw_text(_px,      _ly, "JSR DOWN:");
    draw_set_color(c_yellow);
    draw_text(_px + 90, _ly, "Scroller_D");
    _ly += _lh;

    // ROW 6 — memory notice
    var _scr2_end = 0x0C00 + 0x0400 - 1;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(180, 100, 30));
   // draw_text(_px, _ly, "USES $0C00-$" + string_upper(decimal_to_hex(_scr2_end)) + " (SCR BUF 2)");
 //   _ly += _lh;

    // ROW 7 — $D011 note
  //  draw_set_color(make_color_rgb(100, 100, 160));
  //  draw_text(_px, _ly, "OWNS $D011 BITS 0-2 (FINE V SCROLL)");
 //   _ly += _lh;

    draw_set_font(fnt_c64_code);
}