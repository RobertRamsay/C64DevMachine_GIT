/// @desc Step click handler for CLEAR BMP RECT
function scr_node_step_macro_clear_bmp_rect(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;

    while (array_length(instructions[0]) < 6) {
        array_push(instructions[0], 0);
    }

    var _open_addr = function(_idx) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = _idx;
            var _raw = real(other.instructions[0][_idx]);
            var _h   = string_upper(decimal_to_hex(_raw));
            while (string_length(_h) < 4) _h = "0" + _h;
            current_input_string = _h;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
    };
    var _open_num = function(_idx) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = _idx;
            current_input_string = string(real(other.instructions[0][_idx]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
    };

    // Row 1: BMP addr
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 66, _fy, _draw_x + 130, _fy + 12)) {
        _open_addr(1); exit;
    }
    _fy += _line_h;

    // Row 2: COL / ROW
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 36,  _fy, _draw_x + 66,  _fy + 12)) { _open_num(2); exit; }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 98,  _fy, _draw_x + 128, _fy + 12)) { _open_num(3); exit; }
    _fy += _line_h;

    // Row 3: W / H
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 36,  _fy, _draw_x + 66,  _fy + 12)) { _open_num(4); exit; }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 98,  _fy, _draw_x + 128, _fy + 12)) { _open_num(5); exit; }
}