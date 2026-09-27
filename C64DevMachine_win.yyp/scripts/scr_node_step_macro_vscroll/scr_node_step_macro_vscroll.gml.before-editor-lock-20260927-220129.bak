/// @desc Step MACRO_VSCROLL node
function scr_node_step_macro_vscroll() {

    if (!mouse_check_button_pressed(mb_left)) return;

    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);

    var _px  = x + 8;
    var _ly0 = y + 24 + 4;
    var _lh  = 18;

    var _x1_g = (_px           - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16 - _cam_x) / _cam_zoom;
    var _lh_g = _lh / _cam_zoom;

    var _ry0 = (_ly0           - _cam_y) / _cam_zoom;   // row 0: START COL
    var _ry1 = (_ly0 + _lh     - _cam_y) / _cam_zoom;   // row 1: COL COUNT
    var _ry2 = (_ly0 + _lh * 2 - _cam_y) / _cam_zoom;   // row 2: COLOUR MODE

    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);

    // ROW 0 — START COL
    if (_in_col && _mgy >= _ry0 && _mgy < _ry0 + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][1]) ? real(instructions[0][1]) : 0);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

    // ROW 1 — COL COUNT
    if (_in_col && _mgy >= _ry1 && _mgy < _ry1 + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 2;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][2]) ? real(instructions[0][2]) : 40);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }

}