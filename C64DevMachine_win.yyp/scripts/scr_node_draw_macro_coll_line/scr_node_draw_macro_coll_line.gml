/// @desc Draw body content for MACRO_COLL_LINE node.
/// instructions[0]: [0]="macro_coll_line", [1]=LINE_COLL asset name,
/// [2]=probe X var name, [3]=probe Y var name, [4]=result var name,
/// [5]=optional X offset var, [6]=optional Y offset var.
function scr_node_draw_macro_coll_line(_draw_x, _y) {
    var _hh = 24, _lh = 16, _inst = instructions[0];
    while (array_length(_inst) < 7) array_push(_inst, "");

    var _lx = _draw_x + 8, _rx = _draw_x + width - 6, _cy = _y + _hh + 4;
    var _button = function(_label, _x1, _x2, _yy, _col) {
        var _hov = point_in_rectangle(mouse_x, mouse_y, _x1, _yy + 4, _x2, _yy + 10);
        draw_set_color(_hov ? merge_color(_col, c_white, 0.25) : _col);
        draw_rectangle(_x1, _yy + 1, _x2, _yy + 11, false);
        draw_set_color(c_white); draw_set_halign(fa_center); draw_text((_x1 + _x2) * 0.5, _yy, _label); draw_set_halign(fa_left);
    };

    draw_set_font(fnt_C64_Angled_tiny);

    draw_set_color(c_gray); draw_text(_lx, _cy, "LUT:");
    _button(string(_inst[1]) != "" ? string(_inst[1]) : "<SELECT LINE_COLL>", _lx + 44, _rx, _cy, make_color_rgb(90, 30, 30));
    _cy += _lh;

    draw_set_color(c_gray); draw_text(_lx, _cy, "PX:");
    _button(string(_inst[2]) != "" ? string(_inst[2]) : "<SELECT VAR>", _lx + 44, _rx, _cy, make_color_rgb(25, 65, 60));
    _cy += _lh;

    draw_set_color(c_gray); draw_text(_lx, _cy, "PY:");
    _button(string(_inst[3]) != "" ? string(_inst[3]) : "<SELECT VAR>", _lx + 44, _rx, _cy, make_color_rgb(25, 65, 60));
    _cy += _lh;

    draw_set_color(c_gray); draw_text(_lx, _cy, "OFF X:");
    _button(string(_inst[5]) != "" ? string(_inst[5]) : "<NONE>", _lx + 44, _rx, _cy, make_color_rgb(35, 55, 75));
    _cy += _lh;

    draw_set_color(c_gray); draw_text(_lx, _cy, "OFF Y:");
    _button(string(_inst[6]) != "" ? string(_inst[6]) : "<NONE>", _lx + 44, _rx, _cy, make_color_rgb(35, 55, 75));
    _cy += _lh;

    draw_set_color(c_gray); draw_text(_lx, _cy, "RES:");
    _button(string(_inst[4]) != "" ? string(_inst[4]) : "<SELECT VAR>", _lx + 44, _rx, _cy, make_color_rgb(65, 55, 25));
    _cy += _lh;
}
