/// @desc Step click handler for MOVE_BMP_BLOCK
function scr_node_step_macro_move_bmp_block(_draw_x) {
    var _header_h = 24;
    var _line_h   = 12;
    var _fy       = y + _header_h + 4;

    // Backfill (see draw script for rationale).
    var _had_14 = (array_length(instructions[0]) == 14);
    var _had_16 = (array_length(instructions[0]) == 16);
    while (array_length(instructions[0]) < 19) {
        array_push(instructions[0], 0);
    }
    while (array_length(instructions[0]) < 21) {
        array_push(instructions[0], (array_length(instructions[0]) == 19) ? 0 : "");
    }
    if (!is_real(instructions[0][19])) { instructions[0][19] = 0; }
    if (_had_14) {
        instructions[0][14] = 1;
        instructions[0][15] = 1;
    }
    if (_had_14 || _had_16) {
        instructions[0][16] = 0;
        instructions[0][17] = "";
        instructions[0][18] = "";
    }

    var _src_mode   = is_real(instructions[0][16]) ? real(instructions[0][16]) : 0;
    var _write_coll = is_real(instructions[0][19]) ? real(instructions[0][19]) : 0;

    // Helper to open hex address editor
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
    // Helper to open numeric editor
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
    // Helper to open a VAR picker on the UV tab
    var _open_var = function(_idx) {
        label_picker_open       = true;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_target     = id;
        label_picker_scroll     = 0;
        label_picker_prev_depth = depth;
        depth                   = -10000;
        global.any_picker_open  = true;
        label_picker_index      = _idx;
    };

    // Row 1: SRC BMP addr
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 66, _fy, _draw_x + 130, _fy + 12)) {
        _open_addr(1); exit;
    }
    _fy += _line_h;
    // Row 2: DST BMP addr
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 66, _fy, _draw_x + 130, _fy + 12)) {
        _open_addr(2); exit;
    }
    _fy += _line_h;

    // Row 3: SRC MODE toggle (LIT <-> ASSET)
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
        if (_src_mode == 0) {
            instructions[0][16] = 1;
        } else {
            instructions[0][16] = 0;
        }
        global.addresses_dirty = true;
        exit;
    }
    _fy += _line_h;

    if (_src_mode == 1) {
        // ── ASSET MODE ROWS ──
        // Row 4: BYTE_DATA list picker — same mechanism MACRO_PLACE_CHAR uses.
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
            label_picker_open       = true;
            label_picker_mode       = "BYTE_ASSET";
            label_picker_target     = id;
            label_picker_index      = 17;
            label_picker_scroll     = 0;
            label_picker_prev_depth = depth;
            depth                   = -10000;
            global.any_picker_open  = true;
            exit;
        }
        _fy += _line_h;

        // Row 5: ENTRY VAR picker
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
            _open_var(18);
            exit;
        }
        _fy += _line_h;

        // Row 6: record-layout reminder line (not clickable)
        _fy += _line_h;

        // Row 7: asset info line (only drawn when an asset is picked)
        if (string(instructions[0][17]) != "") {
            _fy += _line_h;
        }
    } else {
        // ── LIT MODE ROWS ──
        // Row 4: SX / SY
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 24, _fy, _draw_x + 56,  _fy + 12)) { _open_num(3); exit; }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 76, _fy, _draw_x + 108, _fy + 12)) { _open_num(4); exit; }
        _fy += _line_h;
        // Row 5: DX / DY
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 24, _fy, _draw_x + 56,  _fy + 12)) { _open_num(5); exit; }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 76, _fy, _draw_x + 108, _fy + 12)) { _open_num(6); exit; }
        _fy += _line_h;
        // Row 6: W / H
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 24, _fy, _draw_x + 56,  _fy + 12)) { _open_num(7); exit; }
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 76, _fy, _draw_x + 108, _fy + 12)) { _open_num(8); exit; }
        _fy += _line_h;
        // Rows 7-10: VAR pickers
        var _var_indices = [9, 10, 11, 12];
        for (var _vi = 0; _vi < 4; _vi++) {
            if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
                _open_var(_var_indices[_vi]);
                exit;
            }
            _fy += _line_h;
        }
    }

    // ── SHARED ROWS ──
    // BLEND toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
        var _cur_b = is_real(instructions[0][14]) ? real(instructions[0][14]) : 0;
        if (_cur_b == 0) {
            instructions[0][14] = 1;
        } else {
            instructions[0][14] = 0;
        }
        global.addresses_dirty = true;
        exit;
    }
    _fy += _line_h;
    // SCREEN RAM toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
        var _cur_s = is_real(instructions[0][15]) ? real(instructions[0][15]) : 1;
        if (_cur_s == 1) {
            instructions[0][15] = 0;
        } else {
            instructions[0][15] = 1;
        }
        global.addresses_dirty = true;
        exit;
    }
    _fy += _line_h;
    // COLOUR RAM toggle
    if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
        var _cur_c = is_real(instructions[0][13]) ? real(instructions[0][13]) : 1;
        if (_cur_c == 1) {
            instructions[0][13] = 0;
        } else {
            instructions[0][13] = 1;
        }
        global.addresses_dirty = true;
        exit;
    }
    _fy += _line_h;

    // WRITE COLL toggle (ASSET mode only — in LIT mode the row is a static note)
    if (_src_mode == 1) {
        if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
            instructions[0][19] = (_write_coll == 1) ? 0 : 1;
            global.addresses_dirty = true;
            exit;
        }
        _fy += _line_h;

        // BBT picker row — only present when WRITE COLL is on.
        if (_write_coll == 1) {
            if (point_in_rectangle(mouse_x, mouse_y, _draw_x + 4, _fy, _draw_x + width - 8, _fy + 12)) {
                label_picker_open       = true;
                label_picker_mode       = "BYTE_ASSET";
                label_picker_target     = id;
                label_picker_index      = 20;
                label_picker_scroll     = 0;
                label_picker_prev_depth = depth;
                depth                   = -10000;
                global.any_picker_open  = true;
                exit;
            }
        }
    }
}