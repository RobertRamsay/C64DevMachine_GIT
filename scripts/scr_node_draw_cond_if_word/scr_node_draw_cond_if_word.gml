/// @desc Draw body content for COND_IF_WORD node
/// Mirrors scr_node_draw_cond_if, but the literal field is 16-bit
/// (4 hex digits) and the VAR pickers only offer word-encoded vars.
function scr_node_draw_cond_if_word(_draw_x, _y) {

    var _header_h   = 24;
    var _line_h     = 16;
    var _inst       = instructions[0];
    var _var        = string(_inst[1]);
    var _cval       = real(_inst[2]);
    var _target     = string(_inst[3]);
    var _mode       = string(_inst[4]);

    var _lx = _draw_x + 8;
    var _rx = _draw_x + width - 6;
    var _cy = _y + _header_h + 4;

    // ── Row 0: VAR ────────────────────────────────────────────────
    draw_set_font(fnt_C64_Angled_tiny);
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "VAR:");

    var _var_bx1 = _lx + 48;
    var _var_bx2 = _rx;
    var _var_hov = point_in_rectangle(mouse_x, mouse_y, _var_bx1, _cy + 4, _var_bx2, _cy + 10);
    draw_set_color(_var_hov ? make_color_rgb(60, 100, 180) : make_color_rgb(34, 44, 64));
    draw_rectangle(_var_bx1, _cy + 1, _var_bx2, _cy + 11, false);
    draw_set_color(_var == "" ? make_color_rgb(160, 80, 80) : c_white);
    draw_set_halign(fa_center);
    draw_text((_var_bx1 + _var_bx2) / 2, _cy, _var == "" ? "< SELECT >" : scr_nloc_display_name(_var));
    draw_set_halign(fa_left);
    _cy += _line_h;

    // ── Row 1: mode toggle + CMP value / CMP VAR ──────────────────
    var _op_label = "==";
    switch (_mode) {
        case "eq":  _op_label = "=="; break;
        case "ne":  _op_label = "!="; break;
        case "lt":  _op_label = " <"; break;
        case "gte": _op_label = ">="; break;
        case "gt":  _op_label = " >"; break;
        case "lte": _op_label = "<="; break;
    }
    var _op_bx1      = _lx;
    var _op_bx2      = _lx + 44;
    var _op_hov      = point_in_rectangle(mouse_x, mouse_y, _op_bx1, _cy + 4, _op_bx2, _cy + 10);
    var _op_col_base = make_color_rgb(30, 90, 30);
    switch (_mode) {
        case "eq":  _op_col_base = make_color_rgb(30,  90,  30); break;
        case "ne":  _op_col_base = make_color_rgb(100, 30,  30); break;
        case "lt":  _op_col_base = make_color_rgb(30,  60, 100); break;
        case "gte": _op_col_base = make_color_rgb(80,  50,  10); break;
        case "gt":  _op_col_base = make_color_rgb(10,  70,  80); break;
        case "lte": _op_col_base = make_color_rgb(70,  20,  80); break;
    }
    draw_set_color(_op_hov ? make_color_rgb(220, 180, 60) : _op_col_base);
    draw_rectangle(_op_bx1+5, _cy + 1, _op_bx2-5, _cy + 11, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text((_op_bx1 + _op_bx2) / 2, _cy, _op_label);
    draw_set_halign(fa_left);

    var _cmp_var     = (array_length(_inst) > 5) ? string(_inst[5]) : "";
    var _has_cmp_var = (_cmp_var != "" && _cmp_var != "0");
    var _mid_x       = _op_bx2 + 4 + ((_rx - (_op_bx2 + 4)) / 2) - 2;

    // Left: 16-bit literal value box (only when no cmp var set)
    var _cval_bx1 = _op_bx2 + 4;
    var _cval_bx2 = _mid_x;
    var _cval_hov = false;
    if (!_has_cmp_var) {
        _cval_hov = point_in_rectangle(mouse_x, mouse_y, _cval_bx1, _cy + 4, _cval_bx2, _cy + 10);
        if (_cval_hov) {
            draw_set_color(make_color_rgb(60, 80, 140));
        } else {
            draw_set_color(make_color_rgb(34, 44, 64));
        }
        draw_rectangle(_cval_bx1, _cy + 1, _cval_bx2, _cy + 11, false);
        var _cv_display = "";
        if (global.use_hex_display) {
            var _cv_hex = decimal_to_hex(_cval);
            while (string_length(_cv_hex) < 4) _cv_hex = "0" + _cv_hex;
            _cv_display = "$" + string_upper(_cv_hex);
        } else {
            _cv_display = string(_cval);
        }
        draw_set_color(c_yellow);
        draw_set_halign(fa_center);
        draw_text((_cval_bx1 + _cval_bx2) / 2, _cy, _cv_display);
        draw_set_halign(fa_left);
    }

    // Right: CMP VAR picker button — full width when a var is set
    var _cvar_bx1 = _mid_x + 2;
    if (_has_cmp_var) {
        _cvar_bx1 = _op_bx2 + 4;
    }
    var _cvar_bx2 = _rx;
    var _cvar_hov = point_in_rectangle(mouse_x, mouse_y, _cvar_bx1, _cy + 4, _cvar_bx2, _cy + 10);
    if (_cvar_hov) {
        draw_set_color(make_color_rgb(60, 100, 180));
    } else {
        if (_has_cmp_var) {
            draw_set_color(make_color_rgb(30, 50, 90));
        } else {
            draw_set_color(make_color_rgb(34, 44, 64));
        }
    }
    draw_rectangle(_cvar_bx1, _cy + 1, _cvar_bx2, _cy + 11, false);
    if (_has_cmp_var) {
        draw_set_color(c_aqua);
    } else {
        draw_set_color(make_color_rgb(100, 100, 140));
    }
    draw_set_halign(fa_center);
    if (string_upper(_cmp_var) != "0") {
        draw_text((_cvar_bx1 + _cvar_bx2) / 2, _cy, scr_nloc_display_name(_cmp_var));
    }
    if (!_has_cmp_var) {
        draw_set_halign(fa_center);
        draw_text((_cvar_bx1 + _cvar_bx2) / 2, _cy, "< WORD >");
    }
    draw_set_halign(fa_left);
    _cy += _line_h;

    // ── Row 2: GOTO label ─────────────────────────────────────────
    draw_set_color(c_gray);
    draw_text(_lx, _cy, "GOTO:");
    var _tgt_bx1 = _lx + 48;
    var _tgt_bx2 = _rx;
    var _tgt_hov = point_in_rectangle(mouse_x, mouse_y, _tgt_bx1, _cy + 4, _tgt_bx2, _cy + 10);
    draw_set_color(_tgt_hov ? make_color_rgb(50, 80, 50) : make_color_rgb(34, 44, 64));
    draw_rectangle(_tgt_bx1, _cy + 1, _tgt_bx2, _cy + 11, false);
    draw_set_color(make_color_rgb(80, 220, 80));
    draw_set_halign(fa_center);
    var _tgt_display = string(instructions[0][3]);
    draw_set_font(fnt_C64_Angled_tiny);
    draw_text((_tgt_bx1 + _tgt_bx2) / 2, _cy,
              (_tgt_display == "") ? "< LABEL >" : (_tgt_display));
    draw_set_halign(fa_left);
    _cy += _line_h;

}