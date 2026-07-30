/// @desc scr_node_step_macro_clr_screen(_draw_x)
/// Click handling for MACRO_CLR_SCREEN. Row anchors mirror the draw script.

function scr_node_step_macro_clr_screen(_draw_x) {

    // Backfill old saves to full slot count
    while (array_length(instructions[0]) <= 2) {
        array_push(instructions[0], 0);
    }

    var _lh = 14;
    var _ly = y + 28;

    // ── Row 1: BASE hex entry ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 48, _ly, _draw_x + width - 6, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 1;
            var _raw = real(other.instructions[0][1]);
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 4) _hex = "0" + _hex;
            current_input_string = _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _ly += _lh;

    // ── Row 2: FILL entry (decimal or $hex) ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 48, _ly, _draw_x + width - 6, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            current_input_string = string(real(other.instructions[0][2]));
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _ly += _lh;
}