/// @desc Draw CLEAR BMP RECT node body
function scr_node_draw_macro_clear_bmp_rect(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    while (array_length(instructions[0]) < 6) {
        array_push(instructions[0], 0);
    }

    var _bmp = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0x4000;
    var _col = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _row = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
    var _w   = is_real(instructions[0][4]) ? real(instructions[0][4]) : 40;
    var _h   = is_real(instructions[0][5]) ? real(instructions[0][5]) : 25;

    var _bh = string_upper(decimal_to_hex(_bmp));
    while (string_length(_bh) < 4) _bh = "0" + _bh;

    var _c_edit = make_color_rgb(120, 220, 120);

    draw_set_font(fnt_c64_tiny);
    var _ply = _y + _header_h + 4;

    // Row 1: target bitmap
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "BMP:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 70, _ply, "$" + _bh);
    _ply += _line_h;

    // Row 2: COL / ROW — top-left cell of the rect
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8,  _ply, "COL:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 40, _ply, string(_col));
    draw_set_color(_c_edit);
    draw_text(_draw_x + 70, _ply, "ROW:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 102, _ply, string(_row));
    _ply += _line_h;

    // Row 3: W / H — size in cells
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8,  _ply, "W:");
    draw_set_color(c_lime);
    draw_text(_draw_x + 40, _ply, string(_w));
    draw_set_color(_c_edit);
    draw_text(_draw_x + 70, _ply, "H:");
    draw_set_color(c_lime);
    draw_text(_draw_x + 102, _ply, string(_h));
    _ply += _line_h;

    // Warn when the rect spills off the 40x25 grid — compile trims it, so the
    // node would silently clear less than the numbers claim.
    if (_col + _w > 40 || _row + _h > 25) {
        draw_set_font(fnt_c64_pico);
        draw_set_color(make_color_rgb(230, 170, 60));
        draw_text(_draw_x + 8, _ply, "! RECT OFF GRID - WILL BE TRIMMED");
        draw_set_font(fnt_c64_tiny);
        _ply += _line_h;
    }

    // Footer: what actually gets written.
    draw_set_font(fnt_c64_pico);
    draw_set_color(make_color_rgb(80, 120, 180));
    var _cw = min(_w, max(0, 40 - _col));
    var _ch = min(_h, max(0, 25 - _row));
    draw_text(_draw_x + 8, _ply,
        string(_cw * _ch * 8) + "B ZEROED  ->  BG ($D021)");
}