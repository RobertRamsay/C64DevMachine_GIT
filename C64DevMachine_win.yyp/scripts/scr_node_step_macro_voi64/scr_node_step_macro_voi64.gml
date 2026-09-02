/// @desc Click handling for both Voi64 nodes. Row anchors mirror the draw
///       script exactly — if one moves, the other has to move with it.

function scr_node_step_macro_voi64_master(_draw_x) {
    var _lh = 14;
    var _fy = y + 28;
    var _x1 = _draw_x + 8;
    var _x2 = _draw_x + width - 8;

    // Rows 0-4 are all numeric entry: pitch, speed, throat, mouth, zp.
    // Index 5 (zp) is hex, the rest decimal — scr_node_commit sorts that
    // out; this only has to open the editor on the right slot.
    var _slots = [1, 2, 3, 4, 5];
    for (var _k = 0; _k < 5; _k++) {
        if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
            var _idx = _slots[_k];
            while (array_length(instructions[0]) <= _idx) {
                array_push(instructions[0], 0);
            }
            var _cur = is_real(instructions[0][_idx]) ? real(instructions[0][_idx]) : 0;
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = _idx;
                if (_idx == 5) {
                    var _h = string_upper(decimal_to_hex(_cur));
                    while (string_length(_h) < 2) { _h = "0" + _h; }
                    current_input_string = _h;
                } else {
                    current_input_string = string(_cur);
                }
                keyboard_string = "";
                cursor_pos      = string_length(current_input_string);
            }
            exit;
        }
        _fy += _lh;
    }
}

