function scr_node_draw_macro_joy(_draw_x, _y) {
    var _header_h   = 24;
    var _line_h   = 12;
    var _port     = is_real(instructions[0][1]) ? real(instructions[0][1]) : 2;
    var _zp       = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0xF8;
    var _zp_hex   = string_upper(decimal_to_hex(_zp));
    while (string_length(_zp_hex) < 2) _zp_hex = "0" + _zp_hex;

var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    draw_set_font(fnt_c64_tiny);
    var _jly = _y + _header_h + 4;

    // Header UI: Port and ZP
    draw_set_color(_c_edit);
    draw_text(_draw_x + 8, _jly, "PORT:                           (JSR CALLS)");
    draw_set_color(_port == 1 ? c_yellow : c_gray);
    draw_text(_draw_x + 60, _jly, "1");
    draw_set_color(_port == 2 ? c_yellow : c_gray);
    draw_text(_draw_x + 80, _jly, "2");


    _jly += _line_h+2;

    draw_text(_draw_x + 8,  _jly, "ZP:");
    draw_set_color(c_aqua);
    draw_text(_draw_x + 60, _jly, "$" + _zp_hex);
    _jly += _line_h+8;

    // Grid Layout Definition
    var _grid_labels = [
        ["UP ", "DN ", "LF ", "RT ", "FR "],
        ["UPF", "DNF", "LFF", "RTF"],
        ["UPL", "UPR", "DNL", "DNR"],
        ["ULF", "URF", "DLF", "DRF", "NON"]
    ];
    var _grid_idx = [
        [14, 15, 16, 17, 13],
        [9, 10, 11, 12],
        [6, 5, 8, 7],
        [2, 1, 4, 3, 18]
    ];

    draw_set_font(fnt_C64_Angled);
    var _col_w = (width - 4) / 5;

    for (var _r = 0; _r < array_length(_grid_idx); _r++) {
        var _row_data = _grid_idx[_r];
        var _row_active = false;
        

        for (var _c = 0; _c < array_length(_row_data); _c++) {
            var _ins_idx = _row_data[_c];
            var _enabled = real(instructions[_ins_idx][2]);
            var _label   = _grid_labels[_r][_c];


            draw_set_color(_enabled ? c_yellow : make_color_rgb(110, 90, 90));
            draw_text(_draw_x + 6 + (_c * _col_w), _jly, _label);
        }
        _jly += _line_h+2;
    }
	
}