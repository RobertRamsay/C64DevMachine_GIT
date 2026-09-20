/// @desc Draw body for MACRO_UCI_REU.
/// instructions[0]: ["macro_uci_reu", manifest_name, filename_override, status_var]
///   1 = LOAD_REU asset this node loads. The filename follows it.
///   2 = filename override. Empty means "use the manifest's reu_filename",
///       which is what stops the two drifting apart after a rename.
///   3 = optional BYTE var receiving the first status byte, so the program
///       can tell "00,OK" from "85,REU FILE CANNOT BE OPENED".
function scr_node_draw_macro_uci_reu(_draw_x, _y) {
    var _hh = 24, _lh = 16, _inst = instructions[0];
    while (array_length(_inst) < 4) {
        array_push(_inst, "");
    }

    var _lx = _draw_x + 8, _rx = _draw_x + width - 6, _cy = _y + _hh + 4;

    var _button = function(_label, _x1, _x2, _yy, _col) {
        var _hov = point_in_rectangle(mouse_x, mouse_y, _x1, _yy + 4, _x2, _yy + 10);
        if (_hov) {
            draw_set_color(merge_color(_col, c_white, 0.25));
        } else {
            draw_set_color(_col);
        }
        draw_rectangle(_x1, _yy + 1, _x2, _yy + 11, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_l((_x1 + _x2) * 0.5, _yy, _label);
        draw_set_halign(fa_left);
    };

    draw_set_font_l(fnt_C64_Angled_tiny);

    // ---- REU manifest ----
    draw_set_color(c_gray);
    draw_text_l(_lx, _cy, "REU:");
    var _mf = string(_inst[1]);
    if (_mf == "") {
        _mf = L("<SELECT LOAD_REU>");
    }
    _button(_mf, _lx + 48, _rx, _cy, make_color_rgb(25, 65, 60));
    _cy += _lh;

    // ---- filename ----
    // Derived names are drawn dimmer than an override, so it is obvious at a
    // glance whether this node is following the manifest or has been pinned.
    draw_set_color(c_gray);
    draw_text_l(_lx, _cy, "FILE:");
    var _file      = string(_inst[2]);
    var _file_col  = make_color_rgb(40, 60, 90);
    if (_file == "") {
        _file_col = make_color_rgb(30, 42, 58);
        var _manifest = scr_reu_find_asset(string(_inst[1]));
        if (!is_undefined(_manifest) && variable_struct_exists(_manifest, "reu_filename")) {
            _file = string(_manifest.reu_filename);
        }
    }
    if (_file == "") {
        _file = L("<NO FILE>");
        _file_col = make_color_rgb(90, 30, 30);
    }
    _button(_file, _lx + 48, _rx, _cy, _file_col);
    _cy += _lh;

    // ---- status var ----
    draw_set_color(c_gray);
    draw_text_l(_lx, _cy, "STAT:");
    var _sv = string(_inst[3]);
    if (_sv == "") {
        _sv = L("<NONE>");
    }
    _button(_sv, _lx + 48, _rx, _cy, make_color_rgb(34, 44, 64));
    _cy += _lh;

    // ---- target note ----
    // Worth saying on the node itself: this does nothing under emulation, and
    // someone reading the graph should not expect it to.
    draw_set_color(make_color_rgb(120, 120, 130));
    draw_text_l(_lx, _cy, L("ULTIMATE ONLY - IGNORED IN VICE"));
}
