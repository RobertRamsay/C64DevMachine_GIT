function scr_node_step_macro_irq() {
    if (!mouse_check_button_pressed(mb_left)) return;
    if (label_picker_open) return;

    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);
    var _px  = x + 8;
    var _ly0 = y + 24 + 4;
    var _lh  = 18;
    var _x1_g = (_px            - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16 - _cam_x) / _cam_zoom;
    var _lh_g = _lh / _cam_zoom;

    var _ry = [
        (_ly0            - _cam_y) / _cam_zoom,  // row 0: RASTER LINE
        (_ly0 + _lh      - _cam_y) / _cam_zoom,  // row 1: REQ note (read-only)
        (_ly0 + _lh * 2  - _cam_y) / _cam_zoom,  // row 2: CALL label picker
    ];
    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);

    // RASTER Text Input
    if (_in_col && _mgy >= _ry[0] && _mgy < _ry[0] + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][1]) ? real(instructions[0][1]) : 0x60);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

    // ROW 1 — read-only, no action

    // ROW 2 — CALL LABEL picker (click the JSR value text)
    var _pick_x_g = (_px + 52 - _cam_x) / _cam_zoom;
    var _pick_y_g = (_ly0 + _lh * 2 - _cam_y) / _cam_zoom;
    var _pick_w_g = (width - 60) / _cam_zoom;
    var _pick_h_g = _lh_g;
    if (_mgx >= _pick_x_g && _mgx <= _pick_x_g + _pick_w_g &&
        _mgy >= _pick_y_g && _mgy <= _pick_y_g + _pick_h_g) {
        label_picker_open   = true;
    global.any_picker_open = true;
    label_picker_prev_depth = depth;
    depth = -9999;
        label_picker_index     = 5;
        label_picker_scroll    = 0;
        label_picker_list      = ["[clear]"];
    label_picker_mode      = "JUMP";
        with (obj_c64_node) {
            if (node_type == "LABEL") {
                array_push(other.label_picker_list,
                    string_replace_all(string(instructions[0][1]), " ", "_"));
            }
        }
        return;
    }
}