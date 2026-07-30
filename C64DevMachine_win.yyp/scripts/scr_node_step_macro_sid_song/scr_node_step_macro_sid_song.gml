/// @desc scr_node_step_macro_sid_song(_draw_x)
/// Click handling for MACRO_SID_SONG. Row anchors mirror the draw script.

function scr_node_step_macro_sid_song(_draw_x) {

    // Backfill old saves to full slot count (0..5). Slots 4 and 5 are
    // reserved for the byte/text table export work and are unused today.
    while (array_length(instructions[0]) <= 5) {
        var _n = array_length(instructions[0]);
        if (_n == 1 || _n == 5) {
            array_push(instructions[0], "");
        } else if (_n == 4) {
            array_push(instructions[0], 2);      // hard restart frames
        } else if (_n == 2) {
            array_push(instructions[0], 1);      // auto_init defaults on
        } else if (_n == 3) {
            array_push(instructions[0], 0x03);   // ZP base
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;

    var _auto_init = is_real(instructions[0][2]) ? real(instructions[0][2]) : 1;

    // ===== SONG picker (slot 1) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "SOUND_ASSET";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 1;
        exit;
    }
    _ly += _lh;

    // ===== AUTO INIT checkbox (slot 2) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + width - 6, _ly + 13)) {
        if (_auto_init == 0) {
            instructions[0][2] = 1;
        } else {
            instructions[0][2] = 0;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ===== HARD RESTART (slot 4) — click to cycle 0..8 =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 150, _ly, _draw_x + width - 6, _ly + 13)) {
        var _hr_cur = is_real(instructions[0][4]) ? real(instructions[0][4]) : 2;
        _hr_cur += 1;
        if (_hr_cur > 8) {
            _hr_cur = 0;
        }
        instructions[0][4] = _hr_cur;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }

    // ===== ZP base (slot 3, hex) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 40, _ly, _draw_x + 116, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 3;
            var _hex = string_upper(decimal_to_hex(real(other.instructions[0][3])));
            while (string_length(_hex) < 2) _hex = "0" + _hex;
            current_input_string = "$" + _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}