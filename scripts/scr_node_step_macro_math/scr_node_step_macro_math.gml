/// @desc scr_node_step_macro_math(_draw_x)
/// Click handling for MACRO_MATH. Row anchors mirror the draw script.

function scr_node_step_macro_math(_draw_x) {

    // Backfill old saves to full slot count
    while (array_length(instructions[0]) <= 6) {
        var _mmn = array_length(instructions[0]);
        if (_mmn == 2 || _mmn == 5 || _mmn == 6) {
            array_push(instructions[0], "");
        } else {
            array_push(instructions[0], 0);
        }
    }

    var _lh = 14;
    var _ly = y + 28;
    var _vbtn_w = 28;

    var _op = is_real(instructions[0][1]) ? real(instructions[0][1]) : 0;

    // ── Row 1: OP cycle 0..5 ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 52, _ly, _draw_x + width - 10, _ly + 13)) {
        instructions[0][1] = (_op + 1) mod 6;
        global.addresses_dirty = true;
        global.undo_dirty      = true;
        exit;
    }
    _ly += _lh;

    // ── Row 2: IN (VAR1) picker ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 10, _ly + 13)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 2;
        exit;
    }
    _ly += _lh;

    // ── Row 3: OPERAND — two-input ops only ──
    if (_op <= 3) {
        // LIT/VAR toggle (right)
        var _tvx = _draw_x + width - 38;
        if (point_in_rectangle(mouse_x, mouse_y, _tvx, _ly + 1, _tvx + _vbtn_w, _ly + 13)) {
            var _om = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
            instructions[0][3] = (_om == 0) ? 1 : 0;
            if (instructions[0][3] == 0) instructions[0][5] = "";
            global.addresses_dirty = true;
            global.undo_dirty      = true;
            exit;
        }
        // value / var (left)
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _tvx - 2, _ly + 13)) {
            if (real(instructions[0][3]) == 1) {
                label_picker_open       = true;
                global.any_picker_open  = true;
                label_picker_prev_depth = depth;
                depth                   = -9999;
                label_picker_mode       = "VAR";
                label_picker_tab        = "UV";
                label_picker_scroll     = 0;
                label_picker_list       = [];
                label_picker_target     = id;
                label_picker_index      = 5;
            } else {
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = 4;
                    current_input_string = string(real(other.instructions[0][4]));
                    keyboard_string      = "";
                    cursor_pos           = string_length(current_input_string);
                }
            }
            exit;
        }
    }
    _ly += _lh;

    // ── Row 4: OUT (VAR3) picker ──
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _ly, _draw_x + width - 10, _ly + 13)) {
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
        exit;
    }
    _ly += _lh;
}