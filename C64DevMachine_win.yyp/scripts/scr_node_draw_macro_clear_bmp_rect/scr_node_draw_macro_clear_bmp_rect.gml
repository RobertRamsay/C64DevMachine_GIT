/// @desc Draw CLEAR BMP RECT node body
function scr_node_draw_macro_clear_bmp_rect(_draw_x, _y) {
    var _header_h = 24;
    var _line_h   = 12;

    // [1] bmp  [2] col  [3] row  [4] w  [5] h  — literals
    // [6] col var  [7] row var  [8] w var  [9] h var — "" = use the literal
    while (array_length(instructions[0]) < 6) {
        array_push(instructions[0], 0);
    }
    while (array_length(instructions[0]) < 10) {
        array_push(instructions[0], "");
    }

    var _bmp = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0x4000;
    var _col = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _row = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
    var _w   = is_real(instructions[0][4]) ? real(instructions[0][4]) : 40;
    var _h   = is_real(instructions[0][5]) ? real(instructions[0][5]) : 25;

    var _col_v = string(instructions[0][6]);
    var _row_v = string(instructions[0][7]);
    var _w_v   = string(instructions[0][8]);
    var _h_v   = string(instructions[0][9]);

    var _any_var = (_col_v != "" || _row_v != "" || _w_v != "" || _h_v != "");

    var _bh = string_upper(decimal_to_hex(_bmp));
    while (string_length(_bh) < 4) _bh = "0" + _bh;

    var _c_edit = make_color_rgb(120, 220, 120);
    var _c_dim  = make_color_rgb(120, 120, 120);
    var _c_var  = make_color_rgb(180, 140, 220);

    draw_set_font(fnt_c64_tiny);
    var _ply = _y + _header_h + 4;

    // Row 1: target bitmap
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _ply, "BMP:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 70, _ply, "$" + _bh);
    _ply += _line_h;

    // Row 2: COL / ROW — top-left cell of the rect. A literal whose slot has a
    // VAR assigned is dimmed: the runtime reads the var instead.
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8,  _ply, "COL:");
    if (_col_v == "") {
        draw_set_color(c_aqua);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 40, _ply, string(_col));
    draw_set_color(_c_edit);
    draw_text(_draw_x + 70, _ply, "ROW:");
    if (_row_v == "") {
        draw_set_color(c_aqua);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 102, _ply, string(_row));
    _ply += _line_h;

    // Row 3: W / H — size in cells
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8,  _ply, "W:");
    if (_w_v == "") {
        draw_set_color(c_lime);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 40, _ply, string(_w));
    draw_set_color(_c_edit);
    draw_text(_draw_x + 70, _ply, "H:");
    if (_h_v == "") {
        draw_set_color(c_lime);
    } else {
        draw_set_color(_c_dim);
    }
    draw_text(_draw_x + 102, _ply, string(_h));
    _ply += _line_h;

    // Rows 4-7: VAR pickers. <LIT> means the literal above is used.
    var _var_labels = ["COL VAR:", "ROW VAR:", "W VAR:", "H VAR:"];
    var _var_names  = [_col_v, _row_v, _w_v, _h_v];
    for (var _vi = 0; _vi < 4; _vi++) {
        draw_set_color(_c_edit);
        draw_text(_draw_x + 8, _ply, _var_labels[_vi]);
        if (_var_names[_vi] == "") {
            draw_set_color(_c_dim);
            draw_text(_draw_x + 70, _ply, "<LIT>");
        } else {
            draw_set_color(_c_var);
            draw_text(_draw_x + 70, _ply, _var_names[_vi]);
        }
        _ply += _line_h;
    }

    // Footer only when the rect is fully literal — with a var the byte count
    // isn't knowable here, so nothing is drawn.
    if (!_any_var) {
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
}
