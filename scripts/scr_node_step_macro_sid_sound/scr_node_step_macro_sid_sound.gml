/// @desc scr_node_step_macro_sid_sound(_draw_x)
/// Click handling for MACRO_SID_SOUND. Row anchors mirror the draw script.

function scr_node_step_macro_sid_sound(_draw_x) {

    // Backfill old saves to full slot count (0..28)
    while (array_length(instructions[0]) <= 28) {
        var _n = array_length(instructions[0]);
        if (_n == 3 || _n == 6 || _n == 9 || _n == 12 || _n == 15 || _n == 19
         || _n == 21 || _n == 24 || _n == 25 || _n == 28) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;
    var _vbtn_w = 28;
    var _vx = _draw_x + width - 38;

    var _voice_mode = is_real(instructions[0][1])  ? real(instructions[0][1])  : 0;
    var _note_mode  = is_real(instructions[0][4])  ? real(instructions[0][4])  : 0;
    var _wave_mode  = is_real(instructions[0][7])  ? real(instructions[0][7])  : 0;
    var _ad_mode    = is_real(instructions[0][10]) ? real(instructions[0][10]) : 0;
    var _sr_mode    = is_real(instructions[0][13]) ? real(instructions[0][13]) : 0;
    var _pulse_on   = is_real(instructions[0][16]) ? real(instructions[0][16]) : 0;
    var _pw_mode    = is_real(instructions[0][17]) ? real(instructions[0][17]) : 0;
    var _off_mode   = is_real(instructions[0][22]) ? real(instructions[0][22]) : 0;
    var _woff_mode  = is_real(instructions[0][26]) ? real(instructions[0][26]) : 0;

    // ===== VOICE (mode slot 1, lit 2 cycles, var 3) =====
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
        instructions[0][1] = (_voice_mode == 0) ? 1 : 0;
        if (instructions[0][1] == 0) instructions[0][3] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
        if (_voice_mode == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 3;
        } else {
            var _vl = is_real(instructions[0][2]) ? clamp(real(instructions[0][2]), 0, 2) : 0;
            instructions[0][2] = (_vl + 1) mod 3;
            global.addresses_dirty = true;
            global.undo_dirty      = true;
        }
        exit;
    }
    _ly += _lh;

    // ===== NOTE (mode 4 cycles LIT/VAR/ASSET, lit 5 text, var 6) =====
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
        instructions[0][4] = (_note_mode + 1) mod 3;
        if (instructions[0][4] != 1) {
            instructions[0][6] = "";
        }
        height_dirty           = true;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
        if (_note_mode == 2) {
            // Value cell is inert in ASSET mode — the LIST row below owns it.
        } else if (_note_mode == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 6;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 5;
                var _raw = real(other.instructions[0][5]);
                var _hex = string_upper(decimal_to_hex(_raw));
                while (string_length(_hex) < 4) _hex = "0" + _hex;
                current_input_string = "$" + _hex;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ===== NOTE LIST + IDX (ASSET mode only) =====
    if (_note_mode == 2) {
        // LIST row — TEXT_DATA picker
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "TEXT_ASSET";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 21;
            exit;
        }
        _ly += _lh;

        // IDX row — VAR toggle on the right, value/picker on the left
        if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
            instructions[0][22] = (_off_mode == 0) ? 1 : 0;
            if (instructions[0][22] == 0) {
                instructions[0][24] = "";
            }
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
            if (_off_mode == 1) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_mode       = "VAR";
                label_picker_tab        = "UV";
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_target     = id;
                label_picker_index      = 24;
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 23;
                    current_input_string = string(real(other.instructions[0][23]));
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
        _ly += _lh;

        // Note-count footer row — not clickable
        _ly += _lh;
    }

    // ===== WAVE (mode 7 cycles LIT/VAR/ASSET, lit 8 hex, var 9) =====
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
        instructions[0][7] = (_wave_mode + 1) mod 3;
        if (instructions[0][7] != 1) {
            instructions[0][9] = "";
        }
        height_dirty           = true;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
        if (_wave_mode == 2) {
            // Value cell is inert in ASSET mode — the WLST row below owns it.
        } else if (_wave_mode == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 9;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 8;
                var _hex = string_upper(decimal_to_hex(real(other.instructions[0][8])));
                while (string_length(_hex) < 2) _hex = "0" + _hex;
                current_input_string = "$" + _hex;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ===== WAVE LIST + WIDX (ASSET mode only) =====
    if (_wave_mode == 2) {
        // WLST row — BYTE_DATA picker
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "BYTE_ASSET";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 25;
            exit;
        }
        _ly += _lh;

        // WIDX row — VAR toggle on the right, value/picker on the left
        if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
            instructions[0][26] = (_woff_mode == 0) ? 1 : 0;
            if (instructions[0][26] == 0) {
                instructions[0][28] = "";
            }
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
            if (_woff_mode == 1) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_mode       = "VAR";
                label_picker_tab        = "UV";
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_target     = id;
                label_picker_index      = 28;
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 27;
                    current_input_string = string(real(other.instructions[0][27]));
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
        _ly += _lh;

        // Byte-count footer row — not clickable
        _ly += _lh;
    };

    // ===== AD (mode 10, lit 11 hex, var 12) =====
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
        instructions[0][10] = (_ad_mode == 0) ? 1 : 0;
        if (instructions[0][10] == 0) instructions[0][12] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
        if (_ad_mode == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 12;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 11;
                var _hex = string_upper(decimal_to_hex(real(other.instructions[0][11])));
                while (string_length(_hex) < 2) _hex = "0" + _hex;
                current_input_string = "$" + _hex;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ===== SR (mode 13, lit 14 hex, var 15) =====
    if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
        instructions[0][13] = (_sr_mode == 0) ? 1 : 0;
        if (instructions[0][13] == 0) instructions[0][15] = "";
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
        if (_sr_mode == 1) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 15;
        } else {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 14;
                var _hex = string_upper(decimal_to_hex(real(other.instructions[0][14])));
                while (string_length(_hex) < 2) _hex = "0" + _hex;
                current_input_string = "$" + _hex;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
        }
        exit;
    }
    _ly += _lh;

    // ===== PULSE checkbox (slot 16) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + width - 6, _ly + 13)) {
        instructions[0][16] = (_pulse_on == 0) ? 1 : 0;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ===== PW (mode 17, lit 18 hex, var 19) — only if pulse on =====
    if (_pulse_on == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _vx, _ly + 1, _vx + _vbtn_w, _ly + 13)) {
            instructions[0][17] = (_pw_mode == 0) ? 1 : 0;
            if (instructions[0][17] == 0) instructions[0][19] = "";
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _vx - 2, _ly + 13)) {
            if (_pw_mode == 1) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_mode       = "VAR";
                label_picker_tab        = "UV";
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_target     = id;
                label_picker_index      = 19;
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 18;
                    var _hex = string_upper(decimal_to_hex(real(other.instructions[0][18])));
                    while (string_length(_hex) < 3) _hex = "0" + _hex;
                    current_input_string = "$" + _hex;
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
    }
    _ly += _lh;

    // ===== ZP (slot 20 hex) =====
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 40, _ly, _draw_x + 116, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 20;
            var _hex = string_upper(decimal_to_hex(real(other.instructions[0][20])));
            while (string_length(_hex) < 2) _hex = "0" + _hex;
            current_input_string = "$" + _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}