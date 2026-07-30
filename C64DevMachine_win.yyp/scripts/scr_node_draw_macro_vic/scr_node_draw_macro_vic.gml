function scr_node_draw_macro_vic(_draw_x) {
    var _header_h   = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;
    var _lx       = _draw_x + 8;
    var _vx       = _draw_x + 90;

	var _mode     = string(instructions[0][1]);
    var _vic_bank = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _scr_addr_raw = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
    var _chr_addr = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0x2000;
    var _scr_addr = (_mode == "BITMAP" || _mode == "MCB") ? (_chr_addr + 0x2000) : _scr_addr_raw;
    var _border   = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0;
    var _bg0      = is_real(instructions[0][6]) ? real(instructions[0][6]) : 0;
    var _bg1      = is_real(instructions[0][7]) ? real(instructions[0][7]) : 0;
    var _bg2      = is_real(instructions[0][8]) ? real(instructions[0][8]) : 0;
    var _bg3      = is_real(instructions[0][9]) ? real(instructions[0][9]) : 0;

    var _bank_base  = _vic_bank * 0x4000;
    var _scr_offset = floor((_scr_addr - _bank_base) / 0x0400) & 0x0F;
    var _d018_val   = 0;
    if (_mode == "BITMAP" || _mode == "BMP" || _mode == "MCB") {
        var _bmp_offset = floor((_chr_addr - _bank_base) / 0x2000) & 0x01;
        _d018_val = (_scr_offset << 4) | (_bmp_offset << 3);
    } else {
        var _chr_offset = floor((_chr_addr - _bank_base) / 0x0800) & 0x07;
        _d018_val = (_scr_offset << 4) | (_chr_offset << 1);
    }

    var _c_dim = make_color_rgb(120, 120, 120);
	var _c_edit = make_color_rgb(120, 220, 120);
    var _c_val = make_color_rgb(255, 220, 100);
    var _bw    = 35;

	draw_set_font(fnt_c64_tiny);

// Row 0: Mode buttons (Compact & Transformed)
    draw_set_color(_c_edit); draw_text(_lx, _fy, "MODE");
    var _modes = ["TXT", "MCT", "ECM", "HRB", "MCB"];
    var _mfull = ["TEXT", "MCT", "ECM", "BITMAP", "MCB"];
    var _bx = _lx + 48; // More space after "MODE"
    var _btn_w = 30;    // Narrower buttons
    for (var _mi = 0; _mi < 5; _mi++) {
        var _active = (_mfull[_mi] == _mode);
        draw_set_color(_active ? make_color_rgb(80, 180, 80) : make_color_rgb(50, 50, 50));
        draw_rectangle(_bx, _fy+2, _bx + _btn_w - 8, _fy + _line_h + 1, false);
        draw_set_color(_active ? c_white : _c_dim);
        // Squish text to 75% width
        draw_text_transformed(_bx , _fy , _modes[_mi], 0.78, 1, 0);
        _bx += _btn_w;
    }
    _fy += _line_h + 8;

    // Row 2: VIC Bank
    draw_set_color(_c_edit); draw_text(_lx, _fy, "VIC BANK");
    draw_set_color(_c_val); draw_text(_vx, _fy, string(_vic_bank)
        + " $" + string_upper(decimal_to_hex(_bank_base))
        + "-$" + string_upper(decimal_to_hex(_bank_base + 0x3FFF)));
    _fy += _line_h;

    // Row 3: Screen RAM
    var _scr_editable = (_mode != "BITMAP" && _mode != "BMP" && _mode != "MCB");
    draw_set_color(_scr_editable ? _c_edit : _c_dim);
    draw_text(_lx, _fy, "SCR RAM");
    draw_set_color(_c_val);
    draw_text(_vx, _fy, "$" + string_upper(decimal_to_hex(_scr_addr)));
    _fy += _line_h;

    // Row 4: Char/Bitmap address
    draw_set_color(_c_edit); draw_text(_lx, _fy, (_mode == "BITMAP" || _mode == "MCB") ? "BMP ADDR" : "CHR ADDR");
    draw_set_color(_c_val); draw_text(_vx, _fy, "$" + string_upper(decimal_to_hex(_chr_addr)));
    _fy += _line_h;

    // Row 5: D018 (computed, read-only)
    draw_set_color(_c_dim); draw_text(_lx, _fy, "D018");
    draw_set_color(make_color_rgb(180, 180, 180)); draw_text(_vx, _fy, "$" + string_upper(decimal_to_hex(_d018_val)));
    if (_mode == "MCT") {
        var _btn_x1 = _vx + 50;
        var _btn_x2 = _draw_x + width - 8;
        var _btn_y1 = _fy - 20;
        var _btn_y2 = _fy + _line_h - 1;
        var _btn_hover = point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2);
        draw_set_color(_btn_hover ? make_color_rgb(80, 180, 80) : make_color_rgb(30, 60, 30));
        draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, false);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, true);
        draw_set_font(fnt_C64_Angled_tiny);
        draw_set_color(_btn_hover ? c_white : make_color_rgb(160, 200, 160));
        draw_set_halign(fa_center);
        draw_text_transformed(_btn_x1 + (_btn_x2 - _btn_x1) * 0.5, _fy-14, "GET MAP\nCOLORS",0.72,0.9,0);
        draw_set_halign(fa_left);
        draw_set_font(fnt_c64_tiny);
    }
    _fy += _line_h + 4;

    // Row 6: Combined Color Swatches
    var _cx = _lx;
    var _sw = 16; // Swatch width (1.6x)
	var _swx = _cx+32
	var _swy = _fy+1
    var _gap = 40; // Space between color pickers
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_c_edit); draw_text(_cx, _fy, "BDR");
    scr_draw_c64_colour_swatch(_swx, _swy, _border, _sw, _sw);
    _cx += _gap + 8;
	_swx += _gap + 4;

    draw_set_color(_c_edit); draw_text(_cx, _fy, "BKG");
    scr_draw_c64_colour_swatch(_swx, _swy, _bg0, _sw, _sw);
    _cx += _gap + 8;
	_swx += _gap + 4;

    if (_mode == "MCT" || _mode == "MCB") {
        draw_set_color(_c_edit); draw_text(_cx, _fy, "MC1");
        scr_draw_c64_colour_swatch(_swx, _swy, _bg1, _sw, _sw);
        _cx += _gap + 4;
		_swx += _gap + 4;
        draw_set_color(_c_edit); draw_text(_cx, _fy, "MC2");
        scr_draw_c64_colour_swatch(_swx, _swy, _bg2, _sw, _sw);
    } else if (_mode == "ECM") {
        draw_set_color(_c_edit); draw_text(_cx, _fy, "BG1");
        scr_draw_c64_colour_swatch(_swx, _swy, _bg1, _sw, _sw);
        _cx += _gap + 4;
		_swx += _gap + 4;
        draw_set_color(_c_edit); draw_text(_cx, _fy, "BG2");
        scr_draw_c64_colour_swatch(_swx, _swy, _bg2, _sw, _sw);
        // BG3 is tight, might need a second color row or wider node
    }
    
    _fy += _line_h + 10;
    node_height = _fy - y + 10;
}