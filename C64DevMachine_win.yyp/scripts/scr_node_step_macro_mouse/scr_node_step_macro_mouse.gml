/// @function scr_node_step_macro_mouse(_draw_x)
/// @desc Hit testing for the MACRO_MOUSE body. Row offsets mirror
///       scr_node_draw_macro_mouse exactly — the two must be edited together.
function scr_node_step_macro_mouse(_draw_x) {
    var _hdr_h  = 24;
    var _line_h = 12;
    var _fy     = y + _hdr_h + 4;

    // ---- PORT 1 / PORT 2 ----
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 55, _fy, _draw_x + 75, _fy + 16)) {
        instructions[0][1] = 1;
        global.undo_dirty  = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 75, _fy, _draw_x + 95, _fy + 16)) {
        instructions[0][1] = 2;
        global.undo_dirty  = true;
        exit;
    }

    // ---- ZP BASE ----
    _fy += _line_h + 2;
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 55, _fy, _draw_x + width, _fy + 16)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 100;
            current_input_string = "$" + string_upper(decimal_to_hex(other.instructions[0][2]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // ---- Y AXIS SENSE ----
    _fy += _line_h + 2;
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 55, _fy, _draw_x + width, _fy + 16)) {
        if (real(instructions[0][3]) == 1) {
            instructions[0][3] = 0;
        } else {
            instructions[0][3] = 1;
        }
        global.undo_dirty = true;
        scr_undo_snapshot();
        exit;
    }

    // ---- CALL GRID ----
    // Skips the address readout row, which is not interactive.
    _fy += (_line_h + 2) + (_line_h + 6);

    var _grid_idx = [
        [1, 2],
        [3, 4, 5, 6]
    ];
    var _col_w = (width - 4) / 5;

    for (var _r = 0; _r < array_length(_grid_idx); _r++) {
        var _row_data = _grid_idx[_r];
        for (var _c = 0; _c < array_length(_row_data); _c++) {
            var _ins_idx = _row_data[_c];
            if (_ins_idx >= array_length(instructions)) {
                continue;
            }

            var _x1 = _draw_x + 8 + (_c * _col_w);
            if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x1 + _col_w - 4, _fy + _line_h + 2)) {
                var _was_enabled = (real(instructions[_ins_idx][2]) == 1);
                if (_was_enabled) {
                    instructions[_ins_idx][2] = 0;
                } else {
                    instructions[_ins_idx][2] = 1;

                    // Same courtesy as MACRO_JOY: turning a call on with nothing
                    // to call is a dead end, so drop a LABEL node beside the
                    // macro unless one already answers to that name.
                    var _call_name   = string(instructions[_ins_idx][1]);
                    var _label_exists = false;
                    with (obj_c64_node) {
                        if (node_type == "LABEL" && string(instructions[0][1]) == _call_name) {
                            _label_exists = true;
                            break;
                        }
                    }

                    if (!_label_exists) {
                        var _spawn_x = round((x + 220) / 20) * 20;
                        var _spawn_y = round((y + ((_ins_idx - 1) * 40)) / 20) * 20;

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
                scr_undo_snapshot();
                exit;
            }
        }
        _fy += _line_h + 2;
    }
}
