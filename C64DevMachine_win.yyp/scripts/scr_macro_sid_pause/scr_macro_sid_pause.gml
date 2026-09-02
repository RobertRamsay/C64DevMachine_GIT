/// @desc Draw and click handling for MACRO_SID_PAUSE.
/// instructions[0]: ["macro_sid_pause", 1 state]   0 = PAUSE, 1 = RESUME

function scr_node_draw_macro_sid_pause(_draw_x, _y) {
    var _ins = instructions[0];

    var _state = 0;
    if (array_length(_ins) > 1 && is_real(_ins[1])) { _state = real(_ins[1]); }

    var _lh = 14;
    var _ly = _y + 28;
    var _px = _draw_x + 8;

    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_left);

    draw_set_color(make_color_rgb(140, 160, 200));
    draw_text(_px, _ly, "STATE:");
    if (_state == 1) {
        draw_set_color(make_color_rgb(120, 230, 140));
        draw_text(_px + 62, _ly, "RESUME");
    } else {
        draw_set_color(make_color_rgb(240, 170, 90));
        draw_text(_px + 62, _ly, "PAUSE");
    }
    _ly += _lh;

    draw_set_color(make_color_rgb(90, 90, 100));
    if (_state == 1) {
        draw_text(_px, _ly, "MUSIC TICK RESUMES");
    } else {
        draw_text(_px, _ly, "SID FREE - IRQ STILL RUNS");
    }
    _ly += _lh;

    // Without a tune there is no play call to guard, so this node would
    // compile to a flag nothing ever reads.
    var _has_sid = false;
    with (obj_c64_node) {
        if (!is_connected) { continue; }
        if (node_type == "MACRO_SID" || node_type == "MACRO_IRQ_HANDLER" || node_type == "MACRO_IRQ") {
            _has_sid = true;
            break;
        }
    }
    if (!_has_sid) {
        draw_set_color(make_color_rgb(220, 110, 90));
        draw_text(_px, _ly, "NO SID / IRQ NODE TO PAUSE");
    }
}

function scr_node_step_macro_sid_pause(_draw_x) {
    var _fy = y + 28;
    var _x1 = _draw_x + 8;
    var _x2 = _draw_x + width - 8;

    if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
        while (array_length(instructions[0]) <= 1) {
            array_push(instructions[0], 0);
        }
        var _s = 0;
        if (is_real(instructions[0][1])) { _s = real(instructions[0][1]); }
        if (_s == 1) {
            instructions[0][1] = 0;
        } else {
            instructions[0][1] = 1;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
}
