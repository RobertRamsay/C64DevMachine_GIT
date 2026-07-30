/// @desc scr_node_step_macro_track(draw_x)
function scr_node_step_macro_track(_draw_x) {
    var _header_h   = 24;
    var _line_h   = 12;
    var _tly      = y + _header_h + 4;
    var _val_y    = _tly + _line_h;

    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _val_y, _draw_x + width - 8, _val_y + _line_h)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            current_input_string = string(real(other.instructions[0][1]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
    }
}