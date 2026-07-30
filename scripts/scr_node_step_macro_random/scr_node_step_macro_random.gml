/// @desc scr_node_step_macro_random(_draw_x)
/// Click handling for MACRO_RANDOM. Row anchors mirror the draw script.

function scr_node_step_macro_random(_draw_x) {

    // Backfill old saves to full slot count (0..8)
    while (array_length(instructions[0]) <= 8) {
        var _n = array_length(instructions[0]);
        if (_n == 7) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;

    var _init_osc = 0;
    if (is_real(instructions[0][1])) { _init_osc = real(instructions[0][1]); }

    var _clamp_on = 0;
    if (is_real(instructions[0][3])) { _clamp_on = real(instructions[0][3]); }

    var _dst_mode = 0;
    if (is_real(instructions[0][6])) { _dst_mode = real(instructions[0][6]); }

    // ── Row 0: INIT OSC checkbox ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + width - 6, _ly + 13)) {
        var _iv = 0;
        if (is_real(instructions[0][1])) { _iv = real(instructions[0][1]); }
        if (_iv == 0) {
            instructions[0][1] = 1;
        } else {
            instructions[0][1] = 0;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 1: FREQ hex entry (only if init on) ──
    if (_init_osc == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 52, _ly, _draw_x + 128, _ly + 13)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 2;
                var _raw = real(other.instructions[0][2]);
                var _hex = string_upper(decimal_to_hex(_raw));
                while (string_length(_hex) < 4) _hex = "0" + _hex;
                current_input_string = "$" + _hex;
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
    }
    _ly += _lh;

    // ── Row 2: CLAMP checkbox ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 8, _ly, _draw_x + width - 6, _ly + 13)) {
        var _cv = 0;
        if (is_real(instructions[0][3])) { _cv = real(instructions[0][3]); }
        if (_cv == 0) {
            instructions[0][3] = 1;
        } else {
            instructions[0][3] = 0;
        }
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 3: MIN / MAX decimal entry (only if clamp on) ──
    if (_clamp_on == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 46, _ly, _draw_x + 104, _ly + 13)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 4;
                current_input_string = string(real(other.instructions[0][4]));
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 152, _ly, _draw_x + width - 6, _ly + 13)) {
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = 5;
                current_input_string = string(real(other.instructions[0][5]));
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
    }
    _ly += _lh;

    // ── Row 4: DEST toggle A / VAR ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 58, _ly, _draw_x + 86, _ly + 13)) {
        instructions[0][6] = 0;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 92, _ly, _draw_x + 140, _ly + 13)) {
        instructions[0][6] = 1;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 5: DEST VAR picker (only if dst_mode == VAR) ──
    if (_dst_mode == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 6, _ly + 13)) {
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "VAR";
            label_picker_tab        = "UV";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 7;
            exit;
        }
    }
    _ly += _lh;

    // ── Row 6: ZP hex entry ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 40, _ly, _draw_x + 116, _ly + 13)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 8;
            var _raw = real(other.instructions[0][8]);
            var _hex = string_upper(decimal_to_hex(_raw));
            while (string_length(_hex) < 2) _hex = "0" + _hex;
            current_input_string = "$" + _hex;
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
}