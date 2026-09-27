/// @function scr_node_step_macro_code(_draw_x)
function scr_node_step_macro_code(_draw_x) {
    if (!mouse_check_button_pressed(mb_left)) return;

    var _ly = y + 24 + 4;

    // Descriptor click -> edit descriptor (uses old is_entering_text system)
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x, _ly, _draw_x + width, _ly + 16)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = -2;
            current_input_string = other.code_descriptor;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        return;
    }
    _ly += 18;

    // EDIT button click -> open dedicated code editor
    var _btn_x1 = _draw_x + 10;
    var _btn_y1 = _ly + 4;
    var _btn_x2 = _draw_x + width - 8;
    var _btn_y2 = _btn_y1 + 16;
    if (point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2)) {
        scr_code_editor_open(id);
        return;
    }
}

