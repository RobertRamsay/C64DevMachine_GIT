/// @desc Step click handler for MOVE_MEM
function scr_node_step_macro_move_mem(_draw_x) {
    var _header_h = 24;
    var _line_h   = 14;
    var _fy       = y + _header_h + 4;

    // Row 1: FROM start ($src_s) hit zone
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 44, _fy, _draw_x + 96, _fy + 12)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            var _raw = real(other.instructions[0][1]);
            var _h   = string_upper(decimal_to_hex(_raw));
            while (string_length(_h) < 4) _h = "0" + _h;
            current_input_string = _h;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    // Row 1: FROM end ($src_e) hit zone
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 114, _fy, _draw_x + 166, _fy + 12)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            var _raw = real(other.instructions[0][2]);
            var _h   = string_upper(decimal_to_hex(_raw));
            while (string_length(_h) < 4) _h = "0" + _h;
            current_input_string = _h;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _fy += _line_h;

    // Row 2: TO ($dst) hit zone
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 44, _fy, _draw_x + 96, _fy + 12)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 3;
            var _raw = real(other.instructions[0][3]);
            var _h   = string_upper(decimal_to_hex(_raw));
            while (string_length(_h) < 4) _h = "0" + _h;
            current_input_string = _h;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}