function scr_node_step_macro_voi64_say(_draw_x) {
    var _lh = 14;
    var _fy = y + 28;
    var _x1 = _draw_x + 8;
    var _x2 = _draw_x + width - 8;

    // Row 0 — MODE toggle
    if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
        while (array_length(instructions[0]) <= 3) { array_push(instructions[0], 0); }
        var _m = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
        instructions[0][3] = (_m == 1) ? 0 : 1;
        global.addresses_dirty = true;
        exit;
    }
    _fy += _lh;

    // Row 1 — SRC toggle
    if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
        while (array_length(instructions[0]) <= 4) { array_push(instructions[0], 0); }
        var _s = 0;
        if (is_real(instructions[0][4])) { _s = real(instructions[0][4]); }
        if (_s == 1) {
            instructions[0][4] = 0;
        } else {
            instructions[0][4] = 1;
        }
        // The range rows appear and disappear with this toggle, so the node
        // changes height. Height is derived in Draw and the layout runs in
        // Step, so raising the flag alone leaves a gap under the node until
        // something else moves; relayout_frames is the mechanism that
        // actually re-runs the pass.
        height_dirty           = true;
        global.addresses_dirty = true;
        global.relayout_frames = 3;
        exit;
    }
    _fy += _lh;

    // Row 2 — the phrase. INLINE mode opens the text editor; TEXT_DATA
    // mode opens the asset picker, because an asset is chosen, not typed.
    if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
        var _src = 0;
        if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) {
            _src = real(instructions[0][4]);
        }
        while (array_length(instructions[0]) <= 6) { array_push(instructions[0], ""); }

        if (_src == 1) {
            // The shared TEXT_ASSET picker — the same scrolling list
            // MACRO_SID_SOUND uses for its note lists. It filters the asset
            // list to TEXT_DATA and writes the chosen name into
            // instructions[0][label_picker_index] on commit, so nothing
            // node-specific is needed beyond pointing it at slot 6.
            label_picker_open       = true;
            global.any_picker_open  = true;
            label_picker_prev_depth = depth;
            depth                   = -9999;
            label_picker_mode       = "TEXT_ASSET";
            label_picker_scroll     = 0;
            label_picker_list       = [];
            label_picker_target     = id;
            label_picker_index      = 6;
            exit;
        }

        with (obj_workspace_manager) {
            is_entering_text     = true;
            input_target_node    = other.id;
            input_target_index   = 5;
            current_input_string = string(other.instructions[0][5]);
            keyboard_string      = "";
            cursor_pos           = string_length(current_input_string);
        }
        exit;
    }
    _fy += _lh;

    // LINES range rows, TEXT DATA mode only — they are not drawn in INLINE
    // mode, so they must not be clickable there either or every override
    // row below would be off by two.
    var _srcm = 0;
    if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) {
        _srcm = real(instructions[0][4]);
    }
    if (_srcm == 1) {
        var _vbw = 30;
        var _vbx = _draw_x + width - 8 - _vbw;
        for (var _r = 0; _r < 2; _r++) {
            var _mi = 13 + (_r * 2);          // 13 = FROM mode, 15 = TO mode
            var _vi = 14 + (_r * 2);          // 14 = FROM var,  16 = TO var
            var _li = 11 + _r;                // 11 = FROM lit,  12 = TO lit
            while (array_length(instructions[0]) <= 16) {
                var _pn = array_length(instructions[0]);
                if (_pn == 14 || _pn == 16) {
                    array_push(instructions[0], "");
                } else {
                    array_push(instructions[0], 0);
                }
            }

            // VAR / LIT toggle
            if (point_in_rectangle(mouse_x, mouse_y, _vbx, _fy + 1, _vbx + _vbw, _fy + 11)) {
                var _cm = 0;
                if (is_real(instructions[0][_mi])) { _cm = real(instructions[0][_mi]); }
                if (_cm == 1) {
                    instructions[0][_mi] = 0;
                    instructions[0][_vi] = "";
                } else {
                    instructions[0][_mi] = 1;
                }
                global.addresses_dirty = true;
                global.undo_dirty      = true;
                exit;
            }

            // Value: picker in VAR mode, numeric entry in LIT mode.
            if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _vbx - 2, _fy + 12)) {
                var _m2 = 0;
                if (is_real(instructions[0][_mi])) { _m2 = real(instructions[0][_mi]); }
                if (_m2 == 1) {
                    label_picker_open       = true;
                    global.any_picker_open  = true;
                    label_picker_prev_depth = depth;
                    depth                   = -9999;
                    label_picker_mode       = "VAR";
                    label_picker_tab        = "UV";
                    label_picker_scroll     = 0;
                    label_picker_list       = [];
                    label_picker_target     = id;
                    label_picker_index      = _vi;
                    // Line numbers are byte values, so only byte vars are
                    // offered - a word var would silently use its low byte.
                    label_picker_byte_only  = true;
                    exit;
                }
                var _rv = 0;
                if (is_real(instructions[0][_li])) { _rv = real(instructions[0][_li]); }
                with (obj_workspace_manager) {
                    is_entering_text     = true;
                    input_target_node    = other.id;
                    input_target_index   = _li;
                    if (_rv <= 0) {
                        current_input_string = "";
                    } else {
                        current_input_string = string(_rv);
                    }
                    keyboard_string = "";
                    cursor_pos      = string_length(current_input_string);
                }
                exit;
            }
            _fy += _lh;
        }
    }

    // Rows 3-6 — per-say overrides. Right click clears one back to
    // inherit; typing -1 does the same thing from the keyboard.
    for (var _k = 0; _k < 4; _k++) {
        if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy, _x2, _fy + 12)) {
            var _oi = 7 + _k;
            while (array_length(instructions[0]) <= _oi) { array_push(instructions[0], -1); }
            var _cv = is_real(instructions[0][_oi]) ? real(instructions[0][_oi]) : -1;
            with (obj_workspace_manager) {
                is_entering_text     = true;
                input_target_node    = other.id;
                input_target_index   = _oi;
                current_input_string = (_cv < 0) ? "" : string(_cv);
                keyboard_string      = "";
                cursor_pos           = string_length(current_input_string);
            }
            exit;
        }
        _fy += _lh;
    }

    // Row 7 — PREVIEW VOICE
    if (point_in_rectangle(mouse_x, mouse_y, _x1, _fy + 1, _x2, _fy + 14)) {
        var _ph = scr_voi64_say_phoneme_string(id);
        if (string_trim(_ph) == "") {
            show_debug_message("VOI64 PREVIEW: nothing to say");
        } else {
            var _v = scr_voi64_effective_voice(id);
            show_debug_message("VOI64 PREVIEW: " + _ph);
            scr_voi64_say_phonemes(_ph, _v.pitch, _v.speed, _v.throat, _v.mouth);
        }
        exit;
    }
}
