/// @function scr_node_step_macro_keys(_draw_x)
/// @desc Hit testing for the keyboard grid. Offsets mirror
///       scr_node_draw_macro_keys — edit the two together.
function scr_node_step_macro_keys(_draw_x) {
    var _hdr_h  = 24;
    var _line_h = 12;
    var _fy     = y + _hdr_h + 4;

    var _cat  = scr_key_category_list(node_type);
    var _cols = _cat.cols;

    // ---- ZP BASE ----
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 40, _fy, _draw_x + width, _fy + 14)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 100;
            current_input_string = "$" + string_upper(decimal_to_hex(other.instructions[0][1]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // ---- KEY GRID ----
    _fy += _line_h + 6;
    var _col_w = (width - 8) / _cols;

    for (var _si = 1; _si < array_length(instructions); _si++) {
        var _idx = _si - 1;
        var _c   = _idx mod _cols;
        var _r   = _idx div _cols;

        var _x1 = _draw_x + 4 + (_c * _col_w);
        var _y1 = _fy + (_r * (_line_h + 2));

        if (point_in_rectangle(mouse_x, mouse_y, _x1, _y1, _x1 + _col_w - 2, _y1 + _line_h + 2)) {
            var _was_enabled = (real(instructions[_si][2]) == 1);
            if (_was_enabled) {
                instructions[_si][2] = 0;
            } else {
                instructions[_si][2] = 1;

                // Same courtesy as MACRO_JOY: enabling a call with nothing to
                // call is a dead end, so drop a LABEL node unless one already
                // answers to that name.
                var _call_name    = string(instructions[_si][1]);
                var _label_exists = false;
                with (obj_c64_node) {
                    if (node_type == "LABEL" && string(instructions[0][1]) == _call_name) {
                        _label_exists = true;
                        break;
                    }
                }

                if (!_label_exists) {
                    var _spawn_x = round((x + 220) / 20) * 20;
                    var _spawn_y = round(y / 20) * 20;

                    var _spawn_clear    = false;
                    var _spawn_attempts = 0;
                    while (!_spawn_clear && _spawn_attempts < 64) {
                        _spawn_clear = true;
                        with (obj_c64_node) {
                            if (is_connected || org_parent != noone) { continue; }
                            if (is_dragging) { continue; }
                            if (x == _spawn_x && y == _spawn_y) {
                                _spawn_clear = false;
                                _spawn_y += ceil(height / 20) * 20;
                                break;
                            }
                        }
                        _spawn_attempts++;
                    }

                    var _new_label = scr_node_spawn("LABEL", _spawn_x, _spawn_y);
                    _new_label.instructions[0][1] = _call_name;
                }
            }

            height_dirty = true;
            global.undo_dirty = true;
            scr_undo_snapshot();
            exit;
        }
    }
}
