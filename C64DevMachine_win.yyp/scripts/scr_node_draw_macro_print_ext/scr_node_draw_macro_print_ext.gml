/// @desc scr_node_draw_macro_print_ext(_draw_x, _y)
/// Draws the MACRO_PRINT_EXT node body — numeric value printer.
/// instructions[0]: ["macro_print_ext", sx, sy, col, clr, src_mode,
///                    var_name, reg_id, fmt, align_h, align_v, pad]

function scr_node_draw_macro_print_ext(_draw_x, _y) {

    var _ins      = instructions[0];
    var _sx       = is_real(_ins[1]) ? real(_ins[1]) : 0;
    var _sy       = is_real(_ins[2]) ? real(_ins[2]) : 0;
    var _col      = is_real(_ins[3]) ? real(_ins[3]) : 1;
    var _clr      = is_real(_ins[4]) ? real(_ins[4]) : 0;
    var _src_mode = (array_length(_ins) > 5 && is_real(_ins[5])) ? real(_ins[5]) : 0;
    var _var_name = (array_length(_ins) > 6) ? string(_ins[6]) : "";
    var _reg_id   = (array_length(_ins) > 7 && is_real(_ins[7])) ? real(_ins[7]) : 0;
    var _fmt      = (array_length(_ins) > 8 && is_real(_ins[8])) ? real(_ins[8]) : 0;
    var _pad      = (array_length(_ins) > 11 && is_real(_ins[11])) ? real(_ins[11]) : 0;

    var _row_h = 18;
    var _ry    = _y + 28;

    draw_set_font(fnt_c64_tiny);

    // ── Row 1: X / Y position ──
    // X/Y values turn magenta when alignment overrides them (matches MACRO_PRINT).
    var _ah_r1 = (array_length(_ins) > 9 && is_real(_ins[9])) ? real(_ins[9]) : 0;
    var _av_r1 = (array_length(_ins) > 10 && is_real(_ins[10])) ? real(_ins[10]) : 0;
    var _x_overridden = (_ah_r1 != 0);
    var _y_overridden = (_av_r1 != 0);
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 10, _ry, "X:");
    draw_set_color(_x_overridden ? make_color_rgb(220, 40, 220) : c_yellow);
    draw_text(_draw_x + 28, _ry, ((array_length(instructions[0]) > 12 && instructions[0][12] == 1) ? "VAR" : string(_sx)));
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 70, _ry, "Y:");
    draw_set_color(_y_overridden ? make_color_rgb(220, 40, 220) : c_yellow);
    draw_text(_draw_x + 88, _ry, ((array_length(instructions[0]) > 14 && instructions[0][14] == 1) ? "VAR" : string(_sy)));
    // colour swatch
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 128, _ry, "COL:");
    draw_set_color(c_yellow);
    draw_text(_draw_x + 162, _ry, ((array_length(instructions[0]) > 16 && instructions[0][16] == 1) ? "VAR" : string(_col)));
    _ry += _row_h;

    // ── Row 2: SOURCE toggle ──
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 10, _ry, "SRC:");
    var _src_str = (_src_mode == 1) ? "REGISTER" : "VARIABLE";
    var _sbx1 = _draw_x + 50;
    var _sbx2 = _draw_x + width - 10;
    draw_set_color(make_color_rgb(40, 60, 90));
    draw_rectangle(_sbx1, _ry, _sbx2, _ry + 14, false);
    draw_set_color(c_aqua);
    draw_text(_sbx1 + 6, _ry, _src_str);
    _ry += _row_h;

    // ── Row 3: VAR name (if VAR) or REGISTER picker (if REG) ──
    if (_src_mode == 0) {
        draw_set_color(make_color_rgb(140, 160, 200));
        draw_text(_draw_x + 10, _ry, "VAR:");
        draw_set_color(_var_name != "" ? c_lime : make_color_rgb(90, 90, 90));
        var _vshow = (_var_name != "") ? _var_name : "-pick var-";
        draw_text(_draw_x + 50, _ry, _vshow);
    } else {
        draw_set_color(make_color_rgb(140, 160, 200));
        draw_text(_draw_x + 10, _ry, "REG:");
        var _reg_names = ["A", "X", "Y", "SP", "FLAGS"];
        var _rn = (_reg_id >= 0 && _reg_id < array_length(_reg_names)) ? _reg_names[_reg_id] : "A";
        var _rbx1 = _draw_x + 50;
        var _rbx2 = _draw_x + width - 10;
        draw_set_color(make_color_rgb(60, 40, 90));
        draw_rectangle(_rbx1, _ry, _rbx2, _ry + 14, false);
        draw_set_color(c_yellow);
        draw_text(_rbx1 + 6, _ry, _rn);
    }
    _ry += _row_h;

    // ── Row 4: FORMAT toggle ──
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 10, _ry, "FMT:");
    var _fmt_names = ["DECIMAL", "HEX", "BINARY", "BCD"];
    var _fn = (_fmt >= 0 && _fmt < array_length(_fmt_names)) ? _fmt_names[_fmt] : "HEX";
    var _fbx1 = _draw_x + 50;
    var _fbx2 = _draw_x + width - 10;
    draw_set_color(make_color_rgb(40, 70, 50));
    draw_rectangle(_fbx1, _ry, _fbx2, _ry + 14, false);
    draw_set_color(c_lime);
    draw_text(_fbx1 + 6, _ry, _fn);
    _ry += _row_h;

    // ── Row 4b: H-ALIGN buttons ──
    var _align_h = (array_length(_ins) > 9 && is_real(_ins[9])) ? real(_ins[9]) : 0;
    var _align_v = (array_length(_ins) > 10 && is_real(_ins[10])) ? real(_ins[10]) : 0;
    var _align_h_labels = ["DEF", "LEFT", "CENT", "RGHT"];
    var _align_v_labels = ["DEF", "TOP", "MID", "BOT"];
    var _pe_btn_w = 34;

    draw_set_color(c_ltgray);
    draw_text(_draw_x + 10, _ry, "H:");
    for (var _ai = 0; _ai < 4; _ai++) {
        var _bx  = _draw_x + 30 + (_ai * (_pe_btn_w + 2));
        var _sel = (_align_h == _ai);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _ry, _bx + _pe_btn_w, _ry + 14);
        if (_sel) {
            draw_set_color(make_color_rgb(220, 40, 220));
        } else if (_hov) {
            draw_set_color(make_color_rgb(80, 60, 80));
        } else {
            draw_set_color(make_color_rgb(40, 30, 40));
        }
        draw_rectangle(_bx, _ry + 2, _bx + _pe_btn_w, _ry + 14, false);
        draw_set_color(_sel ? c_white : c_gray);
        draw_set_halign(fa_center);
        draw_text(_bx + _pe_btn_w * 0.5, _ry, _align_h_labels[_ai]);
        draw_set_halign(fa_left);
    }
    _ry += _row_h;

    // ── Row 4c: V-ALIGN buttons ──
    draw_set_color(c_ltgray);
    draw_text(_draw_x + 10, _ry, "V:");
    for (var _ai = 0; _ai < 4; _ai++) {
        var _bx  = _draw_x + 30 + (_ai * (_pe_btn_w + 2));
        var _sel = (_align_v == _ai);
        var _hov = point_in_rectangle(mouse_x, mouse_y, _bx, _ry, _bx + _pe_btn_w, _ry + 14);
        if (_sel) {
            draw_set_color(make_color_rgb(220, 40, 220));
        } else if (_hov) {
            draw_set_color(make_color_rgb(80, 60, 80));
        } else {
            draw_set_color(make_color_rgb(40, 30, 40));
        }
        draw_rectangle(_bx, _ry + 2, _bx + _pe_btn_w, _ry + 14, false);
        draw_set_color(_sel ? c_white : c_gray);
        draw_set_halign(fa_center);
        draw_text(_bx + _pe_btn_w * 0.5, _ry, _align_v_labels[_ai]);
        draw_set_halign(fa_left);
    }
    _ry += _row_h;

    // ── Row 5: PAD toggle + CLEAR toggle ──
    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_draw_x + 10, _ry, "PAD:");
    var _pad_str = (_pad == 1) ? "SPACES" : "ZEROS";
    draw_set_color(c_white);
    draw_text(_draw_x + 42, _ry, _pad_str);

    // CLEAR checkbox
    var _cbx = _draw_x + 112;
    draw_set_color(_clr ? c_lime : make_color_rgb(60, 60, 60));
    draw_rectangle(_cbx-8, _ry+2, _cbx + 4, _ry + 14, false);
    draw_set_color(c_gray);
    draw_rectangle(_cbx-8, _ry+2, _cbx + 4, _ry + 14, true);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_clr ? c_lime : c_gray);
    draw_text(_cbx+8 , _ry , "PRE-CLEAR?");
    draw_set_font(fnt_c64_code);
    _ry += _row_h;
    scr_print_dynamic_draw(_draw_x, _y + height - 56, 12);
}