function scr_node_step_macro_scroll() {
    // Auto-clear USE SID IRQ if no SID node present
    var _sid_check = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_SID") { _sid_check = true; break; }
    }
if (!_sid_check && array_length(instructions[0]) > 4 && instructions[0][4] == 1) {
        instructions[0][4] = 0;
        scr_c64_update_addresses();
    }
    // Row count is no longer capped by SID presence — with the IRQ split,
    // SID enables a steady HUD rather than limiting scroll rows. Only the
    // physical screen height (25) bounds it; clamping happens on entry below.
    if (!mouse_check_button_pressed(mb_left)) return;
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _mgx      = device_mouse_x_to_gui(0);
    var _mgy      = device_mouse_y_to_gui(0);
    // GUI-space row positions — must mirror _ly sequence in draw function exactly.
    // Draw starts at _ly = _y + 24 + 4, increments by _lh = 18 per row.
    var _px  = x + 8;
    var _ly0 = y + 24 + 4;  // ROW 0: START ROW
    var _lh  = 18;
    var _x1_g = (_px           - _cam_x) / _cam_zoom;
    var _x2_g = (_px + width - 16 - _cam_x) / _cam_zoom;
    var _lh_g = _lh / _cam_zoom;
var _ry = [
        (_ly0           - _cam_y) / _cam_zoom,  // row 0: START ROW
        (_ly0 + _lh     - _cam_y) / _cam_zoom,  // row 1: ROW COUNT
        (_ly0 + _lh * 2 - _cam_y) / _cam_zoom,  // row 2: COLOUR MODE
        (_ly0 + _lh * 3 - _cam_y) / _cam_zoom,  // row 3: SPEED
        (_ly0 + _lh * 4 - _cam_y) / _cam_zoom,  // row 4: DIRECTION
        (_ly0 + _lh * 5 - _cam_y) / _cam_zoom,  // row 5: USE SID IRQ
    ];
    var _in_col = (_mgx >= _x1_g && _mgx <= _x2_g);
    // ROW 0 — START ROW: open text entry for index [1]
    if (_in_col && _mgy >= _ry[0] && _mgy < _ry[0] + _lh_g) {
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 1;
        obj_workspace_manager.current_input_string = string(is_real(instructions[0][1]) ? real(instructions[0][1]) : 4);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
// ROW 1 — ROW COUNT: open text entry for index [2]
    if (_in_col && _mgy >= _ry[1] && _mgy < _ry[1] + _lh_g) {

        var _max_rows_step = 25;
        var _cur_rows = is_real(instructions[0][2]) ? real(instructions[0][2]) : 16;
        instructions[0][2] = clamp(_cur_rows, 1, _max_rows_step);
        obj_workspace_manager.input_target_node    = id;
        obj_workspace_manager.input_target_index   = 2;
        obj_workspace_manager.current_input_string = string(instructions[0][2]);
        obj_workspace_manager.cursor_pos           = string_length(obj_workspace_manager.current_input_string);
        obj_workspace_manager.is_entering_text     = true;
        return;
    }
    // ROW 2 — COLOUR MODE: cycle 0→1→2→0 (index [3])
    if (_in_col && _mgy >= _ry[2] && _mgy < _ry[2] + _lh_g) {
        var _cur = (array_length(instructions[0]) > 3 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 1;
        instructions[0][3] = (_cur + 1) mod 3;
        scr_c64_update_addresses();
        return;
    }
}