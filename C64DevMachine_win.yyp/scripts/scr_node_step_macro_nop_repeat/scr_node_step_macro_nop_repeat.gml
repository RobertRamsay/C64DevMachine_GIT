/// @desc scr_node_step_macro_nop_repeat(_draw_x)
/// Click handling for the NOP REPEAT node — opens decimal text entry
/// on the count box. Geometry must match scr_node_draw_macro_nop_repeat.
function scr_node_step_macro_nop_repeat(_draw_x) {
    while (array_length(instructions[0]) < 2) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][1])) {
        instructions[0][1] = 0;
    }

    var _header_h = 20;
    var _row_y    = y + _header_h + 12;
    var _val_h    = 18;
    var _val_x1   = _draw_x + 70;
    var _val_x2   = _draw_x + 160;

    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _row_y, _val_x2, _row_y + _val_h)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            current_input_string = string(other.instructions[0][1]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}
