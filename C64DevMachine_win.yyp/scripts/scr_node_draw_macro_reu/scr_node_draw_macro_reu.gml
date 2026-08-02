/// @desc Draw body content for MACRO_REU node
function scr_node_draw_macro_reu(_draw_x, _y) {

    var _header_h = 24;
    var _line_h   = 16;
    var _inst     = instructions[0];

    while (array_length(_inst) < 9) {
        array_push(_inst, 0);
    }

    var _op       = real(_inst[1]);
    var _c64_addr = real(_inst[2]);
    var _reu_addr = real(_inst[3]);
    var _bank     = real(_inst[4]);
    var _len      = real(_inst[5]);
    var _autoload = real(_inst[6]);
    var _fix_c64  = real(_inst[7]);
    var _fix_reu  = real(_inst[8]);

    var _lx = _draw_x + 8;
    var _rx = _draw_x + width - 6;
    var _cy = _y + _header_h + 4;

    var _op_labels = ["STASH (C64->REU)", "FETCH (REU->C64)", "SWAP", "COMPARE"];

    // Row 0: OP dropdown
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "OP:");

    var _op_bx1 = _lx + 30;
    var _op_bx2 = _rx;
    var _op_hov = point_in_rectangle(mouse_x, mouse_y, _op_bx1, _cy + 4, _op_bx2, _cy + 10);
    draw_set_color(_op_hov ? make_color_rgb(90, 60, 160) : make_color_rgb(40, 30, 70));
    draw_rectangle(_op_bx1, _cy + 1, _op_bx2, _cy + 11, false);

    var _op_txt = (_op >= 0 && _op <= 3) ? _op_labels[_op] : "STASH (C64->REU)";
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_op_bx1 + _op_bx2) / 2, _cy, _op_txt);
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 1: C64 ADDR
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "C64:");

    var _c64_bx1 = _lx + 44;
    var _c64_bx2 = _rx;
    var _c64_hov = point_in_rectangle(mouse_x, mouse_y, _c64_bx1, _cy + 4, _c64_bx2, _cy + 10);
    draw_set_color(_c64_hov ? make_color_rgb(60, 80, 140) : make_color_rgb(34, 44, 64));
    draw_rectangle(_c64_bx1, _cy + 1, _c64_bx2, _cy + 11, false);

    var _c64_hex = decimal_to_hex(_c64_addr);
    while (string_length(_c64_hex) < 4) {
        _c64_hex = "0" + _c64_hex;
    }
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text((_c64_bx1 + _c64_bx2) / 2, _cy, "$" + string_upper(_c64_hex));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 2: REU ADDR
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "REU:");

    var _reu_bx1 = _lx + 44;
    var _reu_bx2 = _rx;
    var _reu_hov = point_in_rectangle(mouse_x, mouse_y, _reu_bx1, _cy + 4, _reu_bx2, _cy + 10);
    draw_set_color(_reu_hov ? make_color_rgb(60, 80, 140) : make_color_rgb(34, 44, 64));
    draw_rectangle(_reu_bx1, _cy + 1, _reu_bx2, _cy + 11, false);

    var _reu_hex = decimal_to_hex(_reu_addr);
    while (string_length(_reu_hex) < 4) {
        _reu_hex = "0" + _reu_hex;
    }
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text((_reu_bx1 + _reu_bx2) / 2, _cy, "$" + string_upper(_reu_hex));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 3: BANK
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "BANK:");

    var _bank_bx1 = _lx + 44;
    var _bank_bx2 = _rx;
    var _bank_hov = point_in_rectangle(mouse_x, mouse_y, _bank_bx1, _cy + 4, _bank_bx2, _cy + 10);
    draw_set_color(_bank_hov ? make_color_rgb(60, 80, 140) : make_color_rgb(34, 44, 64));
    draw_rectangle(_bank_bx1, _cy + 1, _bank_bx2, _cy + 11, false);

    draw_set_color(c_aqua);
    draw_set_halign(fa_center);
    draw_text((_bank_bx1 + _bank_bx2) / 2, _cy, string(_bank));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 4: LEN
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "LEN:");

    var _len_bx1 = _lx + 44;
    var _len_bx2 = _rx;
    var _len_hov = point_in_rectangle(mouse_x, mouse_y, _len_bx1, _cy + 4, _len_bx2, _cy + 10);
    draw_set_color(_len_hov ? make_color_rgb(60, 80, 140) : make_color_rgb(34, 44, 64));
    draw_rectangle(_len_bx1, _cy + 1, _len_bx2, _cy + 11, false);

    var _len_hex = decimal_to_hex(_len);
    while (string_length(_len_hex) < 4) {
        _len_hex = "0" + _len_hex;
    }
    draw_set_color(c_lime);
    draw_set_halign(fa_center);
    draw_text((_len_bx1 + _len_bx2) / 2, _cy, "$" + string_upper(_len_hex));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 5: AUTOLOAD toggle
    var _al_bx1 = _lx;
    var _al_bx2 = _rx;
    var _al_hov = point_in_rectangle(mouse_x, mouse_y, _al_bx1, _cy + 4, _al_bx2, _cy + 10);
    if (_autoload == 1) {
        draw_set_color(_al_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 50, 30));
    } else {
        draw_set_color(_al_hov ? make_color_rgb(80, 60, 40) : make_color_rgb(50, 40, 25));
    }
    draw_rectangle(_al_bx1, _cy + 1, _al_bx2, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_al_bx1 + _al_bx2) / 2, _cy, (_autoload == 1) ? "AUTOLOAD: ON" : "AUTOLOAD: OFF");
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 6: FIX C64 toggle
    var _fc_bx1 = _lx;
    var _fc_bx2 = _rx;
    var _fc_hov = point_in_rectangle(mouse_x, mouse_y, _fc_bx1, _cy + 4, _fc_bx2, _cy + 10);
    if (_fix_c64 == 1) {
        draw_set_color(_fc_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 50, 30));
    } else {
        draw_set_color(_fc_hov ? make_color_rgb(80, 60, 40) : make_color_rgb(50, 40, 25));
    }
    draw_rectangle(_fc_bx1, _cy + 1, _fc_bx2, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_fc_bx1 + _fc_bx2) / 2, _cy, (_fix_c64 == 1) ? "FIX C64 ADDR: ON" : "FIX C64 ADDR: OFF");
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 7: FIX REU toggle
    var _fr_bx1 = _lx;
    var _fr_bx2 = _rx;
    var _fr_hov = point_in_rectangle(mouse_x, mouse_y, _fr_bx1, _cy + 4, _fr_bx2, _cy + 10);
    if (_fix_reu == 1) {
        draw_set_color(_fr_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 50, 30));
    } else {
        draw_set_color(_fr_hov ? make_color_rgb(80, 60, 40) : make_color_rgb(50, 40, 25));
    }
    draw_rectangle(_fr_bx1, _cy + 1, _fr_bx2, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_fr_bx1 + _fr_bx2) / 2, _cy, (_fix_reu == 1) ? "FIX REU ADDR: ON" : "FIX REU ADDR: OFF");
    draw_set_halign(fa_left);
    _cy += _line_h;
}
