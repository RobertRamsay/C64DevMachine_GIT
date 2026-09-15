/// @desc scr_node_step_macro_hud(_draw_x)
/// Click handling for MACRO_HUD. Row anchors mirror the draw script.
function scr_node_step_macro_hud(_draw_x) {

    // Backfill older saves to the full slot count (0..5).
    while (array_length(instructions[0]) <= 5) {
        var _n = array_length(instructions[0]);
        if (_n == 1) {
            array_push(instructions[0], "");        // asset name
        } else if (_n == 2) {
            array_push(instructions[0], 0x0400);    // screen base
        } else if (_n == 3) {
            array_push(instructions[0], 0xD800);    // colour base
        } else if (_n == 4) {
            array_push(instructions[0], 0);         // auto draw off
        } else {
            array_push(instructions[0], 1);         // write colour on
        }
    }

    var _lh = 14;
    var _ly = y + 28;

    // ===== HUD picker (slot 1) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "HUD_ASSET";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 1;
        exit;
    }
    _ly += _lh;

    // ===== SCREEN base (slot 2, hex) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 40, _ly, _draw_x + 110, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            var _hex = string_upper(decimal_to_hex(real(other.instructions[0][2])));
            while (string_length(_hex) < 4) { _hex = "0" + _hex; }
            current_input_string = "$" + _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // ===== COLOUR base (slot 3, hex) — same row =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 150, _ly, _draw_x + width - 6, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 3;
            var _hex2 = string_upper(decimal_to_hex(real(other.instructions[0][3])));
            while (string_length(_hex2) < 4) { _hex2 = "0" + _hex2; }
            current_input_string = "$" + _hex2;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _ly += _lh;

    // ===== AUTO DRAW (slot 4) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + 110, _ly + 13)) {
        var _auto = 0;
        if (is_real(instructions[0][4])) {
            _auto = real(instructions[0][4]);
        }
        if (_auto == 0) {
            instructions[0][4] = 1;
        } else {
            instructions[0][4] = 0;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }

    // ===== WRITE COLOUR (slot 5) — same row =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 118, _ly, _draw_x + width - 6, _ly + 13)) {
        var _dc = 1;
        if (is_real(instructions[0][5])) {
            _dc = real(instructions[0][5]);
        }
        if (_dc == 0) {
            instructions[0][5] = 1;
        } else {
            instructions[0][5] = 0;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
}
