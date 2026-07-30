function scr_node_step_macro_flip_x(_draw_x) {
// Migrate old 2-element instructions array
    if (array_length(instructions[0]) < 2) instructions[0][1] = 0x2800;
    if (array_length(instructions[0]) < 3) instructions[0][2] = 1;
    // FROM address
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 54, y + 26, _draw_x + 90, y + 44)) {
        var _cur = real(instructions[0][1]);
        var _h   = decimal_to_hex(_cur);
        while (string_length(_h) < 4) _h = "0" + _h;
        var _cur_str = "$" + string_upper(_h);
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            current_input_string = _cur_str;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // COUNT
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 62, y + 43, _draw_x + 82, y + 58)) {
        if (array_length(instructions[0]) < 3) {
            instructions[0][2] = 1;
        }
        var _count_str = string(instructions[0][2]);
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            current_input_string = _count_str;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    
    }

    exit;
}