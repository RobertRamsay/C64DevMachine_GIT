/// @desc Handle LMB clicks for COND_IF_WORD nodes
/// Mirrors scr_node_step_cond_if, but both VAR pickers filter to
/// encoding == "word" and the literal field accepts 4 hex digits.
function scr_node_step_cond_if_word(_draw_x) {

    var _header_h = 24;
    var _line_h   = 16;
    var _inst     = instructions[0];
    var _lx       = _draw_x + 8;
    var _rx       = _draw_x + width - 6;
    var _cy       = y + _header_h + 4;

    // ── Row 0: VAR — open VAR picker (word vars only) ─────────────
    var _var_bx1 = _lx + 42;
    var _var_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _var_bx1, _cy + 4, _var_bx2, _cy + 10)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_target     = id;
        label_picker_index      = 1;
        label_picker_word_only  = true;
        label_picker_byte_only  = false;
        exit;
    }
    _cy += _line_h;

    // ── Row 1 left: mode toggle ───────────────────────────────────
    var _op_bx1 = _lx;
    var _op_bx2 = _lx + 44;
    if (point_in_rectangle(mouse_x, mouse_y, _op_bx1, _cy + 4, _op_bx2, _cy + 10)) {
        var _modes = ["eq", "ne", "lt", "gte", "gt", "lte"];
        var _cur_mode = string(_inst[4]);
        var _cur_idx = 0;
        for (var _mi = 0; _mi < array_length(_modes); _mi++) {
            if (_modes[_mi] == _cur_mode) { _cur_idx = _mi; break; }
        }
        instructions[0][4] = _modes[(_cur_idx + 1) mod array_length(_modes)];
        global.addresses_dirty = true;
		global.undo_dirty      = true;
        scr_c64_do_update_addresses();
        exit;
    }

    // ── Row 1 right: CMP value (left half) + CMP VAR picker ───────
    var _cmp_var     = (array_length(_inst) > 5) ? string(_inst[5]) : "";
    var _has_cmp_var = (_cmp_var != "" && _cmp_var != "0");
    var _mid_x       = _op_bx2 + 4 + ((_rx - (_op_bx2 + 4)) / 2) - 2;

    // Left: 16-bit literal — only clickable when no cmp var set
    var _cval_bx1 = _op_bx2 + 4;
    var _cval_bx2 = _mid_x;
    if (!_has_cmp_var && point_in_rectangle(mouse_x, mouse_y, _cval_bx1, _cy + 4, _cval_bx2, _cy + 10)) {
        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 2;
            var _v = real(other.instructions[0][2]);
            if (global.use_hex_display) {
                var _vh = decimal_to_hex(_v);
                while (string_length(_vh) < 4) _vh = "0" + _vh;
                current_input_string = "$" + string_upper(_vh);
            } else {
                current_input_string = string(_v);
            }
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }

    // Right: CMP VAR picker (word vars only)
    var _cvar_bx1 = _mid_x + 2;
    if (_has_cmp_var) {
        _cvar_bx1 = _op_bx2 + 4;
    }
    var _cvar_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _cvar_bx1, _cy + 4, _cvar_bx2, _cy + 10)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_target     = id;
        label_picker_index      = 5;
        label_picker_word_only  = true;
        label_picker_byte_only  = false;
        exit;
    }
    _cy += _line_h;

    // ── Row 2: GOTO label ─────────────────────────────────────────
    var _tgt_bx1 = _lx + 48;
    var _tgt_bx2 = _rx;
    if (point_in_rectangle(mouse_x, mouse_y, _tgt_bx1, _cy + 4, _tgt_bx2, _cy + 10)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "JUMP";
        label_picker_index      = 3;
        label_picker_scroll     = 0;
        label_picker_list       = [];
        with (obj_c64_node) {
            if (node_type == "LABEL") {
                array_push(other.label_picker_list, string(instructions[0][1]));
            }
        }
        exit;
    }
    _cy += _line_h;

}