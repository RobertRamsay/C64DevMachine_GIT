/// @desc Handle LMB clicks for MACRO_COLL_LINE node fields.
function scr_node_step_macro_coll_line(_draw_x) {
    var _hh = 24, _lh = 16, _inst = instructions[0], _lx = _draw_x + 8, _rx = _draw_x + width - 6, _cy = y + _hh + 4;
    while (array_length(_inst) < 5) array_push(_inst, "");
    var _hit = function(_x1, _x2, _yy) { return point_in_rectangle(mouse_x, mouse_y, _x1, _yy + 4, _x2, _yy + 10); };

    // LUT (LINE_COLL asset picker)
    if (_hit(_lx + 44, _rx, _cy)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "LINE_ASSET";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 1;
        exit;
    }
    _cy += _lh;

    // PX (probe X var)
    if (_hit(_lx + 44, _rx, _cy)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_word_only  = false;
        label_picker_byte_only  = false;
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 2;
        exit;
    }
    _cy += _lh;

    // PY (probe Y var)
    if (_hit(_lx + 44, _rx, _cy)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_word_only  = false;
        label_picker_byte_only  = false;
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 3;
        exit;
    }
    _cy += _lh;

    // RES (result var)
    if (_hit(_lx + 44, _rx, _cy)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_word_only  = false;
        label_picker_byte_only  = false;
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 4;
        exit;
    }
    _cy += _lh;
}
