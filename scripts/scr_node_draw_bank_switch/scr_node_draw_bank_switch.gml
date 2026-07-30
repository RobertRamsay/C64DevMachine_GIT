/// @desc Draw body content for BANK_SWITCH node
function scr_node_draw_bank_switch(_draw_x, _y) {

    var _header_h = 24;
    var _line_h   = 16;
    var _inst     = instructions[0];
    var _v01      = real(_inst[1]);
    var _keep_irq = real(_inst[2]);
    var _write_ddr = real(_inst[3]);
    var _mode_idx = real(_inst[4]);

    var _lx = _draw_x + 8;
    var _rx = _draw_x + width - 6;
    var _cy = _y + _header_h + 4;

    var _mode_labels = ["ALL RAM (24)", "ALL RAM (25)", "CHR+K (26)", "CHR+BAS+K (27)", "RAM+IO (28)", "RAM+IO (29)", "NO BASIC (30)", "DEFAULT (31)"];

    // Row 0: MODE dropdown
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "MODE:");

    var _mode_bx1 = _lx + 44;
    var _mode_bx2 = _rx;
    var _mode_hov = point_in_rectangle(mouse_x, mouse_y, _mode_bx1, _cy + 4, _mode_bx2, _cy + 10);
    if (_mode_hov) {
        draw_set_color(make_color_rgb(90, 60, 160));
    } else {
        draw_set_color(make_color_rgb(40, 30, 70));
    }
    draw_rectangle(_mode_bx1, _cy + 1, _mode_bx2, _cy + 11, false);

    var _mode_txt = "RAW";
    if (_mode_idx >= 0 && _mode_idx <= 7) {
        _mode_txt = _mode_labels[_mode_idx];
    }
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_mode_bx1 + _mode_bx2) / 2, _cy, _mode_txt);
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 1: RAW $01 value
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "$01:");

    var _val_bx1 = _lx + 44;
    var _val_bx2 = _rx;
    var _val_hov = point_in_rectangle(mouse_x, mouse_y, _val_bx1, _cy + 4, _val_bx2, _cy + 10);
    if (_val_hov) {
        draw_set_color(make_color_rgb(60, 80, 140));
    } else {
        draw_set_color(make_color_rgb(34, 44, 64));
    }
    draw_rectangle(_val_bx1, _cy + 1, _val_bx2, _cy + 11, false);

    var _v_hex = decimal_to_hex(_v01);
    while (string_length(_v_hex) < 2) {
        _v_hex = "0" + _v_hex;
    }
    draw_set_color(c_yellow);
    draw_set_halign(fa_center);
    draw_text((_val_bx1 + _val_bx2) / 2, _cy, "$" + string_upper(_v_hex));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 2: KEEP IRQ OFF toggle
    var _irq_bx1 = _lx;
    var _irq_bx2 = _rx;
    var _irq_hov = point_in_rectangle(mouse_x, mouse_y, _irq_bx1, _cy + 4, _irq_bx2, _cy + 10);
    if (_keep_irq == 1) {
        draw_set_color(_irq_hov ? make_color_rgb(160, 60, 60) : make_color_rgb(100, 30, 30));
    } else {
        draw_set_color(_irq_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 50, 30));
    }
    draw_rectangle(_irq_bx1, _cy + 1, _irq_bx2, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    var _irq_txt = "KEEP IRQ OFF: OFF";
    if (_keep_irq == 1) {
        _irq_txt = "KEEP IRQ OFF: ON";
    }
    draw_text((_irq_bx1 + _irq_bx2) / 2, _cy, _irq_txt);
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 3: WRITE DDR toggle
    var _ddr_bx1 = _lx;
    var _ddr_bx2 = _rx;
    var _ddr_hov = point_in_rectangle(mouse_x, mouse_y, _ddr_bx1, _cy + 4, _ddr_bx2, _cy + 10);
    if (_write_ddr == 1) {
        draw_set_color(_ddr_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(30, 50, 30));
    } else {
        draw_set_color(_ddr_hov ? make_color_rgb(80, 60, 40) : make_color_rgb(50, 40, 25));
    }
    draw_rectangle(_ddr_bx1, _cy + 1, _ddr_bx2, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    var _ddr_txt = "WRITE DDR $00: OFF";
    if (_write_ddr == 1) {
        _ddr_txt = "WRITE DDR $00: ON";
    }
    draw_text((_ddr_bx1 + _ddr_bx2) / 2, _cy, _ddr_txt);
    draw_set_halign(fa_left);
    _cy += _line_h;

    // Row 4: WIKI button
    var _wiki_bx1 = _lx;
    var _wiki_bx2 = _rx;
    var _wiki_hov = point_in_rectangle(mouse_x, mouse_y, _wiki_bx1, _cy + 4, _wiki_bx2, _cy + 10);
    if (_wiki_hov) {
        draw_set_color(make_color_rgb(60, 100, 180));
    } else {
        draw_set_color(make_color_rgb(30, 50, 90));
    }
    draw_rectangle(_wiki_bx1, _cy + 1, _wiki_bx2, _cy + 11, false);
    draw_set_color(c_aqua);
    draw_set_halign(fa_center);
    draw_text((_wiki_bx1 + _wiki_bx2) / 2, _cy, "OPEN WIKI PAGE");
    draw_set_halign(fa_left);
    _cy += _line_h;

}