function scr_qmenu_layout(_index, _cx, _cy) {
    var _btn_w = 100;
    var _btn_h = 24;

    var _row_y   = [-50, -50, 0, 0, 50, 50];
    var _narrow_x = 60;
    var _wide_x   = 110;
    var _col_x   = [-_narrow_x, _narrow_x, -_wide_x, _wide_x, -_narrow_x, _narrow_x];

    var _cx2 = _cx + _col_x[_index];
    var _cy2 = _cy + _row_y[_index];

    return [_cx2 - (_btn_w / 2), _cy2 - (_btn_h / 2), _cx2 + (_btn_w / 2), _cy2 + (_btn_h / 2)];
}