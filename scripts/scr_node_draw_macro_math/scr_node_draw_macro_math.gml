/// @desc scr_node_draw_macro_math(_draw_x, _y)
/// instructions[0]: ["macro_math", 1 op, 2 in_var, 3 operand_mode,
///   4 operand_lit(signed), 5 operand_var, 6 result_var]
/// op: 0=ADD 1=SUB 2=MUL 3=DIV 4=ONEMINUS(1-X) 5=INVSIGN(-X)

function scr_node_draw_macro_math(_draw_x, _y) {

    var _ins = instructions[0];

    var _op       = (array_length(_ins) > 1 && is_real(_ins[1])) ? real(_ins[1]) : 0;
    var _in_var   = (array_length(_ins) > 2) ? string(_ins[2]) : "";
    var _op_mode  = (array_length(_ins) > 3 && is_real(_ins[3])) ? real(_ins[3]) : 0;
    var _op_lit   = (array_length(_ins) > 4 && is_real(_ins[4])) ? real(_ins[4]) : 0;
    var _op_var   = (array_length(_ins) > 5) ? string(_ins[5]) : "";
    var _res_var  = (array_length(_ins) > 6) ? string(_ins[6]) : "";

    var _two_input = (_op <= 3);

    var _lh    = 14;
    var _ly    = _y + 28;
    var _c_lbl = make_color_rgb(140, 160, 200);
    var _c_dim = make_color_rgb(100, 100, 100);
    var _vbtn_w = 28;

    draw_set_font(fnt_c64_tiny);

    // ── Row 1: OP selector ──
    var _op_names = ["ADD", "SUB", "MUL", "DIV", "1-X", "-X"];
    var _op_lbl   = _op_names[_op];

    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "OP:");
    var _obx1 = _draw_x + 52;
    var _obx2 = _draw_x + width - 10;
    draw_set_color(make_color_rgb(30, 70, 55));
    draw_rectangle(_obx1, _ly + 1, _obx2, _ly + 13, false);
    draw_set_color(c_lime);
    draw_text(_obx1 + 6, _ly, _op_lbl);
    _ly += _lh;

    // ── Row 2: IN (VAR1) ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "IN:");
    if (_in_var != "") {
        draw_set_color(c_yellow);
        draw_text(_draw_x + 52, _ly, _in_var);
    } else {
        draw_set_color(_c_dim);
        draw_text(_draw_x + 52, _ly, "-pick var-");
    }
    _ly += _lh;

    // ── Row 3: OPERAND (VAR2 / literal) — two-input ops only ──
    if (_two_input) {
        draw_set_color(_c_lbl);
        var _by_lbl = (_op <= 1) ? "WITH:" : "BY:";
        draw_text(_draw_x + 10, _ly, _by_lbl);
        // LIT/VAR toggle on the right
        var _tvx = _draw_x + width - 38;
        if (_op_mode == 1) {
            draw_set_color(make_color_rgb(180, 140, 30));
        } else {
            draw_set_color(make_color_rgb(50, 50, 60));
        }
        draw_rectangle(_tvx, _ly + 1, _tvx + _vbtn_w, _ly + 12, false);
        if (_op_mode == 1) {
            draw_set_color(c_yellow);
        } else {
            draw_set_color(make_color_rgb(140, 140, 160));
        }
        draw_set_halign(fa_center);
        draw_text(_tvx + (_vbtn_w * 0.5), _ly, "VAR");
        draw_set_halign(fa_left);
        // value / var name
        if (_op_mode == 1) {
            if (_op_var != "") {
                draw_set_color(c_yellow);
                draw_text(_draw_x + 52, _ly, _op_var);
            } else {
                draw_set_color(_c_dim);
                draw_text(_draw_x + 52, _ly, "-pick var-");
            }
        } else {
            draw_set_color(c_aqua);
            draw_text(_draw_x + 52, _ly, string(_op_lit));
        }
    } else {
        draw_set_color(make_color_rgb(60, 60, 70));
        draw_text(_draw_x + 10, _ly, "BY: -");
    }
    _ly += _lh;

    // ── Row 4: OUT (VAR3) ──
    draw_set_color(_c_lbl);
    draw_text(_draw_x + 10, _ly, "OUT:");
    if (_res_var != "") {
        draw_set_color(c_lime);
        draw_text(_draw_x + 52, _ly, _res_var);
    } else {
        draw_set_color(c_orange);
        draw_text(_draw_x + 52, _ly, "< NONE >");
    }
    _ly += _lh;

    // ── Footer: width / signed-overflow warnings ──
    // Widths from each var's own meta (byte=1, word=2). Literal fits a
    // signed byte if in -128..127, else counts as 2 bytes.
    var _iw = 1;
    var _m_in = scr_nloc_find_meta(_in_var);
    if (_m_in != undefined) _iw = _m_in.size;

    var _rw = 1;
    var _m_rs = scr_nloc_find_meta(_res_var);
    if (_m_rs != undefined) _rw = _m_rs.size;

    var _ow = 1;
    if (_op_mode == 1) {
        var _m_op = scr_nloc_find_meta(_op_var);
        if (_m_op != undefined) _ow = _m_op.size;
    } else {
        if (_op_lit < -128 || _op_lit > 127) _ow = 2; else _ow = 1;
    }

    var _warn_trunc = "";
    var _warn_over  = "";
    var _nat = _iw;
    switch (_op) {
        case 0: case 1: // ADD / SUB
            _nat = max(_iw, _ow);
            if (_rw < _nat) { _warn_trunc = "TRUNCATES TO OUT WIDTH"; }
            else if (_rw == _nat) { _warn_over = "MAY OVERFLOW SIGNED"; }
            break;
        case 2: // MUL
            _nat = _iw + _ow;
            if (_rw < _nat) { _warn_trunc = "WORD RESULT -> BYTE VAR"; }
            break;
        case 3: // DIV
            _nat = _iw;
            if (_rw < _nat) { _warn_trunc = "TRUNCATES TO OUT WIDTH"; }
            break;
        case 4: case 5: // ONEMINUS / INVSIGN
            _nat = _iw;
            if (_rw < _nat) { _warn_trunc = "TRUNCATES TO OUT WIDTH"; }
            else if (_rw == _nat) { _warn_over = "MAY OVERFLOW SIGNED"; }
            break;
    }

    draw_set_font(fnt_c64_pico);
    if (_warn_trunc != "") {
        draw_set_color(make_color_rgb(230, 80, 80));
        draw_text(_draw_x + 8, _ly, "!! " + _warn_trunc);
    } else if (_warn_over != "") {
        draw_set_color(make_color_rgb(220, 170, 60));
        draw_text(_draw_x + 8, _ly, "! " + _warn_over);
    } else {
        draw_set_color(make_color_rgb(80, 120, 180));
        draw_text(_draw_x + 8, _ly, "SIGNED  IN " + string(_iw) + "B -> OUT " + string(_rw) + "B");
    }
}